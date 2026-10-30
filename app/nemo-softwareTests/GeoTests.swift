//  GeoTests.swift
//  nemo-softwareTests
//
//  FE-2: worked examples from docs/car-to-curb-plan.md sections 6 and 8, plus edge cases.
//

import XCTest

@testable import nemo_software

final class GeoTests: XCTestCase {

  // MARK: distanceMeters

  func testDistanceZeroForSamePoint() {
    XCTAssertEqual(Geo.distanceMeters(lat1: 42.3601, lon1: -71.0942, lat2: 42.3601, lon2: -71.0942), 0)
  }

  func testDistanceOneDegreeOfLatitude() {
    // R * pi / 180 = 111_194.93 m
    XCTAssertEqual(Geo.distanceMeters(lat1: 0, lon1: 0, lat2: 1, lon2: 0), 111_194.93, accuracy: 0.1)
  }

  func testDistanceIsSymmetric() {
    let ab = Geo.distanceMeters(lat1: 42.3601, lon1: -71.0942, lat2: 42.3736, lon2: -71.1190)
    let ba = Geo.distanceMeters(lat1: 42.3736, lon1: -71.1190, lat2: 42.3601, lon2: -71.0942)
    XCTAssertEqual(ab, ba, accuracy: 1e-6)
  }

  func testDistanceShortHopAtBostonLatitude() {
    // 0.001° of latitude is about 111 m anywhere.
    XCTAssertEqual(Geo.distanceMeters(lat1: 42.36, lon1: -71.09, lat2: 42.361, lon2: -71.09), 111.19, accuracy: 0.1)
  }

  // MARK: bearingDegrees

  func testBearingCardinalDirections() {
    XCTAssertEqual(Geo.bearingDegrees(lat1: 0, lon1: 0, lat2: 1, lon2: 0), 0, accuracy: 1e-9)
    XCTAssertEqual(Geo.bearingDegrees(lat1: 0, lon1: 0, lat2: 0, lon2: 1), 90, accuracy: 1e-9)
    XCTAssertEqual(Geo.bearingDegrees(lat1: 0, lon1: 0, lat2: -1, lon2: 0), 180, accuracy: 1e-9)
    XCTAssertEqual(Geo.bearingDegrees(lat1: 0, lon1: 0, lat2: 0, lon2: -1), 270, accuracy: 1e-9)
  }

  func testBearingIsAlwaysInRange() {
    let b = Geo.bearingDegrees(lat1: 42.3601, lon1: -71.0942, lat2: 42.3602, lon2: -71.0943)
    XCTAssertGreaterThanOrEqual(b, 0)
    XCTAssertLessThan(b, 360)
    // 0.0001° north and west at 42.36°N: east leg shrinks by cos(lat), so ~323.5° (north-west).
    XCTAssertEqual(b, 323.54, accuracy: 0.01)
  }

  // MARK: relativeAngle

  func testRelativeAnglePlanExample() {
    XCTAssertEqual(Geo.relativeAngle(heading: 350, target: 10), 20, accuracy: 1e-9)
  }

  func testRelativeAngleLeftIsNegative() {
    XCTAssertEqual(Geo.relativeAngle(heading: 10, target: 350), -20, accuracy: 1e-9)
    XCTAssertEqual(Geo.relativeAngle(heading: 90, target: 45), -45, accuracy: 1e-9)
  }

  func testRelativeAngleEdges() {
    XCTAssertEqual(Geo.relativeAngle(heading: 90, target: 90), 0, accuracy: 1e-9)
    XCTAssertEqual(Geo.relativeAngle(heading: 0, target: 180), -180, accuracy: 1e-9)
    XCTAssertEqual(Geo.relativeAngle(heading: 720, target: -30), -30, accuracy: 1e-9)
  }

  // MARK: photoRayBearing (section 8 worked example)

