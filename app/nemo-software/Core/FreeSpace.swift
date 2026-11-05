//
//  FreeSpace.swift
//  nemo-software
//
//  The perception side's answer to "what is immediately walkable?". These are
//  camera-relative observations, not a route: NavigationSession chooses which clear
//  slice best follows the bundle route.
//

import Foundation

/// One angular sector in front of the camera. Negative offsets are left, positive right.
nonisolated public struct FreeSpaceSlice: Equatable, Sendable {
  public let centerOffsetDegrees: Double
  public let widthDegrees: Double
  /// How far this sector is clear before obstruction.
  public let clearMeters: Double
  public let confidence: Double

  public init(
    centerOffsetDegrees: Double,
    widthDegrees: Double,
    clearMeters: Double,
    confidence: Double = 1
  ) {
    self.centerOffsetDegrees = centerOffsetDegrees
    self.widthDegrees = widthDegrees
    self.clearMeters = clearMeters
    self.confidence = confidence
  }
}

/// A nearby thing the perception stack believes deserves attention.
nonisolated public enum PerceivedHazard: Equatable, Sendable {
  case obstacle(offsetDegrees: Double, meters: Double?, confidence: Double)
  case dropOff(offsetDegrees: Double, meters: Double?, confidence: Double)
  case stepUp(offsetDegrees: Double, meters: Double?, confidence: Double)
}

/// A complete local-space read for one camera/AR frame.
nonisolated public struct FreeSpaceObservation: Equatable, Sendable {
  public let timestamp: Date
  public let slices: [FreeSpaceSlice]
  public let hazards: [PerceivedHazard]

  public init(
    timestamp: Date,
    slices: [FreeSpaceSlice],
    hazards: [PerceivedHazard] = []
  ) {
    self.timestamp = timestamp
    self.slices = slices
    self.hazards = hazards
  }
}
