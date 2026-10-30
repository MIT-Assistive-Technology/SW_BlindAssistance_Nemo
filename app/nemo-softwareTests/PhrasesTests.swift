//  PhrasesTests.swift
//  nemo-softwareTests
//
//  The words themselves. Phrasing is a safety feature here (SAFE-1): the app may say
//  the map shows a door, never that the rider has arrived at one.
//

import XCTest

@testable import nemo_software

final class PhrasesTests: XCTestCase {

  // MARK: Distances

  func testDistanceInFeetIsRounded() {
    // The plan's "about 110 feet" is 33.5 m.
    XCTAssertEqual(Phrases.distance(meters: 33.5), "about 110 feet")
    XCTAssertEqual(Phrases.distance(meters: 9.1), "about 30 feet")
    // Close in, round to 5 ft instead of 10.
    XCTAssertEqual(Phrases.distance(meters: 3), "about 10 feet")
    XCTAssertEqual(Phrases.distance(meters: 0.3), "about 5 feet")
  }

  func testDistanceInMetres() {
    XCTAssertEqual(Phrases.distance(meters: 33.5, units: .meters), "about 35 metres")
    XCTAssertEqual(Phrases.distance(meters: 3.4, units: .meters), "about 3 metres")
    XCTAssertEqual(Phrases.distance(meters: 0.1, units: .meters), "about 1 metres")
  }

  func testTurnWords() {
    XCTAssertEqual(Phrases.turn(offsetDegrees: 0), "straight ahead")
    XCTAssertEqual(Phrases.turn(offsetDegrees: 9), "straight ahead")
    XCTAssertEqual(Phrases.turn(offsetDegrees: 20), "slightly right")
    XCTAssertEqual(Phrases.turn(offsetDegrees: -20), "slightly left")
    XCTAssertEqual(Phrases.turn(offsetDegrees: 60), "to your right")
    XCTAssertEqual(Phrases.turn(offsetDegrees: -150), "behind you, to your left")
  }

  // MARK: Side of street (FE-13)

  func testSideOfStreetPhrases() {
    XCTAssertEqual(
      Phrases.sameSideOfStreet(metersToDoor: 33.5),
      "Your entrance should be on this side of the street, about 110 feet away.")
    XCTAssertEqual(
      Phrases.sameSideOfStreet(metersToDoor: nil),
      "Your entrance should be on this side of the street.")
    XCTAssertEqual(
      Phrases.acrossStreet(metersToCrossing: 30),
      "Your entrance is across the street. The nearest marked crossing is about 100 feet away. I'll stop guiding until you're across."
    )
  }

  func testAcrossTheStreetWithNoKnownCrossingStillLeavesSomethingToDo() {
    // "I'll stop guiding" can't be the whole message: a rider who can't look for a
    // crossing needs to be told there isn't a known one.
    let phrase = Phrases.acrossStreet(metersToCrossing: nil)
    XCTAssertTrue(phrase.contains("don't know of a marked crossing"))
    XCTAssertTrue(phrase.contains("follow the sidewalk"))
  }

  func testTheSideQuestionNamesTheStreetWhenItIsKnown() {
    XCTAssertEqual(
      Phrases.askSideOfStreet(
        entranceStreet: "Massachusetts Avenue", streetSideDescription: "east"),
      "Your entrance is on the east side of Massachusetts Avenue. \(Phrases.askSideOfStreet)")
    // Street unknown: ask the plain question rather than an awkward half-sentence.
    XCTAssertEqual(
      Phrases.askSideOfStreet(entranceStreet: nil, streetSideDescription: "east"),
      Phrases.askSideOfStreet)
    XCTAssertEqual(
      Phrases.askSideOfStreet(entranceStreet: "Example Avenue", streetSideDescription: nil),
      "Your entrance is on Example Avenue. \(Phrases.askSideOfStreet)")
  }

  func testExitPromptNeverAssumesACurb() {
    // Ride-hail cars often stop in a travel lane, so the app says which side, not that
    // the rider is on a sidewalk.
    XCTAssertEqual(Phrases.exitCurbSide, "Exit on the curb side.")
    XCTAssertFalse(Phrases.exitCurbSide.lowercased().contains("sidewalk"))
  }

  func testTheStopPromptIsConditionalAndAsksTheRider() {
    // A stop the phone noticed could be a red light, so the prompt must not read as an
    // instruction to get out, and it must hand the decision back to the rider.
    let prompt = Phrases.possibleDropOff(metersToDoor: nil)
    XCTAssertTrue(prompt.contains("If this is your drop-off"))
    XCTAssertTrue(prompt.contains("tell me when you're out of the car"))
    XCTAssertFalse(prompt.hasPrefix("Exit"))
  }

