//  FeedbackEvent.swift
//  nemo-software
//
//  What happened, not how to present it. Guidance code emits these; FeedbackKit plays each
//  one on the channels the rider switched on. There is no free-text case on purpose: every
//  spoken phrase lives in `Phrases`, so the certainty-word test (SAFE-1) can check them all.
//

import Foundation

public enum FeedbackEvent: Equatable, Sendable {
  /// Signed offset from the rider's heading to the target, -180..<180, negative = left.
  case direction(offsetDegrees: Double)
  case distance(meters: Double)
  /// Heading is on the target (orient phase done).
  case bearingLock
  case landmark(kind: String, side: Side)
  case buildingConfirmed(text: String)
  case doorDetected(offsetDegrees: Double, meters: Double)
  case warning(Warning)
  case exitCurbSide
  /// `sameSide` nil = side of street unknown (ask the rider).
  case brief(sameSide: Bool?, meters: Double, offsetDegrees: Double)
  case offRoute
  case lost
  case arrival

  public enum Warning: Equatable, Sendable {
    case crossStreet(crossingMeters: Double?)
    case driveway
    case notSure
    case trackingLost
    case lowBattery
    case lowLight
  }
}

public enum Verbosity: String, Codable, CaseIterable, Sendable {
  case minimal, normal
}

public enum Units: String, Codable, CaseIterable, Sendable {
  case feet, meters
}

/// Lets code write `Warning` as well as `FeedbackEvent.Warning`.
public typealias Warning = FeedbackEvent.Warning
