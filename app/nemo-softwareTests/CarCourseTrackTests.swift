//  CarCourseTrackTests.swift
//  nemo-softwareTests
//
//  FE-13, first half: which recorded course the app is allowed to trust. These are the
//  cases plan section 6 says must not produce an answer — poor course accuracy, a turn
//  just before the stop, a stale course, no track at all.
//

import XCTest

@testable import nemo_software

final class CarCourseTrackTests: XCTestCase {

  private let base = Date(timeIntervalSinceReferenceDate: 0)

  private func sample(
    _ seconds: TimeInterval,
    course: Double = 92,
    accuracy: Double = 5,
    speed: Double = 12,
    lat: Double = 42.3592,
    lon: Double = -71.0928
  ) -> CourseSample {
    CourseSample(
      courseDegrees: course, courseAccuracyDegrees: accuracy, speedMetersPerSecond: speed,
      latitude: lat, longitude: lon, timestamp: base.addingTimeInterval(seconds))
  }

  // MARK: Which samples count

  func testDrivingSampleNeedsSpeedAndCourseAccuracy() {
    XCTAssertTrue(sample(0).isDrivingCourse)
    // Crawling in traffic: the course is noise.
    XCTAssertFalse(sample(0, speed: 2).isDrivingCourse)
    // CoreLocation reports -1 when it doesn't know.
    XCTAssertFalse(sample(0, course: -1).isDrivingCourse)
    XCTAssertFalse(sample(0, accuracy: -1).isDrivingCourse)
    // Poor course accuracy is one of the plan's "unknown" cases.
    XCTAssertFalse(sample(0, accuracy: 30).isDrivingCourse)
    XCTAssertTrue(sample(0, accuracy: 20).isDrivingCourse)
  }

  func testStoppedSample() {
    XCTAssertTrue(sample(0, speed: 0).isStopped)
    XCTAssertTrue(sample(0, speed: 0.4).isStopped)
    XCTAssertFalse(sample(0, speed: 2).isStopped)
    // An invalid speed is not evidence of a stop.
    XCTAssertFalse(sample(0, speed: -1).isStopped)
  }

  // MARK: The rolling window

  func testOldSamplesAreDropped() {
    var track = CarCourseTrack(window: 30)
    track.record(sample(0))
    track.record(sample(10))
    track.record(sample(100))
    XCTAssertEqual(track.samples.count, 1)
    XCTAssertEqual(track.samples.first?.timestamp, base.addingTimeInterval(100))
  }

  func testSamplesAreKeptInTimeOrder() {
    var track = CarCourseTrack()
    track.record(sample(10))
    track.record(sample(0))
    XCTAssertEqual(track.samples.map { $0.timestamp.timeIntervalSinceReferenceDate }, [0, 10])
    XCTAssertEqual(track.latest?.timestamp, base.addingTimeInterval(10))
  }

  // MARK: drivingCourse

  func testDrivingCourseTakesTheLatestGoodSampleBeforeTheStop() {
    var track = CarCourseTrack()
    track.record(sample(0, course: 10))
    track.record(sample(5, course: 92))
    track.record(sample(8, speed: 0))  // stopping
    XCTAssertEqual(
      track.drivingCourse(asOf: base.addingTimeInterval(10))?.courseDegrees, 92)
  }

  func testNoDrivingCourseWithoutATrackedRide() {
    let track = CarCourseTrack()
    XCTAssertNil(track.drivingCourse(asOf: base))
  }

  func testNoDrivingCourseWhenTheCarNeverDroveFastEnough() {
    var track = CarCourseTrack()
    track.record(sample(0, speed: 1.5))
    track.record(sample(5, speed: 2.0))
    XCTAssertNil(track.drivingCourse(asOf: base.addingTimeInterval(6)))
  }

  func testStaleCourseIsRejected() {
    var track = CarCourseTrack()
    track.record(sample(0))
    // Over a minute of standing still: the car could have been moved since.
    XCTAssertNil(track.drivingCourse(asOf: base.addingTimeInterval(90)))
  }

  // MARK: Turns

