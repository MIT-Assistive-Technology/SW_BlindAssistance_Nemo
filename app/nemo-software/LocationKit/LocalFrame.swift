//  LocalFrame.swift
//  nemo-software
//
//  From Minh's app/mvp (Logic/Geo.swift). Turns ARKit's east/north meters into lat/lon
//  around the GPS fix where tracking started (FE-12).
//

import Foundation

/// A flat east/north frame in meters around an origin. Accurate to centimeters over the few
/// hundred meters of a curb-to-door walk (equirectangular approximation).
nonisolated public struct LocalFrame: Codable, Equatable, Sendable {
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
