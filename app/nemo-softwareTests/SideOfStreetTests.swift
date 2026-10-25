//  SideOfStreetTests.swift
//  nemo-softwareTests
//
//  FE-13, second half: "did the car drop you on the door's side of the street?"
//
//  A wrong answer sends a blind rider across a road, so the unknown cases get as much
//  attention as the right ones. The worked example is plan section 6: a road running
//  east, a door on its right, course 92° -> same side, course 268° -> across.
//

import XCTest

@testable import nemo_software

final class SideOfStreetTests: XCTestCase {

  private let base = Date(timeIntervalSinceReferenceDate: 0)
  private let resolver = SideOfStreetResolver()

  /// A road running east, near the pilot area.
  private func eastRoad(doorSide: String = "right", oneway: Bool = false) -> StreetSide {
    StreetSide(
      entranceStreet: "Example Avenue",
      roadWay: "way/0000003",
      centerline: [[-71.0940, 42.3592], [-71.0920, 42.3592]],
      doorSideOfRoad: doorSide,
      oneway: oneway)
  }

  /// One good driving sample on the road, five seconds before the stop.
  private func track(
    course: Double,
    accuracy: Double = 5,
    speed: Double = 12,
    lat: Double = 42.3592,
    lon: Double = -71.0930,
    secondsBeforeStop: TimeInterval = 5
  ) -> CarCourseTrack {
    var track = CarCourseTrack()
    track.record(
      CourseSample(
        courseDegrees: course, courseAccuracyDegrees: accuracy, speedMetersPerSecond: speed,
        latitude: lat, longitude: lon,
        timestamp: base.addingTimeInterval(-secondsBeforeStop)))
    return track
  }

  // MARK: The worked example

  func testSameSideWhenDrivingWithTheCenterline() {
    XCTAssertEqual(
      resolver.resolve(streetSide: eastRoad(), track: track(course: 92), stopTime: base),
      .sameSide)
  }

  func testAcrossStreetWhenDrivingAgainstTheCenterline() {
    XCTAssertEqual(
      resolver.resolve(streetSide: eastRoad(), track: track(course: 268), stopTime: base),
      .acrossStreet)
  }

  func testTheAnswerFlipsWithTheDoorSide() {
    XCTAssertEqual(
      resolver.resolve(
        streetSide: eastRoad(doorSide: "left"), track: track(course: 92), stopTime: base),
      .acrossStreet)
    XCTAssertEqual(
      resolver.resolve(
        streetSide: eastRoad(doorSide: "left"), track: track(course: 268), stopTime: base),
      .sameSide)
  }

  // MARK: Unknown cases (plan section 6)

  func testOneWayStreetIsAlwaysUnknown() {
    // The car can pull over on either side, so the course proves nothing.
    XCTAssertEqual(
      resolver.resolve(
        streetSide: eastRoad(oneway: true), track: track(course: 92), stopTime: base),
      .unknown(.oneway))
  }

  func testNoBundleDataIsUnknown() {
    XCTAssertEqual(
      resolver.resolve(streetSide: nil, track: track(course: 92), stopTime: base),
      .unknown(.noStreetSideData))
  }

  func testNoTrackedRideIsUnknown() {
    // The app was closed during the ride, so there is no course to read.
    XCTAssertEqual(
      resolver.resolve(streetSide: eastRoad(), track: CarCourseTrack(), stopTime: base),
      .unknown(.noCarTrack))
  }

  func testPoorCourseAccuracyIsUnknown() {
    XCTAssertEqual(
      resolver.resolve(
        streetSide: eastRoad(), track: track(course: 92, accuracy: 35), stopTime: base),
      .unknown(.noCarTrack))
  }

  func testCrawlingTrafficGivesNoUsableCourse() {
    XCTAssertEqual(
      resolver.resolve(
        streetSide: eastRoad(), track: track(course: 92, speed: 1.5), stopTime: base),
      .unknown(.noCarTrack))
  }

