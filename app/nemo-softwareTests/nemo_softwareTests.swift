//
//  nemo_softwareTests.swift
//  nemo-softwareTests
//
//  Created by Trish Zheng on 10/22/26.
//
//  Updated while merging `trish-navigation`: `phrase(for:)` is now static and returns
//  nil for events that have no reviewed wording yet, `.bearingLock` carries the
//  distance, and `.buildingConfirmed` carries the offset. The banned-word list is kept
//  as written — it's stricter than the one in PhrasesTests, so both are worth running.
//

import XCTest

@testable import nemo_software

@MainActor
final class PhraseSafetyTests: XCTestCase {

  /// SAFE-1: no spoken phrase may claim certainty ("that's your building",
  /// "you've arrived"). GPS isn't accurate enough to say that — always hedge.
  func testNoCertaintyWordsInPhrases() {
    // Banned certainty words/phrases.
    let banned = [
      "that's your", "that is your", "you've arrived",
      "you have arrived", "definitely", "certainly",
      "the correct", "your destination",
    ]

    // One representative of each event the phrase table produces.
    // (.landmark/.warning carry strings from upstream — reviewed there, not here.)
    let events: [FeedbackEvent] = [
      .direction(offsetDegrees: 10),
      .direction(offsetDegrees: -30),
      .distance(meters: 18),
      .bearingLock(metersToDoor: 33.5),
      .buildingConfirmed(text: "Starbucks", offsetDegrees: 10),
      .buildingUncertain(text: "Starbucks"),
      .doorDetected(offsetDegrees: 10, meters: 3),
      .lost,
      .arrival,
    ]

    for event in events {
      guard let phrase = SpeechChannel.phrase(for: event)?.lowercased() else { continue }
      for word in banned {
        XCTAssertFalse(
          phrase.contains(word),
          "phrase \"\(phrase)\" contains banned word \"\(word)\"")
      }
    }
  }

  /// The same check over every phrase in the table, not just the ones with events.
  func testNoCertaintyWordsAnywhereInTheTable() {
    let banned = [
      "that's your", "that is your", "you've arrived",
      "you have arrived", "definitely", "certainly",
      "the correct", "your destination",
    ]
    for phrase in Phrases.all {
      let lowered = phrase.lowercased()
      for word in banned {
        XCTAssertFalse(lowered.contains(word), "\"\(phrase)\" contains \"\(word)\"")
      }
    }
  }

  /// Golden check: the table produces the exact phrases the design doc specifies.
  func testPhrasesMatchDesignDoc() {
    XCTAssertEqual(SpeechChannel.phrase(for: .distance(meters: 18)), "About 60 feet")
    // `.doorDetected` has no reviewed wording yet — it waits for the door detector, and
    // staying silent beats inventing a phrase SAFE-1 hasn't seen.
    XCTAssertNil(SpeechChannel.phrase(for: .doorDetected(offsetDegrees: 10, meters: 3)))
  }
}
