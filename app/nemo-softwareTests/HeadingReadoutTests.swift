//  HeadingReadoutTests.swift
//  nemo-softwareTests
//
//  FE-3: the heading screen's logic. The calibration threshold and the announcement
//  throttling are the parts that would otherwise need a field trip to check.
//

import XCTest

@testable import nemo_software

final class HeadingReadoutTests: XCTestCase {

  private func readout(_ degrees: Double, accuracy: Double = 10, at seconds: TimeInterval = 0)
    -> HeadingReadout
  {
    HeadingReadout(
      trueHeadingDegrees: degrees, accuracyDegrees: accuracy,
      timestamp: Date(timeIntervalSinceReferenceDate: seconds))
  }

  // MARK: Compass points

  func testCompassPointsAtTheCardinals() {
    XCTAssertEqual(Phrases.compassPoint(0), "north")
    XCTAssertEqual(Phrases.compassPoint(45), "north east")
    XCTAssertEqual(Phrases.compassPoint(90), "east")
    XCTAssertEqual(Phrases.compassPoint(135), "south east")
    XCTAssertEqual(Phrases.compassPoint(180), "south")
    XCTAssertEqual(Phrases.compassPoint(225), "south west")
    XCTAssertEqual(Phrases.compassPoint(270), "west")
    XCTAssertEqual(Phrases.compassPoint(315), "north west")
  }

  func testCompassPointWrapsAroundNorth() {
    XCTAssertEqual(Phrases.compassPoint(350), "north")
    XCTAssertEqual(Phrases.compassPoint(370), "north")
    XCTAssertEqual(Phrases.compassPoint(-45), "north west")
    // The sector boundary sits at 22.5°.
    XCTAssertEqual(Phrases.compassPoint(22.4), "north")
    XCTAssertEqual(Phrases.compassPoint(22.6), "north east")
  }

  // MARK: Validity and calibration

  func testHeadingIsNormalized() {
    XCTAssertEqual(readout(370).trueHeadingDegrees, 10, accuracy: 1e-9)
    XCTAssertEqual(readout(-10).trueHeadingDegrees, 350, accuracy: 1e-9)
  }

  func testNegativeAccuracyIsInvalidAndNeedsCalibration() {
    XCTAssertFalse(readout(90, accuracy: -1).isValid)
    XCTAssertTrue(readout(90, accuracy: -1).needsCalibration)
  }

  func testCalibrationThresholdIsTwentyDegrees() {
    XCTAssertFalse(readout(90, accuracy: 19.9).needsCalibration)
    XCTAssertFalse(readout(90, accuracy: 20).needsCalibration)
    XCTAssertTrue(readout(90, accuracy: 20.1).needsCalibration)
    XCTAssertTrue(readout(90, accuracy: 35).needsCalibration)
  }

  func testSpokenTextSaysWhenAccuracyIsLow() {
    XCTAssertEqual(readout(45).spokenText, "Facing north east, 45 degrees.")
    XCTAssertEqual(
      readout(45, accuracy: 35).spokenText,
      "Facing north east, 45 degrees. Compass accuracy is low.")
  }

  func testOffsetToBearingUsesTheSignedAngle() {
    XCTAssertEqual(readout(350).offset(toBearing: 10), 20, accuracy: 1e-9)
    XCTAssertEqual(readout(10).offset(toBearing: 350), -20, accuracy: 1e-9)
  }

  // MARK: HeadingAnnouncer

  func testFirstGoodReadingIsAnnounced() {
    var announcer = HeadingAnnouncer()
    XCTAssertEqual(announcer.announcement(for: readout(45)), "Facing north east, 45 degrees.")
  }

  func testSmallWobblesStaySilent() {
    var announcer = HeadingAnnouncer()
    _ = announcer.announcement(for: readout(45, at: 0))
    // Same compass point, 1° apart, one second later: nothing to say.
    XCTAssertNil(announcer.announcement(for: readout(46, at: 1)))
    // Still the same point ten seconds later: still nothing. A VoiceOver user does not
    // want the heading repeated forever.
    XCTAssertNil(announcer.announcement(for: readout(46, at: 10)))
  }

  func testTurningToANewCompassPointIsAnnouncedAfterTheInterval() {
    var announcer = HeadingAnnouncer()
    _ = announcer.announcement(for: readout(45, at: 0))
    // A real turn, but too soon: the rider is still turning.
    XCTAssertNil(announcer.announcement(for: readout(135, at: 1)))
    XCTAssertEqual(
      announcer.announcement(for: readout(135, at: 5)), "Facing south east, 135 degrees.")
  }

  func testBadAccuracyAsksForCalibrationInsteadOfANumber() {
    var announcer = HeadingAnnouncer()
    XCTAssertEqual(announcer.announcement(for: readout(45, accuracy: 35)), Phrases.compassCalibration)
    // Not repeated on every reading.
    XCTAssertNil(announcer.announcement(for: readout(50, accuracy: 35, at: 1)))
    XCTAssertEqual(
      announcer.announcement(for: readout(50, accuracy: 35, at: 20)), Phrases.compassCalibration)
  }

  func testInvalidReadingsAreNeverAnnounced() {
    var announcer = HeadingAnnouncer()
    XCTAssertNil(announcer.announcement(for: readout(45, accuracy: -1)))
  }

  func testResetMakesTheNextReadingSpeakAgain() {
    var announcer = HeadingAnnouncer()
    _ = announcer.announcement(for: readout(45, at: 0))
    XCTAssertNil(announcer.announcement(for: readout(45, at: 1)))
    announcer.reset()
    XCTAssertEqual(
      announcer.announcement(for: readout(45, at: 1)), "Facing north east, 45 degrees.")
  }
}