  func testPhotoRayBearingPlanExamples() {
    XCTAssertEqual(Geo.photoRayBearing(compassAngle: 90, xPixels: 700, widthPixels: 1000, fovDegrees: 60), 103.0, accuracy: 0.05)
    XCTAssertEqual(Geo.photoRayBearing(compassAngle: 30, xPixels: 350, widthPixels: 1000, fovDegrees: 60), 20.2, accuracy: 0.05)
  }

  func testPhotoRayBearingCenterAndWrap() {
    XCTAssertEqual(Geo.photoRayBearing(compassAngle: 45, xPixels: 500, widthPixels: 1000, fovDegrees: 60), 45, accuracy: 1e-9)
    XCTAssertEqual(Geo.photoRayBearing(compassAngle: 0, xPixels: 0, widthPixels: 1000, fovDegrees: 60), 330, accuracy: 1e-9)
  }

  // MARK: sameSide (section 6 worked example)

  func testSameSidePlanExample() {
    XCTAssertEqual(Geo.sameSide(courseDegrees: 92, roadBearingDegrees: 90, doorSideOfRoad: "right", oneway: false), true)
    XCTAssertEqual(Geo.sameSide(courseDegrees: 268, roadBearingDegrees: 90, doorSideOfRoad: "right", oneway: false), false)
  }

  func testSameSideDoorOnLeft() {
    XCTAssertEqual(Geo.sameSide(courseDegrees: 92, roadBearingDegrees: 90, doorSideOfRoad: "left", oneway: false), false)
    XCTAssertEqual(Geo.sameSide(courseDegrees: 268, roadBearingDegrees: 90, doorSideOfRoad: "left", oneway: false), true)
  }

  func testSameSideAcrossNorth() {
    XCTAssertEqual(Geo.sameSide(courseDegrees: 5, roadBearingDegrees: 350, doorSideOfRoad: "right", oneway: false), true)
  }

  func testSameSideUnknownCases() {
    XCTAssertNil(Geo.sameSide(courseDegrees: 92, roadBearingDegrees: 90, doorSideOfRoad: "right", oneway: true))
    XCTAssertNil(Geo.sameSide(courseDegrees: -1, roadBearingDegrees: 90, doorSideOfRoad: "right", oneway: false))
    XCTAssertNil(Geo.sameSide(courseDegrees: 0, roadBearingDegrees: 90, doorSideOfRoad: "right", oneway: false))
    XCTAssertNil(Geo.sameSide(courseDegrees: 92, roadBearingDegrees: 90, doorSideOfRoad: "unknown", oneway: false))
  }

  // MARK: side

  func testSidePlanExample() {
    XCTAssertEqual(Geo.side(direction: (1, 0), toPoint: (30, -10)), .right)
  }

  func testSideLeftAndNorth() {
    XCTAssertEqual(Geo.side(direction: (1, 0), toPoint: (30, 10)), .left)
    XCTAssertEqual(Geo.side(direction: (0, 1), toPoint: (5, 0)), .right)
    XCTAssertEqual(Geo.side(direction: (0, 1), toPoint: (-5, 0)), .left)
  }

  func testSideUnknownWhenStraightAheadOrDegenerate() {
    XCTAssertEqual(Geo.side(direction: (1, 0), toPoint: (30, 0)), .unknown)
    XCTAssertEqual(Geo.side(direction: (0, 0), toPoint: (30, 10)), .unknown)
    XCTAssertEqual(Geo.side(direction: (1, 0), toPoint: (0, 0)), .unknown)
  }

  // MARK: normalize

  func testNormalize() {
    XCTAssertEqual(Geo.normalize(370), 10, accuracy: 1e-9)
    XCTAssertEqual(Geo.normalize(-10), 350, accuracy: 1e-9)
    XCTAssertEqual(Geo.normalize(360), 0, accuracy: 1e-9)
    XCTAssertEqual(Geo.normalize(-1e-15), 0, accuracy: 1e-9)
  }
}
