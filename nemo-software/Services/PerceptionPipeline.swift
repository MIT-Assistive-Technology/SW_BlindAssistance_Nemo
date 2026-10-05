//  PerceptionPipeline.swift
//  nemo-software
//
//  Wires the camera, detector, location, and speaker together. Receives every
//  frame from the active FrameProvider, runs object detection, speaks what was
//  seen, and publishes a simple presentation for the UI.
//

import Combine
import CoreVideo
import Foundation
import ImageIO

/// Presentation data emitted to the UI each time a frame is processed.
public struct FramePresentation {
  /// Raw detections from the object detector.
  public let detections: [Detection]

  /// Most recent device location/heading.
  public let location: LocationSnapshot?
}

/// Central coordinator. Implements `FrameProviderDelegate`.
public final class PerceptionPipeline: ObservableObject, FrameProviderDelegate {
  @Published public private(set) var presentation: FramePresentation?

  private let detector: ObjectDetector
  private let locationProvider: LocationProvider
  private let speaker: Speaker

  public init(
    detector: ObjectDetector,
    locationProvider: LocationProvider,
    speaker: Speaker
  ) {
    self.detector = detector
    self.locationProvider = locationProvider
    self.speaker = speaker
  }

  // MARK: - FrameProviderDelegate

  public func processFrame(_ provider: any FrameProvider, buffer: CVPixelBuffer) {
    // TODO: Determine the correct orientation for the current device orientation.
    let orientation = CGImagePropertyOrientation.up

    // Run detection. Start by accepting everything above a confidence floor.
    let detections = detector.detect(
      buffer,
      filter: { detection in
        // TODO: Filter by confidence threshold, e.g. detection.confidence > 0.4.
        true
      },
      orientation: orientation
    )

    // Speak the most interesting detection(s) so the user gets audio feedback.
    // TODO: Avoid repeating the same label on every frame (add a chatter guard).
    if let top = detections.first {
      speaker.speak(top.labels.first?.identifier ?? "something")
    }

    // Update the UI on the main actor.
    let location = locationProvider.currentSnapshot
    presentation = FramePresentation(
      detections: detections,
      location: location
    )
  }
}
