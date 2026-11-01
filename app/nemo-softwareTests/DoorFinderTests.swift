//  DoorFinderTests.swift
//  nemo-softwareTests
//
//  The door finder's pure parts: which words count as an entrance sign, and how a spot
//  in the camera frame becomes "slightly left".
//

import XCTest

@testable import nemo_software

final class DoorFinderTests: XCTestCase {

  func testEntranceWordsAreRecognized() {
    XCTAssertEqual(EntranceSignParser.entranceWord(in: "ENTRANCE"), .entrance)
    XCTAssertEqual(EntranceSignParser.entranceWord(in: "Main Entrance"), .entrance)
    XCTAssertEqual(EntranceSignParser.entranceWord(in: "PUSH"), .push)
    XCTAssertEqual(EntranceSignParser.entranceWord(in: "Pull"), .pull)
    XCTAssertEqual(EntranceSignParser.entranceWord(in: "AUTOMATIC DOOR"), .automaticDoor)
  }

  func testExitAndOrdinaryWordsAreNotEntrances() {
    // An exit-only door is the one door the rider must not be steered to.
    XCTAssertNil(EntranceSignParser.entranceWord(in: "EXIT"))
    XCTAssertNil(EntranceSignParser.entranceWord(in: "NO ENTRY EXIT ONLY"))
    // ENTER inside another word doesn't count.
    XCTAssertNil(EntranceSignParser.entranceWord(in: "STUDENT CENTER"))
    XCTAssertNil(EntranceSignParser.entranceWord(in: "Massachusetts Ave"))
    // Long lines are posters and notices, not door signs.
    XCTAssertNil(
      EntranceSignParser.entranceWord(in: "Please use the side entrance during construction"))
  }

  func testTheFrameCentreIsStraightAhead() {
    XCTAssertEqual(DoorSighting.offsetDegrees(normalizedX: 0.5, fovDegrees: 60), 0, accuracy: 0.001)
  }

  func testTheFrameEdgesAreHalfTheFieldOfView() {
    XCTAssertEqual(DoorSighting.offsetDegrees(normalizedX: 1, fovDegrees: 60), 30, accuracy: 0.001)
    XCTAssertEqual(DoorSighting.offsetDegrees(normalizedX: 0, fovDegrees: 60), -30, accuracy: 0.001)
  }

  func testPinholeNotLinear() {
    // A quarter of the way across a 60° frame is atan(0.5·tan 30°) ≈ 16.1°, not 15°.
    XCTAssertEqual(
      DoorSighting.offsetDegrees(normalizedX: 0.75, fovDegrees: 60), 16.1, accuracy: 0.05)
  }
}
