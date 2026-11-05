//
//  WalkRoute.swift
//  nemo-software
//
//  A walkable route from the drop-off to the entrance. The bundle stores it as
//  [lon, lat] waypoints; this type turns that polyline into the values guidance
//  needs: cross-track distance, remaining distance and the next aim point.
//

import Foundation

/// One point on the walking route.
nonisolated public struct RouteWaypoint: Equatable, Sendable {
  public let latitude: Double
  public let longitude: Double

  public init(latitude: Double, longitude: Double) {
    self.latitude = latitude
    self.longitude = longitude
  }

  /// Bundle routes are `[lon, lat]` pairs.
  public init?(lonLat: [Double]) {
    guard lonLat.count >= 2 else { return nil }
    self.init(latitude: lonLat[1], longitude: lonLat[0])
  }
}

/// Where a rider position lands when projected onto the route.
nonisolated public struct RouteProjection: Equatable, Sendable {
  /// The rider's position snapped onto the nearest route segment.
  public let position: RouteWaypoint
  /// Index of the segment containing `position`.
  public let segmentIndex: Int
  /// Distance traveled along the route before this projected point.
  public let alongMeters: Double
  /// How far the rider is from the route.
  public let crossTrackMeters: Double
  /// Route distance remaining to the final waypoint.
  public let remainingMeters: Double
}

/// A walkable route as an ordered polyline.
nonisolated public struct WalkRoute: Equatable, Sendable {
  public let waypoints: [RouteWaypoint]
  public let segmentLengths: [Double]

  /// cumulativeMeters[i] is the route distance at waypoints[i].
  private let cumulativeMeters: [Double]

  public var totalMeters: Double { cumulativeMeters.last ?? 0 }

  public init?(waypoints: [RouteWaypoint]) {
    let cleaned = waypoints.filter {
      $0.latitude.isFinite
        && $0.longitude.isFinite
        && abs($0.latitude) <= 90
        && abs($0.longitude) <= 180
    }
    var unique: [RouteWaypoint] = []
    for point in cleaned where unique.last != point {
      unique.append(point)
    }
    guard unique.count >= 2 else { return nil }

    var lengths: [Double] = []
    var cumulative: [Double] = [0]
    for index in 0..<(unique.count - 1) {
      let a = unique[index]
      let b = unique[index + 1]
      let length = Geo.distanceMeters(
        lat1: a.latitude, lon1: a.longitude,
        lat2: b.latitude, lon2: b.longitude)
      lengths.append(length)
      cumulative.append(cumulative[index] + length)
    }
    guard let total = cumulative.last, total > 0 else { return nil }

    self.waypoints = unique
    self.segmentLengths = lengths
    self.cumulativeMeters = cumulative
  }

  public init?(lonLat: [[Double]]) {
    self.init(waypoints: lonLat.compactMap { RouteWaypoint(lonLat: $0) })
  }

  /// Project a rider position onto the nearest point on the route.
  public func projection(for position: GuidancePosition) -> RouteProjection? {
    guard waypoints.count >= 2 else { return nil }

    // Flat local meters around the rider. Accurate enough for a short walk.
    let frame = LocalFrame(originLat: position.latitude, originLon: position.longitude)
    let local = waypoints.map { frame.toLocal(lat: $0.latitude, lon: $0.longitude) }
    var best:
      (
        segmentIndex: Int,
        nearest: (east: Double, north: Double),
        crossTrack: Double,
        along: Double
      )?

    for index in 0..<(local.count - 1) {
      let a = local[index]
      let b = local[index + 1]
      let dx = b.east - a.east
      let dy = b.north - a.north
      let lengthSquared = dx * dx + dy * dy
      guard lengthSquared > 0 else { continue }

      // Rider is at (0, 0) in this local frame. Clamp the projection onto the segment.
      let t = max(0, min(1, -(a.east * dx + a.north * dy) / lengthSquared))
      let nearest = (east: a.east + t * dx, north: a.north + t * dy)
      let crossTrack = hypot(nearest.east, nearest.north)
      let along = cumulativeMeters[index] + sqrt(lengthSquared) * t

      // Prefer the nearest segment. On a tie, prefer the one farther along so a
      // route that crosses itself does not send the rider backwards.
      if best == nil
        || crossTrack < best!.crossTrack
        || (abs(crossTrack - best!.crossTrack) < 0.001 && along > best!.along)
      {
        best = (index, nearest, crossTrack, along)
      }
    }

    guard let best else { return nil }
    let projected = frame.toGeo(east: best.nearest.east, north: best.nearest.north)
    return RouteProjection(
      position: RouteWaypoint(latitude: projected.lat, longitude: projected.lon),
      segmentIndex: best.segmentIndex,
      alongMeters: best.along,
      crossTrackMeters: best.crossTrack,
      remainingMeters: max(0, totalMeters - best.along))
  }

  /// The route point `distance` meters along the route.
  public func point(at distance: Double) -> RouteWaypoint {
    guard !waypoints.isEmpty else { return RouteWaypoint(latitude: 0, longitude: 0) }
    let clamped = max(0, min(distance, totalMeters))

    var segmentIndex = 0
    while segmentIndex < segmentLengths.count - 1,
      cumulativeMeters[segmentIndex + 1] < clamped
    {
      segmentIndex += 1
    }

    let startDistance = cumulativeMeters[segmentIndex]
    let segmentLength = segmentLengths[segmentIndex]
    let t = segmentLength > 0 ? (clamped - startDistance) / segmentLength : 0
    let a = waypoints[segmentIndex]
    let b = waypoints[segmentIndex + 1]
    return RouteWaypoint(
      latitude: a.latitude + (b.latitude - a.latitude) * t,
      longitude: a.longitude + (b.longitude - a.longitude) * t)
  }

  /// A point ahead of the rider's route projection, used as the steering target.
  public func lookahead(from projection: RouteProjection, meters: Double) -> RouteWaypoint {
    point(at: projection.alongMeters + max(0, meters))
  }
}
