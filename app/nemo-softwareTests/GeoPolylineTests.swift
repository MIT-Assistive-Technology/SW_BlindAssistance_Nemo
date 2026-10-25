//  GeoPolylineTests.swift
//  nemo-softwareTests
//
//  The polyline helpers side-of-street detection needs: the road's direction and how far
//  the car stopped from its centerline. Points are [lon, lat], as in the contract.
//

import XCTest

@testable import nemo_software

final class GeoPolylineTests: XCTestCase {

  /// The example bundle's centerline, which runs from north to south.
  private let northSouth = [[-71.0928, 42.3595], [-71.0928, 42.3590]]

  // MARK: polylineBearingDegrees

  func testBearingRunsFirstToLast() {
    XCTAssertEqual(Geo.polylineBearingDegrees(lonLat: northSouth) ?? -1, 180, accuracy: 0.01)
    XCTAssertEqual(
      Geo.polylineBearingDegrees(lonLat: northSouth.reversed().map { $0 }) ?? -1, 0,
      accuracy: 0.01)
  }

  func testBearingUsesOnlyTheEndPoints() {
    // A dog-leg in the middle must not change the answer: the contract defines the
    // road's direction as first point to last point.
    let dogLeg = [[-71.0928, 42.3595], [-71.0900, 42.3592], [-71.0928, 42.3590]]
    XCTAssertEqual(Geo.polylineBearingDegrees(lonLat: dogLeg) ?? -1, 180, accuracy: 0.01)
  }

  func testBearingIsNilWithoutTwoDistinctPoints() {
    XCTAssertNil(Geo.polylineBearingDegrees(lonLat: []))
    XCTAssertNil(Geo.polylineBearingDegrees(lonLat: [[-71.0928, 42.3595]]))
    XCTAssertNil(
      Geo.polylineBearingDegrees(lonLat: [[-71.0928, 42.3595], [-71.0928, 42.3595]]))
    XCTAssertNil(Geo.polylineBearingDegrees(lonLat: [[-71.0928], [42.3595]]))
  }

  // MARK: distanceToPolylineMeters

  func testDistanceIsZeroOnTheLine() {
    let distance = Geo.distanceToPolylineMeters(
      lat: 42.35925, lon: -71.0928, polylineLonLat: northSouth)
    XCTAssertEqual(distance ?? -1, 0, accuracy: 0.5)
  }

  func testPerpendicularDistanceMatchesGreatCircleDistance() {
    // Cross-check against the haversine: for a point beside a north–south line, the
    // shortest distance is the east–west hop to the same latitude on that line.
    let expected = Geo.distanceMeters(
      lat1: 42.35925, lon1: -71.0922, lat2: 42.35925, lon2: -71.0928)
    let distance = Geo.distanceToPolylineMeters(
      lat: 42.35925, lon: -71.0922, polylineLonLat: northSouth)
    XCTAssertEqual(distance ?? -1, expected, accuracy: 0.5)
    // Sanity: a two-way street plus a parked car is tens of meters, not hundreds.
    XCTAssertLessThan(distance ?? .infinity, 60)
  }

  func testDistanceClampsToTheSegmentEnds() {
    // Well south of the line's last point: the nearest point is that end point, not the
    // line extended.
    let expected = Geo.distanceMeters(
      lat1: 42.3580, lon1: -71.0928, lat2: 42.3590, lon2: -71.0928)
    let distance = Geo.distanceToPolylineMeters(
      lat: 42.3580, lon: -71.0928, polylineLonLat: northSouth)
    XCTAssertEqual(distance ?? -1, expected, accuracy: 0.5)
  }

  func testDistanceUsesTheNearestSegment() {
    let lShape = [[-71.0928, 42.3595], [-71.0928, 42.3590], [-71.0900, 42.3590]]
    // A point beside the second (east–west) segment.
    let distance = Geo.distanceToPolylineMeters(
      lat: 42.3592, lon: -71.0910, polylineLonLat: lShape)
    let expected = Geo.distanceMeters(
      lat1: 42.3592, lon1: -71.0910, lat2: 42.3590, lon2: -71.0910)
    XCTAssertEqual(distance ?? -1, expected, accuracy: 0.5)
  }

  func testDistanceWithASinglePointOrNone() {
    XCTAssertNil(Geo.distanceToPolylineMeters(lat: 42.36, lon: -71.09, polylineLonLat: []))
    let expected = Geo.distanceMeters(
      lat1: 42.3595, lon1: -71.0928, lat2: 42.3590, lon2: -71.0928)
    let distance = Geo.distanceToPolylineMeters(
      lat: 42.3595, lon: -71.0928, polylineLonLat: [[-71.0928, 42.3590]])
    XCTAssertEqual(distance ?? -1, expected, accuracy: 0.5)
  }

  // MARK: localOffsetMeters

  func testLocalOffsetSigns() {
    let offset = Geo.localOffsetMeters(
      lat: 42.3600, lon: -71.0920, originLat: 42.3590, originLon: -71.0930)
    XCTAssertGreaterThan(offset.east, 0)
    XCTAssertGreaterThan(offset.north, 0)
    // 0.001° of latitude is about 111 m anywhere.
    XCTAssertEqual(offset.north, 111.19, accuracy: 0.1)
    // East shrinks by cos(latitude).
    XCTAssertEqual(offset.east, 111.19 * cos(42.3590 * .pi / 180), accuracy: 0.1)
  }
}
