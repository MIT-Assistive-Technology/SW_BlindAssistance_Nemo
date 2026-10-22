import XCTest

@testable import CarToCurbLogic

final class FeedbackProfileTests: XCTestCase {
  func testRoundTrip() throws {
    for profile in FeedbackProfile.presets {
      let data = try JSONEncoder().encode(profile)
      XCTAssertEqual(try JSONDecoder().decode(FeedbackProfile.self, from: data), profile)
    }
    var custom = FeedbackProfile.audioFirst
    custom.units = .meters
    custom.cameraFirst = false
    custom.beaconVolume = 0.3
    let back = try JSONDecoder().decode(FeedbackProfile.self, from: JSONEncoder().encode(custom))
    XCTAssertEqual(back, custom)
  }

  func testPresets() {
    XCTAssertEqual(
      FeedbackProfile.presets.map(\.name), ["Haptics-first", "Audio-first", "Voice-only"])
    let voice = FeedbackProfile.voiceOnly
    XCTAssertTrue(voice.voiceOn)
    XCTAssertFalse(voice.beaconOn)
    XCTAssertFalse(voice.hapticsOn)
    let loud = FeedbackProfile(
      name: "x", hapticsOn: true, beaconOn: true, voiceOn: true, verbosity: .normal,
      beaconVolume: 4)
    XCTAssertEqual(loud.beaconVolume, 1)
  }

  func testDecodesKnownJSON() throws {
    let json = """
      {"name": "Mine", "version": 1, "hapticsOn": true, "beaconOn": false, "voiceOn": true,
       "verbosity": "minimal", "units": "meters", "cameraFirst": false, "beaconVolume": 0.5}
      """
    let p = try JSONDecoder().decode(FeedbackProfile.self, from: Data(json.utf8))
    XCTAssertEqual(p.verbosity, .minimal)
    XCTAssertEqual(p.units, .meters)
    XCTAssertFalse(p.cameraFirst)
  }
}
