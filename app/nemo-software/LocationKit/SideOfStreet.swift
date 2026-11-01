//  SideOfStreet.swift
//  nemo-software
//
//  FE-13: "did the car drop you on the door's side of the street?"
//
//  `Geo.sameSide` is the geometry. This file is the decision around it: which course
//  sample to trust, when to refuse to answer, and why. Plan section 6 lists the cases
//  that must come back unknown, because a wrong call sends a blind rider across a road:
//  one-way street, a turn in the last 10 s, a stop that wasn't on the matched road,
//  poor course accuracy, or no car track at all (the app was closed during the ride).
//
//  The car's GPS *position* is never used in a cross product: at the curb it is too
//  noisy and a small error flips the answer. Only its direction of travel is.
//

import Foundation

nonisolated public enum SideOfStreetAnswer: Equatable, Sendable {
  /// The door is on the side of the street the car stopped on.
  case sameSide
  /// The door is on the far side: guidance stops until the rider is across.
  case acrossStreet
  /// Not decidable. Ask the rider instead of guessing.
  case unknown(SideOfStreetUnknown)

  public var isKnown: Bool {
    if case .unknown = self { return false }
    return true
  }
}

/// Why the app won't answer. Worth keeping: every trial logs it (plan section 6).
nonisolated public enum SideOfStreetUnknown: String, Equatable, Sendable {
  /// The bundle has no `street_side` block for this destination.
  case noStreetSideData
  /// The centerline had fewer than two distinct points.
  case unusableCenterline
  /// `door_side_of_road` wasn't "left" or "right".
  case unusableDoorSide
  /// No tracked ride, or the car never drove fast enough with a good course.
  case noCarTrack
  /// Cars can pull over on either side of a one-way street.
  case oneway
  /// A turn or U-turn just before the stop: the final course is misleading.
  case turnBeforeStop
  /// The stop wasn't on the matched road (parking lot, driveway, drop-off loop).
  case stopOffRoad
  /// The car's course wasn't along the road's axis, so it wasn't driving along it.
  case courseNotAlongRoad
}

/// "faces Massachusetts Avenue on the east side". Before arrival the app names the
/// street and the compass side, never "your side" (plan section 6).
nonisolated public enum StreetSideDescription {
  public static func compassSide(_ streetSide: StreetSide) -> String? {
    guard let roadBearing = Geo.polylineBearingDegrees(lonLat: streetSide.centerline) else {
      return nil
    }
    switch streetSide.doorSideOfRoad.lowercased() {
    case "right": return Phrases.compassPoint(roadBearing + 90)
    case "left": return Phrases.compassPoint(roadBearing - 90)
    default: return nil
    }
  }
}

nonisolated public struct SideOfStreetResolver: Sendable {
  /// How far from the road's centerline the stop may be and still count as "on" it.
  /// A two-way street plus a parked car is well under this; a parking lot isn't.
  public var maxDistanceFromRoadMeters: Double
  /// The course has to be within this of the road's axis to be "along" the road.
  public var maxCourseOffAxisDegrees: Double

  public init(maxDistanceFromRoadMeters: Double = 30, maxCourseOffAxisDegrees: Double = 45) {
    self.maxDistanceFromRoadMeters = maxDistanceFromRoadMeters
    self.maxCourseOffAxisDegrees = maxCourseOffAxisDegrees
  }

  /// - Parameters:
  ///   - streetSide: the bundle's `street_side` block (BE-5).
  ///   - track: courses recorded since "I'm in the car".
  ///   - stopTime: when the car stopped; the course just before it is the one that counts.
  public func resolve(
    streetSide: StreetSide?,
    track: CarCourseTrack,
    stopTime: Date
  ) -> SideOfStreetAnswer {
    guard let streetSide else { return .unknown(.noStreetSideData) }
    guard !streetSide.oneway else { return .unknown(.oneway) }
    guard let roadBearing = Geo.polylineBearingDegrees(lonLat: streetSide.centerline) else {
      return .unknown(.unusableCenterline)
    }
    let doorSide = streetSide.doorSideOfRoad.lowercased()
    guard doorSide == "left" || doorSide == "right" else { return .unknown(.unusableDoorSide) }
    guard let course = track.drivingCourse(asOf: stopTime) else { return .unknown(.noCarTrack) }
    guard !track.hadTurn(before: stopTime) else { return .unknown(.turnBeforeStop) }

    // Did the car stop on the road the bundle matched?
    if let distance = Geo.distanceToPolylineMeters(
      lat: course.latitude, lon: course.longitude, polylineLonLat: streetSide.centerline),
      distance > maxDistanceFromRoadMeters
    {
      return .unknown(.stopOffRoad)
    }

    // Travelling across the road's axis rather than along it (a cross street, a turn
    // into a driveway) tells us nothing about which curb the car pulled over to.
    let offAxis = abs(
      Geo.relativeAngle(heading: roadBearing, target: course.courseDegrees))
    let alongAxis = min(offAxis, 180 - offAxis)
    guard alongAxis <= maxCourseOffAxisDegrees else { return .unknown(.courseNotAlongRoad) }

    guard
      let same = Geo.sameSide(
        courseDegrees: course.courseDegrees,
        roadBearingDegrees: roadBearing,
        doorSideOfRoad: doorSide,
        oneway: streetSide.oneway)
    else { return .unknown(.courseNotAlongRoad) }
    return same ? .sameSide : .acrossStreet
  }
}
