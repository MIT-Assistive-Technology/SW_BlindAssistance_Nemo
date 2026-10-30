//  LocationSnapshot.swift
//  nemo-software
//
//  A read-only snapshot of device location, heading, and timestamp.
//

import CoreLocation
import Foundation

/// A snapshot of where the device was and which way it was pointing.
/// `nonisolated` so guidance can read it off the main actor (plan section 11).
nonisolated public struct LocationSnapshot {
  /// Absolute latitude/longitude if GPS is available.
  public let coordinate: CLLocationCoordinate2D?

  /// Estimated horizontal accuracy (metres). Lower is better.
  public let horizontalAccuracy: CLLocationDistance?

  /// Raw CoreLocation heading, when one has arrived.
  public let heading: CLHeading?

  /// When the position (`coordinate`) was measured. Heading updates keep it unchanged,
  /// so guidance can tell a stale fix from a fresh one; the heading's own time is
  /// `headingReadout.timestamp`.
  public let timestamp: Date

  /// True heading plus its accuracy as a value type, so guidance and tests don't need a
  /// `CLHeading` (FE-3). Nil until the first usable compass reading.
  public let headingReadout: HeadingReadout?

  /// Direction of travel from `CLLocation.course`, degrees from true north. Negative
  /// when unknown. This, not the device heading, is what the car's drop-off side uses.
  public let courseDegrees: CLLocationDirection?

  /// `CLLocation.courseAccuracy` in degrees; negative when invalid.
  public let courseAccuracyDegrees: CLLocationDirectionAccuracy?

  /// `CLLocation.speed` in m/s; negative when invalid.
  public let speedMetersPerSecond: CLLocationSpeed?

  public init(
    coordinate: CLLocationCoordinate2D? = nil,
    horizontalAccuracy: CLLocationDistance? = nil,
    heading: CLHeading? = nil,
    timestamp: Date = Date(),
    headingReadout: HeadingReadout? = nil,
    courseDegrees: CLLocationDirection? = nil,
    courseAccuracyDegrees: CLLocationDirectionAccuracy? = nil,
    speedMetersPerSecond: CLLocationSpeed? = nil
  ) {
    self.coordinate = coordinate
    self.horizontalAccuracy = horizontalAccuracy
    self.heading = heading
    self.timestamp = timestamp
    self.headingReadout = headingReadout
    self.courseDegrees = courseDegrees
    self.courseAccuracyDegrees = courseAccuracyDegrees
    self.speedMetersPerSecond = speedMetersPerSecond
  }
}
