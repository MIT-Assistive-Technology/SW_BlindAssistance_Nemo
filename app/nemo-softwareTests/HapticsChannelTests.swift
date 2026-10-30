//
//  HapticsChannelTests.swift
//  nemo-softwareTests
//
//  A1: haptics must come back after stop(), a reset or an idle shutdown, and a stream
//  of turn updates must not become one long buzz. A fake engine stands in for Core
//  Haptics, so these run in the simulator.
//

import CoreHaptics
import XCTest

@testable import nemo_software

@MainActor
final class FakeHapticEngine: HapticEngine {
  var starts = 0
  var stops = 0
  var patterns: [Int] = []  // tap count of each pattern played
  var startError: Error?

  func startEngine() throws {
    starts += 1
    if let startError { throw startError }
  }

  func stopEngine() { stops += 1 }

  func playTaps(_ events: [CHHapticEvent]) throws { patterns.append(events.count) }
}

@MainActor
final class HapticsChannelTests: XCTestCase {
  private struct StartFailed: Error {}

  /// Fails if the engine is only started once (in init, as before), because after
  /// stop() the second pattern would play on a stopped engine.
  func testAPatternAfterStopStartsTheEngineAgain() {
    let engine = FakeHapticEngine()
    let haptics = HapticsChannel(engine: engine)

    haptics.play(.arrival)
    haptics.stop()
    haptics.play(.lost)

    XCTAssertEqual(engine.stops, 1)
    XCTAssertEqual(engine.starts, 2)
    XCTAssertEqual(engine.patterns, [3, 3])
  }

  /// Fails if a failed start is ignored and the pattern is played anyway.
  func testNoPatternWhenTheEngineWontStart() {
    let engine = FakeHapticEngine()
    engine.startError = StartFailed()
    let haptics = HapticsChannel(engine: engine)

    haptics.play(.arrival)

    XCTAssertEqual(engine.starts, 1)
    XCTAssertEqual(engine.patterns, [])
  }

  /// Fails if the turn-tap throttle is removed (three taps) or blocks every tap (none).
  func testTurnTapsAreAtMostOneASecond() {
    let engine = FakeHapticEngine()
    let haptics = HapticsChannel(engine: engine)

    haptics.play(.direction(offsetDegrees: 20))
    haptics.play(.direction(offsetDegrees: 25))
    haptics.play(.direction(offsetDegrees: 30))

    XCTAssertEqual(engine.patterns, [1])
  }

  /// The throttle is only on turn taps: fails if a warning right after a turn tap is
  /// swallowed by it.
  func testTheTurnThrottleNeverSwallowsAWarning() {
    let engine = FakeHapticEngine()
    let haptics = HapticsChannel(engine: engine)

    haptics.play(.direction(offsetDegrees: 20))
    haptics.play(.lost)
    haptics.play(.arrivalUncertain)

    XCTAssertEqual(engine.patterns, [1, 3, 2])
  }

  /// Without the throttle interval, every turn update taps. Shows the one-a-second test
  /// above is measuring the throttle, not some other filter.
  func testWithNoIntervalEveryTurnTaps() {
    let engine = FakeHapticEngine()
    let haptics = HapticsChannel(engine: engine)
    haptics.directionInterval = 0

    haptics.play(.direction(offsetDegrees: 20))
    haptics.play(.direction(offsetDegrees: 25))

    XCTAssertEqual(engine.patterns, [1, 1])
  }

  /// No haptics hardware: nothing to call, nothing crashes.
  func testNoEngineIsSilent() {
    let haptics = HapticsChannel(engine: nil)
    haptics.play(.arrival)
    haptics.stop()
  }
}
