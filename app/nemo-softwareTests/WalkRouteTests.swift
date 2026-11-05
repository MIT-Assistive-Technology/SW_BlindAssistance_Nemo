import XCTest
@testable import nemo_software

final class WalkRouteTests: XCTestCase {
  private let doorLat = 42.35921
  private let doorLon = -71.09298
  private let metersPerDegree = 111_194.93

  private func waypoint(north: Double, east: Double) -> RouteWaypoint {
    RouteWaypoint(
      latitude: doorLat + north / metersPerDegree,
      longitude: doorLon + east / (metersPerDegree * cos(doorLat * .pi / 180)))
  }

  private func position(north: Double, east: Double) -> GuidancePosition {
    let point = waypoint(north: north, east: east)
    return GuidancePosition(
      latitude: point.latitude,
      longitude: point.longitude,
      horizontalAccuracyMeters: 5)
  }

  func testTotalRouteLength() {
    let route = WalkRoute(waypoints: [
      waypoint(north: 50, east: 0),
      waypoint(north: 50, east: 20),
      waypoint(north: 0, east: 0)
    ])!

    XCTAssertEqual(route.totalMeters, 20 + hypot(50, 20), accuracy: 1)
  }

  func testProjectionOntoRoute() {
    let route = WalkRoute(waypoints: [
      waypoint(north: 50, east: 0),
      waypoint(north: 50, east: 20),
      waypoint(north: 0, east: 0)
    ])!

    let projection = route.projection(for: position(north: 50, east: 10))!

    XCTAssertEqual(projection.crossTrackMeters, 0, accuracy: 0.5)
    XCTAssertEqual(projection.alongMeters, 10, accuracy: 0.5)
    XCTAssertEqual(projection.remainingMeters, route.totalMeters - 10, accuracy: 0.5)
  }

  func testCrossTrackDistance() {
    let route = WalkRoute(waypoints: [
      waypoint(north: 50, east: 0),
      waypoint(north: 50, east: 20),
      waypoint(north: 0, east: 0)
    ])!

    let projection = route.projection(for: position(north: 45, east: 10))!

    XCTAssertEqual(projection.crossTrackMeters, 5, accuracy: 0.5)
  }

  func testLookaheadStaysOnRoute() {
    let route = WalkRoute(waypoints: [
      waypoint(north: 50, east: 0),
      waypoint(north: 50, east: 20),
      waypoint(north: 0, east: 0)
    ])!

    let projection = route.projection(for: position(north: 50, east: 10))!
    let ahead = route.lookahead(from: projection, meters: 5)
    let expected = waypoint(north: 50, east: 15)

    XCTAssertEqual(ahead.latitude, expected.latitude, accuracy: 0.00001)
    XCTAssertEqual(ahead.longitude, expected.longitude, accuracy: 0.00001)
  }

  func testBundleRouteDecodes() {
    let route = WalkRoute(lonLat: [
      [-71.0935646, 42.3588425],
      [-71.0934618, 42.3590057],
      [-71.0933778, 42.3591393],
      [-71.0933469, 42.3591286]
    ])

    XCTAssertNotNil(route)
    XCTAssertGreaterThan(route?.totalMeters ?? 0, 20)
  }
}
