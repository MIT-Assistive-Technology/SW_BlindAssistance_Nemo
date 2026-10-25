//  PerceptionPipeline.swift
//  nemo-software
//
//  Wires the camera, detector, location, and speaker together. Receives every
//  frame from the active FrameProvider, runs object detection, speaks what was
//  seen, and publishes a simple presentation for the UI.
//
//  Threading: frames arrive on the provider's queue. At most one frame at a time is
//  processed on `perceptionQueue`; frames that arrive while it's busy, or faster than
//  `maxFramesPerSecond`, are dropped. Only the presentation (and speech) hop to the
//  main actor. Pixel buffers are released as soon as the frame is processed.
//

import CoreVideo
import Foundation
import ImageIO
import QuartzCore

/// Counters for the debug screen: is the camera delivering, and is perception keeping up?
nonisolated public struct FrameStats: Sendable {
  /// Frames delivered by the provider since the pipeline was created.
  public var received = 0
  /// Frames that went through the detector.
  public var processed = 0
  /// Frames skipped because perception was busy or over its rate cap.
  public var dropped: Int { received - processed }
  /// Processed frames per second, smoothed.
  public var processedPerSecond: Double = 0
  /// Detector time for the last processed frame, in milliseconds.
  public var lastProcessingMs: Double = 0
  /// Size of the last frame, as delivered (landscape).
  public var frameWidth = 0
  public var frameHeight = 0
}

/// Presentation data emitted to the UI each time a frame is processed.
nonisolated public struct FramePresentation {
  /// Raw detections from the object detector.
  public let detections: [Detection]

  /// Building numbers read from the camera. Held briefly so one missed frame does not clear them.
  public let numbers: [RecognizedNumber]

  /// Green street-name signs. When a destination is loaded, `text` is the bundle's spelling.
  public let streetSigns: [RecognizedStreetSign]

  /// Most recent device location/heading.
  public let location: LocationSnapshot?

  /// Frame flow counters.
  public let stats: FrameStats
}