  func testTheStopPromptQuotesTheDistanceWhenItIsKnown() {
    // The distance is what makes the question answerable without looking outside.
    XCTAssertEqual(
      Phrases.possibleDropOff(metersToDoor: 12),
      "It looks like the car has stopped, about 40 feet from your entrance. If this is your drop-off, exit on the curb side, then tell me when you're out of the car."
    )
    XCTAssertEqual(
      Phrases.possibleDropOff(metersToDoor: nil),
      "It looks like the car has stopped. If this is your drop-off, exit on the curb side, then tell me when you're out of the car."
    )
  }

  // MARK: Destination brief

  func testBriefForATaggedMainEntrance() {
    let brief = DestinationBrief(
      band: "main", entranceStreet: "Massachusetts Avenue", streetSideDescription: "east",
      housenumber: "77", door: "hinged", automaticDoor: "button", stepCount: 3,
      metersToDoor: 33.5)
    XCTAssertEqual(
      Phrases.destinationBrief(brief),
      "Map shows the main entrance for number 77, about 110 feet ahead. It faces Massachusetts Avenue on the east side. It has 3 steps and a push-button door."
    )
  }

  func testBriefForAPlainDoorWarnsItMayNotBeTheMainOne() {
    XCTAssertEqual(
      Phrases.destinationBrief(DestinationBrief(band: "door", metersToDoor: 33.5)),
      "Map shows a door, about 110 feet ahead. It may not be the main entrance.")
  }

  func testBriefForAFacadeSaysThereIsNoDoorOnTheMap() {
    XCTAssertEqual(
      Phrases.destinationBrief(DestinationBrief(band: "facade")),
      "No door on the map. I'll guide you to the street-facing side.")
  }

  func testDoorFactsAreOptional() {
    XCTAssertNil(Phrases.doorFacts(DestinationBrief(band: "main")))
    XCTAssertEqual(
      Phrases.doorFacts(DestinationBrief(band: "main", stepCount: 1)), "It has 1 step.")
    XCTAssertEqual(
      Phrases.doorFacts(DestinationBrief(band: "main", door: "revolving")),
      "It has a revolving door.")
    XCTAssertEqual(
      Phrases.doorFacts(DestinationBrief(band: "main", automaticDoor: "motion", stepCount: 2)),
      "It has 2 steps and an automatic door.")
  }

  // MARK: SAFE-1

  func testNoPhrasePromisesCertainty() {
    for phrase in Phrases.all {
      let lowered = phrase.lowercased()
      for banned in Phrases.bannedCertaintyPhrases {
        XCTAssertFalse(
          lowered.contains(banned),
          "\"\(phrase)\" contains the certainty phrase \"\(banned)\"")
      }
    }
  }

  func testEveryPhraseIsNonEmptyAndEndsCleanly() {
    for phrase in Phrases.all {
      XCTAssertFalse(phrase.isEmpty)
      XCTAssertFalse(phrase.hasSuffix(" "), "\"\(phrase)\" ends in a space")
      XCTAssertFalse(phrase.contains("  "), "\"\(phrase)\" has a double space")
    }
  }
}

/// `SpeechChannel` is the only place events become words, so the mapping and the
/// chatter guard are checked here rather than by listening to the phone.
@MainActor
final class SpeechChannelTests: XCTestCase {

  private final class RecordingSpeaker: SpeechOutput {
    var spoken: [String] = []
    var stopped = 0
    func speak(_ text: String) { spoken.append(text) }
    func stop() { stopped += 1 }
  }

  func testEventsBecomePhrases() {
    XCTAssertEqual(
      SpeechChannel.phrase(for: .heading(degrees: 45, accuracyDegrees: 10)),
      "Facing north east, 45 degrees.")
    XCTAssertEqual(SpeechChannel.phrase(for: .compassCalibration), Phrases.compassCalibration)
    XCTAssertEqual(SpeechChannel.phrase(for: .exitCurbSide), Phrases.exitCurbSide)
    XCTAssertEqual(
      SpeechChannel.phrase(for: .possibleDropOff(metersToDoor: 12)),
      Phrases.possibleDropOff(metersToDoor: 12))
    XCTAssertEqual(
      SpeechChannel.phrase(for: .askSideOfStreet(SideOfStreetContext())),
      Phrases.askSideOfStreet)
    XCTAssertEqual(
      SpeechChannel.phrase(for: .locationPermissionDenied), Phrases.locationPermissionDenied)
    XCTAssertEqual(
      SpeechChannel.phrase(for: .rideTracking(started: true)), Phrases.rideTrackingStarted)
    XCTAssertEqual(SpeechChannel.phrase(for: .distance(meters: 33.5)), "About 110 feet")
    XCTAssertEqual(SpeechChannel.phrase(for: .direction(offsetDegrees: 20)), "Slightly right")
  }

