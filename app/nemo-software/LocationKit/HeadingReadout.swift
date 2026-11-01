//  HeadingReadout.swift
//  nemo-software
//
//  The heading readout screen's logic (FE-3), kept free of CoreLocation so it can be
//  unit tested. `LocationService` builds one of these from every CLHeading.
//  Headings are degrees clockwise from TRUE north: OSM and the server's bearings are
//  true north, so magnetic heading is never used.
//

import Foundation

/// A compass reading the app is willing to act on, plus how good it is.
nonisolated public struct HeadingReadout: Equatable, Sendable {
  /// Worse than this and the rider is asked to calibrate (FE-3).
  public static let calibrationThresholdDegrees = 20.0

  /// Degrees clockwise from true north, 0..<360.
  public let trueHeadingDegrees: Double
  /// CoreLocation's `headingAccuracy`: degrees of error, negative when invalid.
  public let accuracyDegrees: Double
  public let timestamp: Date

  public init(trueHeadingDegrees: Double, accuracyDegrees: Double, timestamp: Date = Date()) {
    self.trueHeadingDegrees = Geo.normalize(trueHeadingDegrees)
    self.accuracyDegrees = accuracyDegrees
    self.timestamp = timestamp
  }

  /// False for the readings CoreLocation marks unusable (negative accuracy, or a
  /// `trueHeading` of -1 before the first location fix).
  public var isValid: Bool { accuracyDegrees >= 0 }

  /// True when the compass is too rough to steer by. The compass beside a car is
  /// often ±10–20°, which is 7–14 m sideways at 40 m, so this matters.
  public var needsCalibration: Bool {
    !isValid || accuracyDegrees > Self.calibrationThresholdDegrees
  }

  /// "north", "north east", ... Spoken, so it's words rather than "NE".
  public var compassPoint: String { Phrases.compassPoint(trueHeadingDegrees) }

  /// What the heading screen says out loud.
  public var spokenText: String {
    Phrases.heading(degrees: trueHeadingDegrees, accuracyDegrees: accuracyDegrees)
  }

  /// Signed angle to a target bearing, negative to the left. Convenience over `Geo`.
  public func offset(toBearing target: Double) -> Double {
    Geo.relativeAngle(heading: trueHeadingDegrees, target: target)
  }
}

/// Decides when the heading screen should speak, so VoiceOver users aren't flooded
/// with a new number several times a second (FE-3's "works with VoiceOver only").
/// Pure and injectable-clock, so the throttling is unit tested rather than observed.
nonisolated public struct HeadingAnnouncer: Equatable, Sendable {
  /// Don't repeat the same compass point more often than this.
  public var minimumInterval: TimeInterval
  /// Speak early when the heading moves at least this far, even inside the interval.
  public var significantChangeDegrees: Double

  private var lastSpokenPoint: String?
  private var lastSpokenDegrees: Double?
  private var lastSpokenAt: Date?
  private var lastCalibrationPromptAt: Date?

  public init(minimumInterval: TimeInterval = 4, significantChangeDegrees: Double = 30) {
    self.minimumInterval = minimumInterval
    self.significantChangeDegrees = significantChangeDegrees
  }

  /// Returns the phrase to speak, or nil to stay quiet.
  public mutating func announcement(for readout: HeadingReadout) -> String? {
    guard readout.isValid else { return nil }
    if readout.needsCalibration {
      // The calibration prompt is the useful thing to say; a number from a bad
      // compass would only mislead. Repeat it at most once per interval.
      if let last = lastCalibrationPromptAt,
        readout.timestamp.timeIntervalSince(last) < minimumInterval * 2
      {
        return nil
      }
      lastCalibrationPromptAt = readout.timestamp
      lastSpokenPoint = nil
      lastSpokenDegrees = nil
      lastSpokenAt = readout.timestamp
      return Phrases.compassCalibration
    }
    lastCalibrationPromptAt = nil

    let movedFar =
      lastSpokenDegrees.map {
        abs(Geo.relativeAngle(heading: $0, target: readout.trueHeadingDegrees))
          >= significantChangeDegrees
      } ?? true
    let pointChanged = readout.compassPoint != lastSpokenPoint
    let waitedLongEnough =
      lastSpokenAt.map { readout.timestamp.timeIntervalSince($0) >= minimumInterval } ?? true
    guard (pointChanged || movedFar), waitedLongEnough else { return nil }

    lastSpokenPoint = readout.compassPoint
    lastSpokenDegrees = readout.trueHeadingDegrees
    lastSpokenAt = readout.timestamp
    return readout.spokenText
  }

  /// Forget the history so the next reading is spoken (used by "Speak heading").
  public mutating func reset() {
    lastSpokenPoint = nil
    lastSpokenDegrees = nil
    lastSpokenAt = nil
    lastCalibrationPromptAt = nil
  }
}
