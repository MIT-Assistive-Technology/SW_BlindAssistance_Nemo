//  LocationSnapshot.swift
//  nemo-software
//
//  A read-only snapshot of device location, heading, and timestamp.
//

import CoreLocation
import Foundation

/// A snapshot of where the device was and which way it was pointing.
public struct LocationSnapshot {
  /// Absolute latitude/longitude if GPS is available.
  public let coordinate: CLLocationCoordinate2D?

  /// Estimated horizontal accuracy (metres). Lower is better.
  public let horizontalAccuracy: CLLocationDistance?

  /// Device heading in degrees, where 0 is magnetic north.
  public let heading: CLHeading?

  /// When the snapshot was taken.
  public let timestamp: Date

  public init(
    coordinate: CLLocationCoordinate2D? = nil,
    horizontalAccuracy: CLLocationDistance? = nil,
    heading: CLHeading? = nil,
    timestamp: Date = Date()
  ) {
    self.coordinate = coordinate
    self.horizontalAccuracy = horizontalAccuracy
    self.heading = heading
    self.timestamp = timestamp
  }
}