  func testSideOfStreetEventPicksThePhraseForTheAnswer() {
    XCTAssertEqual(
      SpeechChannel.phrase(
        for: .sideOfStreet(.sameSide, SideOfStreetContext(metersToDoor: 33.5))),
      Phrases.sameSideOfStreet(metersToDoor: 33.5))
    XCTAssertEqual(
      SpeechChannel.phrase(
        for: .sideOfStreet(
          .acrossStreet, SideOfStreetContext(metersToDoor: 33.5, metersToCrossing: 30))),
      Phrases.acrossStreet(metersToCrossing: 30))
    // Unknown means ask, never guess, and the question names the street so a rider who
    // can't see has something to answer with.
    XCTAssertEqual(
      SpeechChannel.phrase(
        for: .sideOfStreet(
          .unknown(.oneway),
          SideOfStreetContext(entranceStreet: "Example Avenue", streetSideDescription: "west"))),
      "Your entrance is on the west side of Example Avenue. \(Phrases.askSideOfStreet)")
    // With nothing known about the street, the plain question is still asked.
    XCTAssertEqual(
      SpeechChannel.phrase(for: .sideOfStreet(.unknown(.oneway), SideOfStreetContext())),
      Phrases.askSideOfStreet)
  }

  func testFailuresAndAcknowledgementsHaveWords() {
    // Anything a sighted user would read on screen has to be sayable.
    XCTAssertEqual(
      SpeechChannel.phrase(for: .lookingUpDestination), Phrases.lookingUpEntrance)
    XCTAssertEqual(
      SpeechChannel.phrase(for: .destinationLookupFailed(.addressNotFound)),
      "I couldn't find that address.")
    XCTAssertEqual(
      SpeechChannel.phrase(for: .destinationLookupFailed(.noCachedCopy)),
      Phrases.lookupFailed(.noCachedCopy))
    XCTAssertEqual(
      SpeechChannel.phrase(for: .noDestinationLoaded), Phrases.noDestinationLoaded)
    XCTAssertEqual(
      SpeechChannel.phrase(for: .bundleNotSavedForOffline), Phrases.bundleNotSavedForOffline)
  }

  func testLookupFailureIsClassifiedFromTheError() {
    XCTAssertEqual(
      LookupFailure(
        EntranceError.service(
          code: "GEOCODE_NOT_FOUND", message: "", requestId: nil, httpStatus: 404)),
      .addressNotFound)
    XCTAssertEqual(LookupFailure(EntranceError.noCachedResult), .noCachedCopy)
    XCTAssertEqual(LookupFailure(URLError(.notConnectedToInternet)), .other)
    XCTAssertEqual(LookupFailure(EntranceError.badResponse(httpStatus: 500)), .other)
  }

  func testAskedAgainMeansSaidAgain() {
    // The chatter guard must never swallow an explicit "repeat": silence is
    // indistinguishable from a broken app when you can't see the screen.
    let speaker = RecordingSpeaker()
    let channel = SpeechChannel(speaker: speaker)
    channel.play(.exitCurbSide)
    channel.play(.exitCurbSide)
    XCTAssertEqual(speaker.spoken.count, 1)
    channel.play(.exitCurbSide, force: true)
    XCTAssertEqual(speaker.spoken.count, 2)

    let kit = FeedbackKit(channels: [channel])
    kit.emit(.exitCurbSide, force: true)
    XCTAssertEqual(speaker.spoken.count, 3)
  }

  func testTheWalkEventsHaveWords() {
    // The walk is speech-only until the beacon and haptics land, so every state change
    // in the trip has to be sayable.
    XCTAssertEqual(SpeechChannel.phrase(for: .startingGuidance), Phrases.startingGuidance)
    XCTAssertEqual(
      SpeechChannel.phrase(for: .bearingLock(metersToDoor: 33.5)),
      Phrases.bearingLock(metersToDoor: 33.5))
    XCTAssertEqual(SpeechChannel.phrase(for: .directionUncertain), Phrases.directionUncertain)
    XCTAssertEqual(SpeechChannel.phrase(for: .lost), Phrases.offRoute)
    XCTAssertEqual(SpeechChannel.phrase(for: .arrival), Phrases.arrivedAtDoor)
    XCTAssertEqual(SpeechChannel.phrase(for: .guidanceStopped), Phrases.guidanceStopped)
    XCTAssertEqual(
      SpeechChannel.phrase(for: .waitingToCrossStreet), Phrases.waitingToCrossStreet)
    XCTAssertEqual(
      SpeechChannel.phrase(
        for: .finalApproach(metersToDoor: 9, DestinationBrief(band: "main", stepCount: 3))),
      Phrases.finalApproach(
        metersToDoor: 9, brief: DestinationBrief(band: "main", stepCount: 3)))
  }