  func testStaleCourseIsUnknown() {
    XCTAssertEqual(
      resolver.resolve(
        streetSide: eastRoad(), track: track(course: 92, secondsBeforeStop: 120),
        stopTime: base),
      .unknown(.noCarTrack))
  }

  func testTurnJustBeforeTheStopIsUnknown() {
    var turning = track(course: 92, secondsBeforeStop: 2)
    turning.record(
      CourseSample(
        courseDegrees: 2, courseAccuracyDegrees: 5, speedMetersPerSecond: 12,
        latitude: 42.3592, longitude: -71.0930, timestamp: base.addingTimeInterval(-8)))
    XCTAssertEqual(
      resolver.resolve(streetSide: eastRoad(), track: turning, stopTime: base),
      .unknown(.turnBeforeStop))
  }

  func testStopInAParkingLotIsUnknown() {
    // 400 m north of the road: a drop-off loop or parking lot, not the matched street.
    XCTAssertEqual(
      resolver.resolve(
        streetSide: eastRoad(), track: track(course: 92, lat: 42.3628), stopTime: base),
      .unknown(.stopOffRoad))
  }

  func testCourseAcrossTheRoadAxisIsUnknown() {
    // Driving north on a cross street, stopping at the corner.
    XCTAssertEqual(
      resolver.resolve(streetSide: eastRoad(), track: track(course: 0), stopTime: base),
      .unknown(.courseNotAlongRoad))
  }

  func testUnusableBundleFieldsAreUnknown() {
    let noCenterline = StreetSide(
      entranceStreet: "Example Avenue", roadWay: "way/1", centerline: [],
      doorSideOfRoad: "right", oneway: false)
    XCTAssertEqual(
      resolver.resolve(streetSide: noCenterline, track: track(course: 92), stopTime: base),
      .unknown(.unusableCenterline))

    XCTAssertEqual(
      resolver.resolve(
        streetSide: eastRoad(doorSide: "unknown"), track: track(course: 92), stopTime: base),
      .unknown(.unusableDoorSide))
  }

  func testIsKnown() {
    XCTAssertTrue(SideOfStreetAnswer.sameSide.isKnown)
    XCTAssertTrue(SideOfStreetAnswer.acrossStreet.isKnown)
    XCTAssertFalse(SideOfStreetAnswer.unknown(.oneway).isKnown)
  }

  // MARK: Naming the side out loud

  func testCompassSideOfTheStreet() {
    // Right of a road running east is its south side.
    XCTAssertEqual(StreetSideDescription.compassSide(eastRoad()), "south")
    XCTAssertEqual(StreetSideDescription.compassSide(eastRoad(doorSide: "left")), "north")
    // Right of a road running south is its west side: the example bundle's case.
    let southRoad = StreetSide(
      entranceStreet: "Example Avenue", roadWay: "way/3",
      centerline: [[-71.0928, 42.3595], [-71.0928, 42.3590]],
      doorSideOfRoad: "right", oneway: false)
    XCTAssertEqual(StreetSideDescription.compassSide(southRoad), "west")
  }

  // MARK: The real bundle

  func testExampleBundleResolvesWithACourseAlongItsCenterline() async throws {
    let bundle = try await StubEntranceClient().resolve(address: "77 Example Avenue")
    let streetSide = try XCTUnwrap(bundle.streetSide)
    // Its centerline runs north to south with the door on the right (so, the west side),
    // and the top candidate is indeed west of the centerline.
    XCTAssertEqual(streetSide.doorSideOfRoad, "right")
    XCTAssertLessThan(try XCTUnwrap(bundle.target?.lon), streetSide.centerline[0][0])

    let southbound = track(course: 182, lat: 42.3592, lon: -71.0928)
    XCTAssertEqual(
      resolver.resolve(streetSide: streetSide, track: southbound, stopTime: base), .sameSide)

    let northbound = track(course: 2, lat: 42.3592, lon: -71.0928)
    XCTAssertEqual(
      resolver.resolve(streetSide: streetSide, track: northbound, stopTime: base),
      .acrossStreet)
  }
}
