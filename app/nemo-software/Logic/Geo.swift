//  Geo.swift
//  nemo-software
//
//  Pure geometry used by guidance (FE-2). No CoreLocation managers here, just math,
//  so it is easy to unit test. Bearings are degrees clockwise from TRUE north.
//
//  Worked examples are XCTest cases in app/Tests/CarToCurbLogicTests/GeoTests.swift
//  (docs/car-to-curb-plan.md sections 6 and 8).
//

import Foundation

public enum Side: String, Codable, Sendable {
  case left, right, unknown
}

public enum Geo {
  public static let earthRadiusMeters = 6_371_000.0

  /// Great-circle distance in meters between two lat/lon points (haversine).
  public static func distanceMeters(
    lat1: Double, lon1: Double, lat2: Double, lon2: Double
  ) -> Double {
    let phi1 = radians(lat1), phi2 = radians(lat2)
    let dPhi = radians(lat2 - lat1), dLambda = radians(lon2 - lon1)
    let a = sin(dPhi / 2) * sin(dPhi / 2)
      + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
    return 2 * earthRadiusMeters * atan2(sqrt(a), sqrt(max(0, 1 - a)))
  }

  /// Initial bearing from point 1 to point 2, 0..<360.
  public static func bearingDegrees(
    lat1: Double, lon1: Double, lat2: Double, lon2: Double
  ) -> Double {
    let phi1 = radians(lat1), phi2 = radians(lat2)
    let dLambda = radians(lon2 - lon1)
    let y = sin(dLambda) * cos(phi2)
    let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLambda)
    return normalize(degrees(atan2(y, x)))
  }

  /// Signed angle from `heading` to `target`, -180..<180. Negative = target is to the left.
  public static func relativeAngle(heading: Double, target: Double) -> Double {
    let d = (target - heading + 540).truncatingRemainder(dividingBy: 360)
    return (d < 0 ? d + 360 : d) - 180
  }

  /// Is the door on the rider's side of the street? (FE-13)
  ///
  /// Don't use the car's GPS position for this; it's too noisy near the curb. Use only the
  /// car's DIRECTION along the road, plus the side the server already computed:
  ///   - `courseDegrees`: the last trustworthy car course before the stop (speed > 3 m/s,
  ///     good course accuracy, no turn in the last 10 s; `SessionReducer` filters this).
  ///   - `roadBearingDegrees`: bearing of the bundle's `street_side.centerline` (first → last).
  ///   - `doorSideOfRoad`: the bundle's `street_side.door_side_of_road` ("left" / "right").
  /// Travelling the same way as the centerline (cos of the angle between them > 0) puts the
  /// US curb on the right; travelling the other way puts it on the left.
  /// Same side iff curb side == door side. Returns nil (ask the rider) when the street is
  /// one-way, the side string is unknown, or the course is nearly perpendicular to the road
  /// (the car wasn't on the matched road).
  /// Example from the plan: road bearing 90°, door "right", course 92° → true; course 268° → false.
  public static func sameSide(
    courseDegrees: Double, roadBearingDegrees: Double, doorSideOfRoad: String, oneway: Bool
  ) -> Bool? {
    if oneway { return nil }
    guard let doorSide = Side(rawValue: doorSideOfRoad.lowercased()), doorSide != .unknown
    else { return nil }
    let dot = cos(radians(courseDegrees - roadBearingDegrees))
    // Within ~10° of perpendicular: the car was crossing, not driving along this road.
    if abs(dot) < 0.17 { return nil }
    let curbSide: Side = dot > 0 ? .right : .left
    return curbSide == doorSide
  }

  /// Which side of a direction a point lies on (used for "bench on your left").
  /// `direction` is the walking vector (east, north); `toPoint` the vector to the point.
  ///   cross = direction.east * toPoint.north - direction.north * toPoint.east
  ///   negative -> right, positive -> left.
  /// Example: direction (1, 0), point at (30, -10) -> cross = -10 -> right.
  /// Returns `.unknown` when the point is within ~5° of straight ahead or behind.
  public static func side(
    direction: (east: Double, north: Double),
    toPoint: (east: Double, north: Double)
  ) -> Side {
    let cross = direction.east * toPoint.north - direction.north * toPoint.east
    let scale = hypot(direction.east, direction.north) * hypot(toPoint.east, toPoint.north)
    guard scale > 0, abs(cross) / scale > 0.087 else { return .unknown }
    return cross < 0 ? .right : .left
  }

  /// Bearing of a [lon, lat] polyline from its first point to its last; nil if too short.
  public static func polylineBearing(_ lonLat: [[Double]]) -> Double? {
    guard let first = lonLat.first, let last = lonLat.last,
      first.count >= 2, last.count >= 2, lonLat.count >= 2
    else { return nil }
    return bearingDegrees(lat1: first[1], lon1: first[0], lat2: last[1], lon2: last[0])
  }

  /// Ray-casting point-in-polygon on a [lon, lat] ring.
  public static func contains(_ ring: [[Double]], lat: Double, lon: Double) -> Bool {
    var inside = false
    var j = ring.count - 1
    for i in ring.indices {
      let (xi, yi) = (ring[i][0], ring[i][1])
      let (xj, yj) = (ring[j][0], ring[j][1])
      if (yi > lat) != (yj > lat), lon < (xj - xi) * (lat - yi) / (yj - yi) + xi {
        inside.toggle()
      }
      j = i
    }
    return inside
  }

  static func radians(_ deg: Double) -> Double { deg * .pi / 180 }
  static func degrees(_ rad: Double) -> Double { rad * 180 / .pi }
  static func normalize(_ deg: Double) -> Double {
    let d = deg.truncatingRemainder(dividingBy: 360)
    return d < 0 ? d + 360 : d
  }
}

/// A flat east/north frame in meters around an origin. Accurate to centimeters over the few
/// hundred meters of a curb-to-door walk (equirectangular approximation).
public struct LocalFrame: Codable, Equatable, Sendable {
  public let originLat: Double
  public let originLon: Double

  public init(originLat: Double, originLon: Double) {
    self.originLat = originLat
    self.originLon = originLon
  }

  private var metersPerDegLat: Double { Geo.earthRadiusMeters * .pi / 180 }
  private var metersPerDegLon: Double { metersPerDegLat * cos(Geo.radians(originLat)) }

  public func toLocal(lat: Double, lon: Double) -> (east: Double, north: Double) {
    ((lon - originLon) * metersPerDegLon, (lat - originLat) * metersPerDegLat)
  }

  public func toGeo(east: Double, north: Double) -> (lat: Double, lon: Double) {
    (originLat + north / metersPerDegLat, originLon + east / metersPerDegLon)
  }
}