  func testTheBuildingCheckEventsHaveWords() {
    // CV-9's results have to be sayable before the camera work lands, so the perception
    // side has something to emit into.
    XCTAssertEqual(
      SpeechChannel.phrase(for: .buildingConfirmed(text: "77", offsetDegrees: 20)),
      "I can see 77 ahead slightly right. That looks like your building.")
    XCTAssertEqual(
      SpeechChannel.phrase(for: .buildingUncertain(text: "77")),
      "I see 77, but it may not be your building.")
    XCTAssertEqual(
      SpeechChannel.phrase(for: .cameraCheckUnavailable(.lowLight)),
      "Camera check unavailable in low light.")
  }

  func testTheBuildingCheckNeverClaimsCertainty() {
    // Plan section 7: "That looks like your building", never "That's your building".
    let confirmed = Phrases.buildingConfirmed(text: "77", offsetDegrees: nil)
    XCTAssertTrue(confirmed.contains("looks like"))
    XCTAssertFalse(confirmed.lowercased().contains("that's your building"))
  }

  func testTheLandmarkAndDoorEventsStillHaveNoWords() {
    // These wait for the landmark and door-detector work; staying silent beats
    // inventing phrasing that SAFE-1 hasn't reviewed.
    XCTAssertNil(SpeechChannel.phrase(for: .doorDetected(offsetDegrees: 10, meters: 3)))
    XCTAssertNil(SpeechChannel.phrase(for: .landmark(phrase: "bench on your left")))
  }

  func testNoWalkPhraseRefersToASoundTheAppCannotPlay() {
    // There is no spatial beacon yet (FE-4). Telling a rider to "turn until the tone
    // centres" would be an instruction they can't follow.
    for phrase in [Phrases.offRoute, Phrases.bearingLock(metersToDoor: 33.5), Phrases.startingGuidance] {
      XCTAssertFalse(phrase.lowercased().contains("tone"), phrase)
      XCTAssertFalse(phrase.lowercased().contains("beacon"), phrase)
    }
  }

  func testUnitsAreRespected() {
    XCTAssertEqual(
      SpeechChannel.phrase(
        for: .sideOfStreet(.sameSide, SideOfStreetContext(metersToDoor: 33.5)),
        units: .meters),
      "Your entrance should be on this side of the street, about 35 metres away.")
  }

  func testChatterGuardStopsRepeats() {
    var now = Date(timeIntervalSinceReferenceDate: 0)
    let speaker = RecordingSpeaker()
    let channel = SpeechChannel(speaker: speaker, units: .feet, now: { now })

    channel.play(.exitCurbSide)
    channel.play(.exitCurbSide)
    XCTAssertEqual(speaker.spoken, [Phrases.exitCurbSide])

    // A different phrase always gets through.
    channel.play(.askSideOfStreet(SideOfStreetContext()))
    XCTAssertEqual(speaker.spoken.count, 2)

    // And the same one again once the guard window has passed.
    now = now.addingTimeInterval(10)
    channel.play(.askSideOfStreet(SideOfStreetContext()))
    XCTAssertEqual(speaker.spoken.count, 3)
  }

  func testStopClearsTheGuardAndStopsTheSpeaker() {
    let speaker = RecordingSpeaker()
    let channel = SpeechChannel(speaker: speaker)
    channel.play(.exitCurbSide)
    channel.stop()
    channel.play(.exitCurbSide)
    XCTAssertEqual(speaker.stopped, 1)
    XCTAssertEqual(speaker.spoken.count, 2)
  }

  func testFeedbackKitSendsEventsToEveryChannel() {
    let first = RecordingSpeaker()
    let second = RecordingSpeaker()
    let kit = FeedbackKit(channels: [
      SpeechChannel(speaker: first), SpeechChannel(speaker: second),
    ])
    kit.emit(.exitCurbSide)
    kit.stopAll()
    XCTAssertEqual(first.spoken, [Phrases.exitCurbSide])
    XCTAssertEqual(second.spoken, [Phrases.exitCurbSide])
    XCTAssertEqual(first.stopped, 1)
  }
}