/// Central coordinator. Implements `FrameProviderDelegate`.
nonisolated public final class PerceptionPipeline: FrameProviderDelegate, @unchecked Sendable {
  /// Called on the main actor after each processed frame.
  @MainActor public var onPresentation: ((FramePresentation) -> Void)?

  /// Upper bound on detector runs per second. The plan uses ≤ 10 for a door model and
  /// 2–3 for the text building check.
  public let maxFramesPerSecond: Double

  private let detector: ObjectDetector
  private let numberRecognizer: any NumberRecognizer
  private let locationProvider: LocationProvider
  private let speaker: Speaker
  private let spokenNumbers = SpokenNumbers()

  /// Only touched on `perceptionQueue`, except `expectedBundleTexts`, which uses `lock`.
  private var lastNumberRecognition: CFTimeInterval = 0
  private var heldNumbers: [RecognizedNumber] = []
  private var heldNumbersAt: CFTimeInterval = 0
  private var heldSigns: [RecognizedStreetSign] = []
  private var heldSignsAt: CFTimeInterval = 0
  private var expectedBundleTexts: [String] = []

  private let perceptionQueue = DispatchQueue(label: "nemo.perception", qos: .userInitiated)

  /// Guards `isBusy`, `lastStart` and `stats`, which are touched from the provider's queue
  /// and from `perceptionQueue`.
  private let lock = NSLock()
  private var isBusy = false
  private var lastStart: CFTimeInterval = 0
  private var stats = FrameStats()

  public init(
    detector: ObjectDetector,
    numberRecognizer: any NumberRecognizer,
    locationProvider: LocationProvider,
    speaker: Speaker,
    maxFramesPerSecond: Double = 10
  ) {
    self.detector = detector
    self.numberRecognizer = numberRecognizer
    self.locationProvider = locationProvider
    self.speaker = speaker
    self.maxFramesPerSecond = maxFramesPerSecond
  }

  /// Strings the building check is allowed to repeat: `recognize.text`, the entrance
  /// street, and the building name. Empty until a destination bundle is loaded.
  /// A green street sign is kept either way, but it is renamed to the bundle spelling
  /// when one of these matches. That matched string is what Jing's `BuildingSighting` takes.
  public func setExpectedBundleTexts(_ texts: [String]) {
    lock.withLock { expectedBundleTexts = texts }
  }

  // MARK: - FrameProviderDelegate

  /// Called on the provider's queue. Decides quickly whether to take the frame.
  public func processFrame(_ provider: any FrameProvider, buffer: CVPixelBuffer) {
    let now = CACurrentMediaTime()
    let accepted: Bool = lock.withLock {
      stats.received += 1
      stats.frameWidth = CVPixelBufferGetWidth(buffer)
      stats.frameHeight = CVPixelBufferGetHeight(buffer)
      // 10% slack so a 30 fps camera gives 10/s, not every 4th frame (7.5/s), under jitter.
      guard !isBusy, now - lastStart >= 0.9 / maxFramesPerSecond else { return false }
      isBusy = true
      if lastStart > 0 {
        let rate = 1 / (now - lastStart)
        stats.processedPerSecond =
          stats.processedPerSecond == 0 ? rate : stats.processedPerSecond * 0.9 + rate * 0.1
      }
      lastStart = now
      return true
    }
    guard accepted else { return }

    // Only one queue uses the buffer at a time: the provider hands it off here.
    nonisolated(unsafe) let buffer = buffer
    perceptionQueue.async { [self] in
      process(buffer)
    }
  }

  // MARK: - Processing

  /// Runs on `perceptionQueue`.
  private func process(_ buffer: CVPixelBuffer) {
    let started = CACurrentMediaTime()

    // Back camera frames arrive in landscape. For an iPhone held in portrait use `.right`,
    // or text recognition and detection quietly fail.
    // TODO: derive this from the device orientation if the app ever supports landscape.
    let orientation = CGImagePropertyOrientation.right

    // Run detection. Start by accepting everything above a confidence floor.
    let detections = detector.detect(
      buffer,
      filter: { detection in
        // TODO: Filter by confidence threshold, e.g. detection.confidence > 0.4.
        true
      },
      orientation: orientation
    )

    // Building-number check is 2–3 times a second. The buffer stays on this queue and is
    // released when `process` returns, which is what the camera provider requires.
    let fresh = recognizeText(in: buffer, orientation: orientation, now: started)

    let snapshot: FrameStats = lock.withLock {
      stats.processed += 1
      stats.lastProcessingMs = (CACurrentMediaTime() - started) * 1000
      isBusy = false
      return stats
    }

    // `buffer` is not captured below, so the camera gets it back now.
    let visibleNumbers = heldNumbers
    let visibleSigns = heldSigns
    let phrase = spokenNumbers.phrase(for: fresh.numbers)
    let signPhrase = spokenNumbers.phrase(forSign: fresh.streetSigns.first?.text)
    Task { @MainActor [self] in
      // Speak the most interesting detection(s) so the user gets audio feedback.
      // TODO: Avoid repeating the same label on every frame (add a chatter guard), and move
      // announcements to FeedbackKit events.
      if let top = detections.first {
        speaker.speak(top.labels.first?.identifier ?? "something")
      }
      if let phrase {
        speaker.speak(phrase)
      }
      if let signPhrase {
        speaker.speak(signPhrase)
      }

      // LocationService is main-actor, so the snapshot is read here, a few ms after capture.
      // TODO: attach location at capture time once LocationService is thread-safe (FE-3).
      onPresentation?(
        FramePresentation(
          detections: detections,
          numbers: visibleNumbers,
          streetSigns: visibleSigns,
          location: locationProvider.currentSnapshot,
          stats: snapshot
        ))
    }
  }

  /// Runs on `perceptionQueue`. Returns this frame's reads, not the held lists.
  private func recognizeText(
    in buffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    now: CFTimeInterval
  ) -> CameraTextRead {
    guard now - lastNumberRecognition >= 0.4 else { return CameraTextRead() }
    lastNumberRecognition = now
    let expected = lock.withLock { expectedBundleTexts }
    let read = numberRecognizer.read(buffer, orientation: orientation, expectedBundleTexts: expected)
    if read.numbers.isEmpty {
      if now - heldNumbersAt > 1.5 { heldNumbers = [] }
    } else {
      heldNumbers = read.numbers
      heldNumbersAt = now
    }
    if read.streetSigns.isEmpty {
      if now - heldSignsAt > 1.5 { heldSigns = [] }
    } else {
      heldSigns = read.streetSigns
      heldSignsAt = now
    }
    return read
  }
}

/// Doesn't repeat the same building number on every check.
private nonisolated final class SpokenNumbers: @unchecked Sendable {
  private let lock = NSLock()
  private var lastValue: String?
  private var lastAt = Date.distantPast

  func phrase(for numbers: [RecognizedNumber]) -> String? {
    guard let top = numbers.first else { return nil }
    let now = Date()
    lock.lock()
    defer { lock.unlock() }
    if lastValue == top.value, now.timeIntervalSince(lastAt) < 6 { return nil }
    lastValue = top.value
    lastAt = now
    return "Number \(top.value)"
  }

  func phrase(forSign text: String?) -> String? {
    guard let text else { return nil }
    let now = Date()
    lock.lock()
    defer { lock.unlock() }
    if lastSign == text, now.timeIntervalSince(lastSignAt) < 6 { return nil }
    lastSign = text
    lastSignAt = now
    return "Sign \(text)"
  }

  private var lastSign: String?
  private var lastSignAt = Date.distantPast
}
