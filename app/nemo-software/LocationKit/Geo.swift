//  Geo.swift
//  nemo-software
//
//  Pure geometry used by guidance (FE-2). No CoreLocation managers here, just math,
//  so it is easy to unit test. Bearings are degrees clockwise from TRUE north.
//
//  Worked examples to turn into XCTest cases are in
//  docs/car-to-curb-plan.md sections 6 (side of street) and 8 (street photos).
//

import Foundation

public enum Side: String, Sendable {
  case left, right, unknown
}

public enum Geo {
  /// Great-circle distance in meters between two lat/lon points.
  public static func distanceMeters(
    lat1: Double, lon1: Double, lat2: Double, lon2: Double
  ) -> Double {
    // TODO (FE-2): haversine formula, Earth radius 6_371_000 m.
    0
  }

  /// Initial bearing from point 1 to point 2, 0..<360.
  public static func bearingDegrees(
    lat1: Double, lon1: Double, lat2: Double, lon2: Double
  ) -> Double {
    // TODO (FE-2): atan2(sin Δλ·cos φ2, cos φ1·sin φ2 − sin φ1·cos φ2·cos Δλ), to degrees, normalize.
    0
  }

  /// Signed angle from `heading` to `target`, -180...180. Negative = target is to the left.
  public static func relativeAngle(heading: Double, target: Double) -> Double {
    // TODO (FE-2): ((target - heading + 540).truncatingRemainder(dividingBy: 360)) - 180
    0
  }

  /// Which side of a direction of travel a point lies on, in local meters.
  /// `direction` is the travel vector (east, north); `toPoint` is the vector from the
  /// car to the point. Uses the sign of the 2D cross product:
  ///   cross = direction.east * toPoint.north - direction.north * toPoint.east
  ///   negative -> right, positive -> left.
  /// Example from the plan: direction (1, 0), door at (30, -10) -> cross = -10 -> right.
  public static func side(
    direction: (east: Double, north: Double),
    toPoint: (east: Double, north: Double)
  ) -> Side {
    // TODO (FE-2): implement, returning .unknown when |cross| is tiny (point straight ahead).
    .unknown
  }
}
