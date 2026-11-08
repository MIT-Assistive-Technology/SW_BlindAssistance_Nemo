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

  /// Called on the main actor with each fresh text read, so navigation can turn a
  /// building number into a `BuildingSighting` (CV-9 → FE-10). Wired in `AppServices`.
  @MainActor public var onTextRead: ((CameraTextRead) -> Void)?

  /// Called on the main actor with this frame's detections (already filtered), so the
  /// hazard path can turn them into `HazardSighting`s. Wired in `AppServices`.
  @MainActor public var onDetections: (([Detection]) -> Void)?

  /// Called on the main actor with the free-space scan built from the monocular
  /// depth estimator. Only fires when `depthEstimator` is set — on LiDAR phones the
  /// scan comes from `ARGuide.onFreeSpace` instead.
  @MainActor public var onFreeSpace: ((FreeSpace) -> Void)?

  /// Monocular depth for phones without LiDAR (Depth Anything V2 Small). Runs on
  /// `perceptionQueue` at most every `depthEstimateInterval` seconds; nil means no
  /// estimator, so nothing extra runs on LiDAR phones.
  public var depthEstimator: (any DepthEstimator)?

  /// How often the estimator runs, when set. Relative depth is a second estimate on
  /// top of the 10 fps detection cap; 2 Hz is enough for hazards and kind to battery.
  public var depthEstimateInterval: CFTimeInterval = 0.5

  /// Speak raw reads ("Number 77", "Sign …") for the debug screen. Off during a walk,
  /// where `NavigationSession` speaks the reviewed phrases instead.
  @MainActor public var announcesReads = true

  private let detector: ObjectDetector
  private let numberRecognizer: any NumberRecognizer
  private let locationProvider: LocationProvider
  private let speaker: any SpeechOutput
  private let spokenNumbers = SpokenNumbers()

  /// Only touched on `perceptionQueue`, except `expectedBundleTexts`, which uses `lock`.
  private var lastNumberRecognition: CFTimeInterval = 0
  private var lastDepthEstimate: CFTimeInterval = 0
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
    speaker: any SpeechOutput,
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

    // Run detection, accepting everything above a confidence floor. The session's
    // own `minSightingConfidence` gate decides what becomes a hazard.
    let detections = detector.detect(
      buffer,
      filter: { detection in detection.confidence > 0.4 },
      orientation: orientation
    )

    // Monocular depth for phones without LiDAR: a relative scan on its own cadence.
    // On LiDAR phones `depthEstimator` is nil and ARGuide's sceneDepth scan runs
    // instead, so the two never duplicate.
    let freeSpace: FreeSpace?
    if let depthEstimator, started - lastDepthEstimate >= depthEstimateInterval,
      let disparity = depthEstimator.disparityMap(for: buffer, orientation: orientation)
    {
      lastDepthEstimate = started
      freeSpace = FreeSpaceAnalyzer.analyze(disparity)
    } else {
      freeSpace = nil
    }

    // Building-number check is 2–3 times a second. The buffer stays on this queue and is
    // released when `process` returns, which is what the camera provider requires.
    let fresh = recognizeText(in: buffer, orientation: orientation, now: started)

    let snapshot: FrameStats = lock.withLock {
      stats.processed += 1
      stats.lastProcessingMs = (CACurrentMediaTime() - started) * 1000
      isBusy = false
      return stats
    }

    // CV-9 → FE-10: `onTextRead` gets this frame's reads; AppServices turns a matching
    // building number into a `BuildingSighting` for `NavigationSession.observe(_:)`.
    // TODO (CV-9): in low light, call `cameraCheckUnavailable(.lowLight)` instead of
    // failing quietly.

    // `buffer` is not captured below, so the camera gets it back now.
    let visibleNumbers = heldNumbers
    let visibleSigns = heldSigns
    // One sentence for the number and the sign. The overlay shows this same string.
    let readout = CameraReadout.sentence(numbers: visibleNumbers, signs: visibleSigns)
    // The repeat guard covers the "I see" line too, or it would be said on every frame.
    let phrase = spokenNumbers.phrase(for: readout ?? CameraReadout.seen(detections))
    Task { @MainActor [self] in
      // Detections go to the hazard path, which speaks reviewed phrases through
      // FeedbackKit. The raw sentence is for the debug Camera screen, never a walk.
      if !detections.isEmpty {
        onDetections?(detections)
      }
      if let freeSpace {
        onFreeSpace?(freeSpace)
      }
      if announcesReads, let phrase {
        speaker.speak(phrase)
      }
      if !fresh.isEmpty {
        onTextRead?(fresh)
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

/// The words on the camera screen and the words that are spoken. One sentence so a
/// building number and a street sign are both shown and both said.
nonisolated enum CameraReadout {
  static func sentence(numbers: [RecognizedNumber], signs: [RecognizedStreetSign]) -> String? {
    var parts: [String] = []
    if !numbers.isEmpty {
      parts.append("Number \(numbers.map(\.value).joined(separator: ", "))")
    }
    if !signs.isEmpty {
      parts.append("Sign \(signs.map(\.text).joined(separator: ", "))")
    }
    guard !parts.isEmpty else { return nil }
    return parts.joined(separator: ". ") + "."
  }

  static func seen(_ detections: [Detection]) -> String? {
    let names = detections.map { $0.labels.first?.identifier ?? "something" }
    guard !names.isEmpty else { return nil }
    return "I see: \(names.joined(separator: ", "))"
  }
}

/// Doesn't repeat the same camera sentence on every check.
private nonisolated final class SpokenNumbers: @unchecked Sendable {
  private let lock = NSLock()
  private var lastValue: String?
  private var lastAt = Date.distantPast

  func phrase(for sentence: String?) -> String? {
    guard let sentence else { return nil }
    let now = Date()
    lock.lock()
    defer { lock.unlock() }
    if lastValue == sentence, now.timeIntervalSince(lastAt) < 6 { return nil }
    lastValue = sentence
    lastAt = now
    return sentence
  }
}
