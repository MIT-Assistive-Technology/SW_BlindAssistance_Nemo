//  BuildingSighting.swift
//  nemo-software
//
//  What the camera tells navigation (CV-9 → FE-10). One message type, so the perception
//  side and the state machine can be built separately: the camera produces sightings,
//  `NavigationSession.observe(_:)` consumes them, and neither needs the other to exist.
//
//  What a sighting is NOT: it never says which door is the entrance. Order of trust is
//  a surveyed OSM door, then other OSM tags, then the outline (plan section 13). The
//  camera only confirms that the building the map describes is where the map says, and
//  by how much the phone's idea of "which way am I facing" is wrong.
//

import Foundation

nonisolated public struct BuildingSighting: Equatable, Sendable {
  /// The text that was read and matched against the bundle's `recognize.text`,
  /// e.g. "77". Matched, not free-form: the phrase only ever repeats a string the
  /// bundle already contained.
  public let text: String
  /// True bearing from the phone to the thing that was read, degrees from true north.
  /// Build it with `Geo.photoRayBearing` from the pixel column, or use the pixel
  /// initializer below.
  public let bearingDegrees: Double
  /// Vision's confidence, 0...1.
  public let confidence: Double
  public let timestamp: Date

  public init(
    text: String, bearingDegrees: Double, confidence: Double, timestamp: Date = Date()
  ) {
    self.text = text
    self.bearingDegrees = Geo.normalize(bearingDegrees)
    self.confidence = confidence
    self.timestamp = timestamp
  }

  /// Build a sighting straight from a detection in a frame, using the same pinhole
  /// model the server uses on street photos (`Geo.photoRayBearing`, FE-2).
  ///
  /// - Parameters:
  ///   - headingDegrees: the device's true heading when the frame was captured.
  ///   - xPixels: the centre of the detection's bounding box, in pixels from the left.
  ///   - widthPixels: frame width.
  ///   - fovDegrees: the camera's horizontal field of view.
  public init(
    text: String,
    headingDegrees: Double,
    xPixels: Double,
    widthPixels: Double,
    fovDegrees: Double,
    confidence: Double,
    timestamp: Date = Date()
  ) {
    self.init(
      text: text,
      bearingDegrees: Geo.photoRayBearing(
        compassAngle: headingDegrees, xPixels: xPixels, widthPixels: widthPixels,
        fovDegrees: fovDegrees),
      confidence: confidence,
      timestamp: timestamp)
  }
}

/// Why a camera check couldn't run, so it can say so instead of failing silently
/// (plan section 7).
nonisolated public enum CameraCheckProblem: String, Equatable, Sendable, CaseIterable {
  case lowLight
  case unavailable
}
