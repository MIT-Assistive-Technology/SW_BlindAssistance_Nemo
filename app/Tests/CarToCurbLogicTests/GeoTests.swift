import XCTest

@testable import CarToCurbLogic

final class GeoTests: XCTestCase {
  func testHaversine() {
    // One degree of latitude (or of longitude at the equator) is ~111.195 km.
    XCTAssertEqual(Geo.distanceMeters(lat1: 0, lon1: 0, lat2: 1, lon2: 0), 111_194.9, accuracy: 1)
    XCTAssertEqual(Geo.distanceMeters(lat1: 0, lon1: 0, lat2: 0, lon2: 1), 111_194.9, accuracy: 1)
    XCTAssertEqual(Geo.distanceMeters(lat1: 42.36, lon1: -71.09, lat2: 42.36, lon2: -71.09), 0)
    // Boston -> New York City, ~306 km.
    XCTAssertEqual(
      Geo.distanceMeters(lat1: 42.3601, lon1: -71.0589, lat2: 40.7128, lon2: -74.0060),
      306_000, accuracy: 2_000)
  }

  func testBearing() {
    XCTAssertEqual(Geo.bearingDegrees(lat1: 0, lon1: 0, lat2: 1, lon2: 0), 0, accuracy: 1e-9)
    XCTAssertEqual(Geo.bearingDegrees(lat1: 0, lon1: 0, lat2: 0, lon2: 1), 90, accuracy: 1e-9)
    XCTAssertEqual(Geo.bearingDegrees(lat1: 1, lon1: 0, lat2: 0, lon2: 0), 180, accuracy: 1e-9)
    XCTAssertEqual(Geo.bearingDegrees(lat1: 0, lon1: 1, lat2: 0, lon2: 0), 270, accuracy: 1e-9)
    let b = Geo.bearingDegrees(lat1: 42.36, lon1: -71.09, lat2: 42.37, lon2: -71.10)
    XCTAssert((0..<360).contains(b))
  }

  func testRelativeAngle() {
    XCTAssertEqual(Geo.relativeAngle(heading: 350, target: 10), 20, accuracy: 1e-9)
    XCTAssertEqual(Geo.relativeAngle(heading: 10, target: 350), -20, accuracy: 1e-9)
    XCTAssertEqual(Geo.relativeAngle(heading: 90, target: 90), 0, accuracy: 1e-9)
    XCTAssertEqual(Geo.relativeAngle(heading: 0, target: 270), -90, accuracy: 1e-9)
    XCTAssertEqual(Geo.relativeAngle(heading: 0, target: 180), -180, accuracy: 1e-9)
    XCTAssertEqual(Geo.relativeAngle(heading: -30, target: 720), 30, accuracy: 1e-9)
  }

  func testSameSidePlanExamples() {
    XCTAssertEqual(
      Geo.sameSide(courseDegrees: 92, roadBearingDegrees: 90, doorSideOfRoad: "right", oneway: false),
      true)
    XCTAssertEqual(
      Geo.sameSide(courseDegrees: 268, roadBearingDegrees: 90, doorSideOfRoad: "right", oneway: false),
      false)
    XCTAssertEqual(
      Geo.sameSide(courseDegrees: 268, roadBearingDegrees: 90, doorSideOfRoad: "left", oneway: false),
      true)
    XCTAssertNil(
      Geo.sameSide(courseDegrees: 92, roadBearingDegrees: 90, doorSideOfRoad: "right", oneway: true))
    XCTAssertNil(
      Geo.sameSide(courseDegrees: 0, roadBearingDegrees: 90, doorSideOfRoad: "right", oneway: false),
      "a course across the road is not on the matched road")
    XCTAssertNil(
      Geo.sameSide(courseDegrees: 92, roadBearingDegrees: 90, doorSideOfRoad: "", oneway: false))
  }

  func testSide() {
    XCTAssertEqual(Geo.side(direction: (1, 0), toPoint: (30, -10)), .right)
    XCTAssertEqual(Geo.side(direction: (1, 0), toPoint: (30, 10)), .left)
    XCTAssertEqual(Geo.side(direction: (1, 0), toPoint: (30, 0.01)), .unknown)
  }

  func testLocalFrameRoundTrip() {
    let frame = LocalFrame(originLat: 42.3595, originLon: -71.0928)
    let local = frame.toLocal(lat: 42.35921, lon: -71.09298)
    XCTAssertLessThan(local.east, 0)
    XCTAssertLessThan(local.north, 0)
    let back = frame.toGeo(east: local.east, north: local.north)
    XCTAssertEqual(back.lat, 42.35921, accuracy: 1e-10)
    XCTAssertEqual(back.lon, -71.09298, accuracy: 1e-10)
    // Local meters agree with haversine over a walk-sized distance.
    XCTAssertEqual(
      hypot(local.east, local.north),
      Geo.distanceMeters(lat1: 42.3595, lon1: -71.0928, lat2: 42.35921, lon2: -71.09298),
      accuracy: 0.05)
    let p = frame.toGeo(east: 12.5, north: -40)
    let q = frame.toLocal(lat: p.lat, lon: p.lon)
    XCTAssertEqual(q.east, 12.5, accuracy: 1e-6)
    XCTAssertEqual(q.north, -40, accuracy: 1e-6)
  }

  func testPolylineBearingAndContains() {
    XCTAssertEqual(
      Geo.polylineBearing([[-71.0928, 42.3595], [-71.0928, 42.359]])!, 180, accuracy: 1e-6)
    XCTAssertNil(Geo.polylineBearing([[-71.0928, 42.3595]]))
    let square: [[Double]] = [[0, 0], [1, 0], [1, 1], [0, 1], [0, 0]]
    XCTAssertTrue(Geo.contains(square, lat: 0.5, lon: 0.5))
    XCTAssertFalse(Geo.contains(square, lat: 1.5, lon: 0.5))
  }
}
