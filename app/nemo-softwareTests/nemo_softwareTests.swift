//  nemo_softwareTests.swift
//  nemo-softwareTests
//
//  SAFE-1 over what the rider actually hears: one of every FeedbackEvent through the
//  speech channel, and the briefs built from every real pilot bundle. PhrasesTests
//  checks `Phrases.all`; this checks the routes into it, so a phrase that never made
//  it into `all`, or a bundle field that reads as a promise, is still caught.
//
//  The banned-word list here is stricter than `Phrases.bannedCertaintyPhrases`, so both
//  are run. "That looks like your building" is the plan's own wording (section 7) and
//  is allowed; "that's your building" is not.
//

import XCTest

@testable import nemo_software

@MainActor
final class PhraseSafetyTests: XCTestCase {

  private static let banned =
    [
      "that's your", "that is your", "you've arrived",
      "you have arrived", "definitely", "certainly",
      "the correct", "your destination",
    ] + Phrases.bannedCertaintyPhrases

  /// Every case of FeedbackEvent, by name. The switch has no `default`, so a new event
  /// doesn't compile until it is named here, and the coverage test below then fails
  /// until a sample of it is in `samples`.
  private static func caseName(_ event: FeedbackEvent) -> String {
    switch event {
    case .direction: return "direction"
    case .distance: return "distance"
    case .bearingLock: return "bearingLock"
    case .landmark: return "landmark"
    case .buildingConfirmed: return "buildingConfirmed"
    case .buildingUncertain: return "buildingUncertain"
    case .cameraCheckUnavailable: return "cameraCheckUnavailable"
    case .doorDetected: return "doorDetected"
    case .warning: return "warning"
    case .lost: return "lost"
    case .arrival: return "arrival"
    case .heading: return "heading"
    case .compassCalibration: return "compassCalibration"
    case .headingUnavailable: return "headingUnavailable"
    case .locationPermissionDenied: return "locationPermissionDenied"
    case .rideTracking: return "rideTracking"
    case .exitCurbSide: return "exitCurbSide"
    case .possibleDropOff: return "possibleDropOff"
    case .sideOfStreet: return "sideOfStreet"
    case .askSideOfStreet: return "askSideOfStreet"
    case .destinationBrief: return "destinationBrief"
    case .lookingUpDestination: return "lookingUpDestination"
    case .destinationLookupFailed: return "destinationLookupFailed"
    case .noDestinationLoaded: return "noDestinationLoaded"
    case .bundleNotSavedForOffline: return "bundleNotSavedForOffline"
    case .startingGuidance: return "startingGuidance"
    case .guidanceStopped: return "guidanceStopped"
    case .waitingToCrossStreet: return "waitingToCrossStreet"
    case .directionUncertain: return "directionUncertain"
    case .finalApproach: return "finalApproach"
    case .beaconAim: return "beaconAim"
    case .positionUncertain: return "positionUncertain"
    case .guidanceResumed: return "guidanceResumed"
    case .reorienting: return "reorienting"
    case .noSafePath: return "noSafePath"
    case .roadToCross: return "roadToCross"
    case .atCrossing: return "atCrossing"
    case .arrivalUncertain: return "arrivalUncertain"
    case .readyToStartGuidance: return "readyToStartGuidance"
    }
  }

  /// Same order as the switch above. Kept next to it so the two are edited together.
  private static let allCaseNames: Set<String> = [
    "direction", "distance", "bearingLock", "landmark", "buildingConfirmed",
    "buildingUncertain", "cameraCheckUnavailable", "doorDetected", "warning", "lost",
    "arrival", "heading", "compassCalibration", "headingUnavailable",
    "locationPermissionDenied", "rideTracking", "exitCurbSide", "possibleDropOff",
    "sideOfStreet", "askSideOfStreet", "destinationBrief", "lookingUpDestination",
    "destinationLookupFailed", "noDestinationLoaded", "bundleNotSavedForOffline",
    "startingGuidance", "guidanceStopped", "waitingToCrossStreet", "directionUncertain",
    "finalApproach", "beaconAim", "positionUncertain", "guidanceResumed", "reorienting",
    "noSafePath", "roadToCross", "atCrossing", "arrivalUncertain", "readyToStartGuidance",
  ]

