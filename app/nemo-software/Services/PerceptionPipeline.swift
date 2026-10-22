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
  private let locationProvider: LocationProvider
  private let speaker: Speaker

  private let perceptionQueue = DispatchQueue(label: "nemo.perception", qos: .userInitiated)

  /// Guards `isBusy`, `lastStart` and `stats`, which are touched from the provider's queue
  /// and from `perceptionQueue`.
  private let lock = NSLock()
  private var isBusy = false
  private var lastStart: CFTimeInterval = 0
  private var stats = FrameStats()

  public init(
    detector: ObjectDetector,
    locationProvider: LocationProvider,
    speaker: Speaker,
    maxFramesPerSecond: Double = 10
  ) {
    self.detector = detector
    self.locationProvider = locationProvider
    self.speaker = speaker
    self.maxFramesPerSecond = maxFramesPerSecond
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

    let snapshot: FrameStats = lock.withLock {
      stats.processed += 1
      stats.lastProcessingMs = (CACurrentMediaTime() - started) * 1000
      isBusy = false
      return stats
    }

    // `buffer` is not captured below, so the camera gets it back now.
    Task { @MainActor [self] in
      // Speak the most interesting detection(s) so the user gets audio feedback.
      // TODO: Avoid repeating the same label on every frame (add a chatter guard), and move
      // announcements to FeedbackKit events.
      if let top = detections.first {
        speaker.speak(top.labels.first?.identifier ?? "something")
      }

      // LocationService is main-actor, so the snapshot is read here, a few ms after capture.
      // TODO: attach location at capture time once LocationService is thread-safe (FE-3).
      onPresentation?(
        FramePresentation(
          detections: detections,
          location: locationProvider.currentSnapshot,
          stats: snapshot
        ))
    }
  }
}
