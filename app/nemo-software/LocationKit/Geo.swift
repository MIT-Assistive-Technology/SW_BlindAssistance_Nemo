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

  /// Is the door on the rider's side of the street? (FE-13)
  ///
  /// Don't use the car's GPS position for this; it's too noisy near the curb. Use only the
  /// car's DIRECTION along the road, plus the side the server already computed:
  ///   - `courseDegrees`: `CLLocation.course` just before the stop. Only trust it when
  ///     speed > 3 m/s and `courseAccuracy` is reasonable, with no turn in the last 10 s.
  ///   - `roadBearingDegrees`: bearing of the bundle's `street_side.centerline` (first → last).
  ///   - `doorSideOfRoad`: the bundle's `street_side.door_side_of_road` ("left" / "right").
  /// Travelling the same way as the centerline (cos of the angle between them > 0) puts the
  /// US curb on the right; travelling the other way puts it on the left.
  /// Same side iff curb side == door side. Return nil (ask the rider) when oneway is true or
  /// the course isn't trustworthy.
  /// Example from the plan: road bearing 90°, door "right", course 92° → true; course 268° → false.
  public static func sameSide(
    courseDegrees: Double, roadBearingDegrees: Double, doorSideOfRoad: String, oneway: Bool
  ) -> Bool? {
    // TODO (FE-13): implement as described; unit-test both examples.
    nil
  }

  /// Which side of a direction a point lies on (used for "bench on your left").
  /// `direction` is the walking vector (east, north); `toPoint` the vector to the point.
  ///   cross = direction.east * toPoint.north - direction.north * toPoint.east
  ///   negative -> right, positive -> left.
  /// Example: direction (1, 0), point at (30, -10) -> cross = -10 -> right.
  public static func side(
    direction: (east: Double, north: Double),
    toPoint: (east: Double, north: Double)
  ) -> Side {
    // TODO (FE-2): implement, returning .unknown when |cross| is tiny (point straight ahead).
    .unknown
  }
}