  /// Events with no words, on purpose. `.beaconAim` is carried by the tone. The other
  /// three wait for reviewed phrases (FE-6); until then SAFE-5/SAFE-6 warnings, landmarks
  /// and door detections can't be spoken, which is an open gap, not a pass.
  private static let silent: Set<String> = ["beaconAim", "landmark", "doorDetected", "warning"]

  /// At least one of every event, with each variant that picks different words.
  private static var samples: [FeedbackEvent] {
    let street = SideOfStreetContext(
      metersToDoor: 33.5, metersToCrossing: 30, entranceStreet: "Massachusetts Avenue",
      streetSideDescription: "east")
    let main = DestinationBrief(
      band: "main", entranceStreet: "Massachusetts Avenue", streetSideDescription: "east",
      housenumber: "77", door: "hinged", automaticDoor: "button", stepCount: 3,
      metersToDoor: 33.5)
    let events: [FeedbackEvent] = [
      .direction(offsetDegrees: 0), .direction(offsetDegrees: 20),
      .direction(offsetDegrees: -60), .direction(offsetDegrees: 150),
      .distance(meters: 18),
      .bearingLock(metersToDoor: 33.5), .bearingLock(metersToDoor: nil),
      .landmark(phrase: "bench on your left"),
      .buildingConfirmed(text: "77", offsetDegrees: 10),
      .buildingConfirmed(text: "77", offsetDegrees: nil),
      .buildingUncertain(text: "77"),
      .doorDetected(offsetDegrees: 10, meters: 3),
      .warning("step down"),
      .lost, .arrival,
      .heading(degrees: 45, accuracyDegrees: 10), .heading(degrees: 45, accuracyDegrees: 35),
      .compassCalibration, .headingUnavailable, .locationPermissionDenied,
      .rideTracking(started: true), .rideTracking(started: false),
      .exitCurbSide,
      .possibleDropOff(metersToDoor: 12), .possibleDropOff(metersToDoor: nil),
      .sideOfStreet(.sameSide, street), .sideOfStreet(.acrossStreet, street),
      .sideOfStreet(.acrossStreet, SideOfStreetContext()),
      .sideOfStreet(.unknown(.oneway), street),
      .askSideOfStreet(street), .askSideOfStreet(SideOfStreetContext()),
      .destinationBrief(main), .destinationBrief(DestinationBrief(band: "door")),
      .destinationBrief(DestinationBrief(band: "facade")),
      .lookingUpDestination,
      .noDestinationLoaded, .bundleNotSavedForOffline,
      .startingGuidance, .guidanceStopped, .waitingToCrossStreet, .directionUncertain,
      .finalApproach(metersToDoor: 9, main),
      .finalApproach(metersToDoor: nil, DestinationBrief(band: "facade")),
      .beaconAim(offsetDegrees: 10), .beaconAim(offsetDegrees: nil),
      .positionUncertain, .guidanceResumed, .reorienting,
      .noSafePath(roadCrossing: false), .noSafePath(roadCrossing: true),
      .roadToCross(metersToCrossing: 40), .roadToCross(metersToCrossing: nil),
      .atCrossing, .arrivalUncertain, .readyToStartGuidance,
    ]
    let failures = LookupFailure.allCases.map { FeedbackEvent.destinationLookupFailed($0) }
    let camera = CameraCheckProblem.allCases.map { FeedbackEvent.cameraCheckUnavailable($0) }
    return events + failures + camera
  }