  func testTurnBeforeTheStopIsDetected() {
    var track = CarCourseTrack()
    track.record(sample(0, course: 10))
    track.record(sample(5, course: 92))
    XCTAssertTrue(track.hadTurn(before: base.addingTimeInterval(8)))
  }

  func testDriftingWithinAFewDegreesIsNotATurn() {
    var track = CarCourseTrack()
    track.record(sample(0, course: 90))
    track.record(sample(4, course: 93))
    track.record(sample(8, course: 92))
    XCTAssertFalse(track.hadTurn(before: base.addingTimeInterval(9)))
  }

  func testATurnLongBeforeTheStopDoesNotCount() {
    var track = CarCourseTrack()
    track.record(sample(0, course: 10))
    track.record(sample(40, course: 92))
    // The turn is outside the 10 s window before the stop.
    XCTAssertFalse(track.hadTurn(before: base.addingTimeInterval(45)))
  }

  func testTurnAcrossNorthIsMeasuredTheShortWay() {
    var track = CarCourseTrack()
    track.record(sample(0, course: 350))
    track.record(sample(5, course: 10))
    XCTAssertFalse(track.hadTurn(before: base.addingTimeInterval(6)))
  }

  // MARK: Stop detection

  func testStopIsDetectedAfterTheDwellTime() {
    var track = CarCourseTrack()
    track.record(sample(0))
    track.record(sample(10, speed: 0.2))
    XCTAssertNil(track.stopDetected(asOf: base.addingTimeInterval(12)))
    XCTAssertEqual(
      track.stopDetected(asOf: base.addingTimeInterval(16)), base.addingTimeInterval(10))
  }

  func testMovingAgainCancelsTheStop() {
    var track = CarCourseTrack()
    track.record(sample(0))
    track.record(sample(10, speed: 0.2))
    track.record(sample(14, speed: 9))  // red light, not a drop-off
    XCTAssertNil(track.stopDetected(asOf: base.addingTimeInterval(20)))
  }

  func testNoStopWithoutDrivingFirst() {
    var track = CarCourseTrack()
    track.record(sample(0, speed: 0.1))
    track.record(sample(10, speed: 0.1))
    XCTAssertNil(track.stopDetected(asOf: base.addingTimeInterval(20)))
  }

  func testEveryStopAfterACrawlIsANewStop() {
    // The detect → ask → "not yet" → detect again cycle depends on each stop having a
    // new timestamp. A car creeping forward in traffic never reaches driving speed, so
    // anchoring on "last driving course" would report the same stop forever and the
    // question would never be asked again.
    var track = CarCourseTrack()
    track.record(sample(0, speed: 12))  // driving
    track.record(sample(10, speed: 0.1))  // stopped at a light
    XCTAssertEqual(
      track.stopDetected(asOf: base.addingTimeInterval(20)), base.addingTimeInterval(10))

    track.record(sample(30, speed: 2))  // crawling forward, course useless
    XCTAssertNil(
      track.stopDetected(asOf: base.addingTimeInterval(32)), "moving again cancels the stop")

    track.record(sample(40, speed: 0.1))  // stopped again: the real drop-off
    XCTAssertEqual(
      track.stopDetected(asOf: base.addingTimeInterval(50)), base.addingTimeInterval(40),
      "the second stop must be a different stop")
  }

  func testAnUnknownSpeedDoesNotCancelAStop() {
    // CLLocation.speed is negative when it can't be measured, which happens in tunnels
    // and between tall buildings. That is not evidence the car moved.
    var track = CarCourseTrack()
    track.record(sample(0, speed: 12))
    track.record(sample(10, speed: 0.1))
    track.record(sample(15, speed: -1))
    XCTAssertEqual(
      track.stopDetected(asOf: base.addingTimeInterval(20)), base.addingTimeInterval(10))
  }

  func testMoving() {
    XCTAssertTrue(sample(0, speed: 12).isMoving)
    XCTAssertTrue(sample(0, speed: 2).isMoving)
    XCTAssertFalse(sample(0, speed: 0.5).isMoving)
    XCTAssertFalse(sample(0, speed: -1).isMoving)
  }
}
