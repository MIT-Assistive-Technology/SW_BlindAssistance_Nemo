//
//  nemo_softwareTests.swift
//  nemo-softwareTests
//
//  Created by Trish Zheng on 10/22/26.
//

import XCTest
@testable import nemo_software  

final class PhraseSafetyTests: XCTestCase {

    /// SAFE-1: no spoken phrase may claim certainty ("that's your building",
    /// "you've arrived"). GPS isn't accurate enough to say that — always hedge.
    func testNoCertaintyWordsInPhrases() {
        let channel = SpeechChannel(speaker: Speaker())

        // Banned certainty words/phrases.
        let banned = ["that's your", "that is your", "you've arrived",
                      "you have arrived", "definitely", "certainly",
                      "the correct", "your destination"]

        // One representative of each event the phrase table produces.
        // (.landmark/.warning carry strings from upstream — reviewed there, not here.)
        let events: [FeedbackEvent] = [
            .direction(offsetDegrees: 10),
            .direction(offsetDegrees: -30),
            .distance(meters: 18),
            .bearingLock,
            .buildingConfirmed(text: "Starbucks"),
            .doorDetected(offsetDegrees: 10, meters: 3),
            .lost,
            .arrival,
        ]

        for event in events {
            let phrase = channel.phrase(for: event).lowercased()
            for word in banned {
                XCTAssertFalse(phrase.contains(word),
                               "phrase \"\(phrase)\" contains banned word \"\(word)\"")
            }
        }
    }

    /// Golden check: the table produces the exact phrases the design doc specifies.
    func testPhrasesMatchDesignDoc() {
        let channel = SpeechChannel(speaker: Speaker())
        XCTAssertEqual(channel.phrase(for: .doorDetected(offsetDegrees: 10, meters: 3)),
                       "Door slightly right, 10 feet")
        XCTAssertEqual(channel.phrase(for: .distance(meters: 18)),
                       "About 60 feet")
    }
}