  private func assertNoCertainty(
    _ phrase: String, _ source: String, file: StaticString = #filePath, line: UInt = #line
  ) {
    let lowered = phrase.lowercased()
    for word in Self.banned where lowered.contains(word) {
      XCTFail("\(source): \"\(phrase)\" contains \"\(word)\"", file: file, line: line)
    }
  }

  /// Fails when a new event is added without a sample here, so the lint can't silently
  /// miss it.
  func testEveryEventHasASample() {
    XCTAssertEqual(Set(Self.samples.map(Self.caseName)), Self.allCaseNames)
  }

  /// SAFE-1 over every event the speech channel can say. Fails on a certainty word, and
  /// also when an event outside `silent` has no words (it would be dropped without a
  /// sound) or a silent one starts speaking without being reviewed here.
  func testNoEventIsSpokenWithCertainty() {
    for event in Self.samples {
      let name = Self.caseName(event)
      guard let phrase = SpeechChannel.phrase(for: event) else {
        XCTAssertTrue(Self.silent.contains(name), ".\(name) has no words and isn't marked silent")
        continue
      }
      XCTAssertFalse(Self.silent.contains(name), ".\(name) now speaks: review it and unmark it")
      XCTAssertFalse(phrase.isEmpty, ".\(name)")
      assertNoCertainty(phrase, ".\(name)")
    }
  }

  /// The same check over every phrase in the table.
  func testNoCertaintyWordsAnywhereInTheTable() {
    for phrase in Phrases.all {
      assertNoCertainty(phrase, "Phrases.all")
    }
  }

  /// The briefs and door facts built from every real pilot bundle: street names, door
  /// tags and bands come from OSM, not from the phrase table. Fails on a certainty word
  /// in them, if a `partial` bundle is spoken as anything but the street-facing side,
  /// or if the pilot bundles aren't in the app at all (so the test can't pass empty).
  func testPilotBundlesAreBriefedWithoutCertainty() async throws {
    struct Sites: Decodable {
      struct Site: Decodable { let id: String }
      let sites: [Site]
    }
    let url = try XCTUnwrap(Bundle.main.url(forResource: "pilot_sites", withExtension: "json"))
    let ids = try JSONDecoder().decode(Sites.self, from: Data(contentsOf: url)).sites.map(\.id)
    XCTAssertEqual(ids.count, 19)

    for id in ids {
      let bundle = try await StubEntranceClient(site: id).resolve(address: id)
      let brief = bundle.destinationBrief(metersToDoor: 30)
      let context = SideOfStreetContext(
        metersToDoor: 30, entranceStreet: bundle.streetSide?.entranceStreet,
        streetSideDescription: bundle.streetSide.flatMap(StreetSideDescription.compassSide))
      let events: [FeedbackEvent] = [
        .destinationBrief(brief), .finalApproach(metersToDoor: 9, brief),
        .finalApproach(metersToDoor: nil, brief), .askSideOfStreet(context),
      ]
      for event in events {
        let phrase = try XCTUnwrap(SpeechChannel.phrase(for: event), id)
        assertNoCertainty(phrase, id)
      }
      if bundle.status == "partial" {
        XCTAssertTrue(
          Phrases.destinationBrief(brief).hasPrefix("No door on the map."),
          "\(id) is partial but briefed as \"\(Phrases.destinationBrief(brief))\"")
      }
    }
  }

  /// Golden check: the table produces the exact phrases the design doc specifies.
  func testPhrasesMatchDesignDoc() {
    XCTAssertEqual(SpeechChannel.phrase(for: .distance(meters: 18)), "About 60 feet")
    XCTAssertEqual(
      SpeechChannel.phrase(for: .buildingConfirmed(text: "77", offsetDegrees: nil)),
      "I can see 77 ahead. That looks like your building.")
    XCTAssertEqual(SpeechChannel.phrase(for: .noSafePath(roadCrossing: false)), Phrases.noSafePath)
    XCTAssertEqual(Phrases.noSafePath, "I don't have a safe path. Follow the sidewalk.")
  }
}
