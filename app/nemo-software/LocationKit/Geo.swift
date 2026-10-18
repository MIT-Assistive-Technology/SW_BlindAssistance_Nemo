//  Geo.swift
//  nemo-software
//
//  Pure geometry used by guidance (FE-2). No CoreLocation managers here, just math,
//  so it is easy to unit test. Bearings are degrees clockwise from TRUE north.
//
//  Worked examples are covered by nemo-softwareTests/GeoTests.swift, taken from
//  docs/car-to-curb-plan.md sections 6 (side of street) and 8 (street photos).
//

import Foundation

nonisolated public enum Side: String, Sendable {
  case left, right, unknown
}

/// `nonisolated` so the math can run off the main actor (the app defaults to MainActor).
nonisolated public enum Geo {
  public static let earthRadiusMeters = 6_371_000.0

  /// Great-circle distance in meters between two lat/lon points (haversine).
  public static func distanceMeters(
    lat1: Double, lon1: Double, lat2: Double, lon2: Double
  ) -> Double {
    let phi1 = radians(lat1)
    let phi2 = radians(lat2)
    let dPhi = radians(lat2 - lat1)
    let dLambda = radians(lon2 - lon1)
    let a =
      sin(dPhi / 2) * sin(dPhi / 2)
      + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
    let c = 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    return earthRadiusMeters * c
  }

  /// Initial bearing from point 1 to point 2, 0..<360.
  public static func bearingDegrees(
    lat1: Double, lon1: Double, lat2: Double, lon2: Double
  ) -> Double {
    let phi1 = radians(lat1)
    let phi2 = radians(lat2)
    let dLambda = radians(lon2 - lon1)
    let y = sin(dLambda) * cos(phi2)
    let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLambda)
    return normalize(degrees(atan2(y, x)))
  }

  /// Signed angle from `heading` to `target`, -180..<180. Negative = target is to the left.
  /// Example: heading 350°, target 10° -> +20° (turn right).
  public static func relativeAngle(heading: Double, target: Double) -> Double {
    normalize(target - heading + 180) - 180
  }

  /// Bearing from a street photo's camera to a detected object, 0..<360. Pinhole model,
  /// matching `photo_ray_bearing` in server/app/geo.py:
  ///   offset = atan((2x / w − 1) · tan(FOV / 2)), bearing = compass_angle + offset
  /// Example: compass 90°, x 700 of 1000 px, FOV 60° -> about 103.0°.
  public static func photoRayBearing(
    compassAngle: Double, xPixels: Double, widthPixels: Double, fovDegrees: Double
  ) -> Double {
    let normalizedX = 2 * xPixels / widthPixels - 1
    let offset = degrees(atan(normalizedX * tan(radians(fovDegrees) / 2)))
    return normalize(compassAngle + offset)
  }

  /// Is the door on the rider's side of the street? (FE-13)
  ///
  /// Don't use the car's GPS position for this; it's too noisy near the curb. Use only the
  /// car's DIRECTION along the road, plus the side the server already computed:
  ///   - `courseDegrees`: `CLLocation.course` just before the stop. Only trust it when
  ///     speed > 3 m/s and `courseAccuracy` is reasonable, with no turn in the last 10 s.
  ///     The caller checks those; this function only does the geometry.
  ///   - `roadBearingDegrees`: bearing of the bundle's `street_side.centerline` (first → last).
  ///   - `doorSideOfRoad`: the bundle's `street_side.door_side_of_road` ("left" / "right").
  /// Travelling the same way as the centerline (cos of the angle between them > 0) puts the
  /// US curb on the right; travelling the other way puts it on the left.
  /// Same side iff curb side == door side.
  ///
  /// Returns nil (ask the rider) when the street is one-way, the course is invalid
  /// (`CLLocation.course` is negative when unknown), `doorSideOfRoad` isn't "left"/"right",
  /// or the course is more than 45° off the road's axis (the car wasn't driving along it).
  /// Example from the plan: road bearing 90°, door "right", course 92° → true; course 268° → false.
  public static func sameSide(
    courseDegrees: Double, roadBearingDegrees: Double, doorSideOfRoad: String, oneway: Bool
  ) -> Bool? {
    guard !oneway, courseDegrees >= 0, courseDegrees.isFinite, roadBearingDegrees.isFinite
    else { return nil }
    let doorSide: Side
    switch doorSideOfRoad.lowercased() {
    case "left": doorSide = .left
    case "right": doorSide = .right
    default: return nil
    }
    let dot = cos(radians(courseDegrees - roadBearingDegrees))
    guard abs(dot) >= cos(radians(45)) else { return nil }
    let curbSide: Side = dot > 0 ? .right : .left
    return curbSide == doorSide
  }

  /// Which side of a direction a point lies on (used for "bench on your left").
  /// `direction` is the walking vector (east, north); `toPoint` the vector to the point.
  ///   cross = direction.east * toPoint.north - direction.north * toPoint.east
  ///   negative -> right, positive -> left.
  /// Returns `.unknown` when the point is (almost exactly) straight ahead or behind, or
  /// either vector is zero.
  /// Example: direction (1, 0), point at (30, -10) -> cross = -10 -> right.
  public static func side(
    direction: (east: Double, north: Double),
    toPoint: (east: Double, north: Double)
  ) -> Side {
    let cross = direction.east * toPoint.north - direction.north * toPoint.east
    let lengths = hypot(direction.east, direction.north) * hypot(toPoint.east, toPoint.north)
    guard lengths > 0, lengths.isFinite else { return .unknown }
    let sinAngle = cross / lengths
    if abs(sinAngle) < 1e-6 { return .unknown }
    return sinAngle < 0 ? .right : .left
  }

  // MARK: - Helpers

  /// Wraps any angle into 0..<360.
  public static func normalize(_ degrees: Double) -> Double {
    let r = degrees.truncatingRemainder(dividingBy: 360)
    let wrapped = r < 0 ? r + 360 : r
    return wrapped == 360 ? 0 : wrapped
  }

  static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
  static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
