//  ResolveResult+Brief.swift
//  nemo-software
//
//  Turns a bundle into the few numbers and words guidance actually uses. Kept out of
//  EntranceModels.swift so that file stays a plain mirror of the contract.
//

import Foundation

nonisolated extension ResolveResult {
  /// The door being guided to. The rest of `candidates` are backups (FE-10).
  public var target: Candidate? { candidates.first }

  /// Middle of the building's outline. The camera reads signs and numbers on the
  /// building, not on the door, so this is what a sighting is checked against (CV-9).
  public var buildingCenter: (lat: Double, lon: Double)? {
    var points = building.footprint.filter { $0.count >= 2 }
    // OSM outlines repeat their first point at the end; counting it twice skews the mean.
    if points.count > 1, points.first! == points.last! { points.removeLast() }
    guard !points.isEmpty else { return nil }
    let count = Double(points.count)
    return (
      lat: points.reduce(0) { $0 + $1[1] } / count,
      lon: points.reduce(0) { $0 + $1[0] } / count
    )
  }

  /// Walking distance as the crow flies from a point to the target door.
  public func metersToTarget(fromLat lat: Double, fromLon lon: Double) -> Double? {
    guard let target else { return nil }
    return Geo.distanceMeters(lat1: lat, lon1: lon, lat2: target.lat, lon2: target.lon)
  }

  /// Bearing from a point to the target door, for the beacon and the orient step.
  public func bearingToTarget(fromLat lat: Double, fromLon lon: Double) -> Double? {
    guard let target else { return nil }
    return Geo.bearingDegrees(lat1: lat, lon1: lon, lat2: target.lat, lon2: target.lon)
  }

  /// Distance to the nearest marked crossing, when the bundle found one. Spoken only
  /// when the door turns out to be across the street.
  public func metersToNearestCrossing(fromLat lat: Double, fromLon lon: Double) -> Double? {
    guard let crossing = pathChecks.nearestCrossing, crossing.count >= 2 else { return nil }
    return Geo.distanceMeters(lat1: lat, lon1: lon, lat2: crossing[1], lon2: crossing[0])
  }

  /// What the rider hears at setup, built from the top candidate (plan section 3, step 1).
  /// `metersToDoor` is left out until there's a location to measure from.
  /// The band to speak. A `partial` bundle is the server saying the result is weak, so it
  /// is never spoken as more than the street-facing side, whatever the top candidate says.
  public var spokenBand: String {
    status == "partial" ? "facade" : (target?.band ?? "facade")
  }

  public func destinationBrief(metersToDoor: Double? = nil) -> DestinationBrief {
    DestinationBrief(
      band: spokenBand,
      entranceStreet: streetSide?.entranceStreet,
      streetSideDescription: streetSide.flatMap(StreetSideDescription.compassSide),
      housenumber: building.housenumber,
      door: target?.speak?.door,
      automaticDoor: target?.speak?.automaticDoor,
      stepCount: target?.speak?.stepCount,
      metersToDoor: metersToDoor)
  }
}
