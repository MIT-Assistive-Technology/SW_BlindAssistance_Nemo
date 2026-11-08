//  HazardTests.swift
//  nemo-softwareTests
//
//  The hazard path (Person B): what the detector and the depth scan tell the session,
//  how often it speaks, and the words it uses. Same replay-harness style as
//  `NavigationSessionTests` — positions walk towards the example bundle's door.
//

import XCTest

@testable import nemo_software

@MainActor
final class HazardTests: XCTestCase {

  private final class RecordingSpeaker: SpeechOutput {
    var spoken: [String] = []
    func speak(_ text: String) { spoken.append(text) }
    func stop() {}
  }

  private var speaker: RecordingSpeaker!
  private var session: NavigationSession!
  private let base = Date(timeIntervalSinceReferenceDate: 0)

  private let doorLat = 42.35921
  private let doorLon = -71.09298

  override func setUp() async throws {
    try await super.setUp()
    speaker = RecordingSpeaker()
    let channel = SpeechChannel(speaker: speaker)
    channel.repeatGuard = 0
    session = NavigationSession(feedback: FeedbackKit(channels: [channel]))
    let bundle = try await StubEntranceClient().resolve(address: "77 Example Avenue")
    session.setDestination(bundle, address: "77 Example Avenue")
  }

  /// Walk in .guide, 55 m north of the door facing it.
  private func startWalking() {
    session.startRiding()
    session.riderIsOutOfCar(isOnDoorSide: true)
    session.startGuidance()
    session.update(position: position(seconds: 0), heading: heading(seconds: 0))
    session.update(position: position(seconds: 2), heading: heading(seconds: 2))
    XCTAssertEqual(session.state, .guide)
    speaker.spoken = []
  }

  private func position(seconds: TimeInterval) -> GuidancePosition {
    GuidancePosition(
      latitude: doorLat + 55 / 111_194.93, longitude: doorLon,
      horizontalAccuracyMeters: 5, timestamp: base.addingTimeInterval(seconds))
  }

  private func heading(seconds: TimeInterval) -> HeadingReadout {
    HeadingReadout(
      trueHeadingDegrees: 180, accuracyDegrees: 10,
      timestamp: base.addingTimeInterval(seconds))
  }

  // MARK: Label mapping

  func testDetectorLabelsMapOntoTheFixedKinds() {
    XCTAssertEqual(HazardSighting.Kind(label: "person"), .person)
    XCTAssertEqual(HazardSighting.Kind(label: "car"), .vehicle)
    XCTAssertEqual(HazardSighting.Kind(label: "truck"), .vehicle)
    XCTAssertEqual(HazardSighting.Kind(label: "bicycle"), .bike)
    XCTAssertEqual(HazardSighting.Kind(label: "pole"), .pole)
    XCTAssertEqual(HazardSighting.Kind(label: "traffic cone"), .cone)
    XCTAssertEqual(HazardSighting.Kind(label: "dog"), .dog)
    XCTAssertEqual(HazardSighting.Kind(label: "squirrel"), .animal)
    XCTAssertEqual(HazardSighting.Kind(label: "pigeon"), .animal)
    XCTAssertEqual(HazardSighting.Kind(label: "barricade"), .construction)
    XCTAssertEqual(HazardSighting.Kind(label: "bench"), .bench)
    XCTAssertEqual(HazardSighting.Kind(label: "foundation"), .wall)
    // Everything else is "seen, not worth a spoken hazard".
    XCTAssertNil(HazardSighting.Kind(label: "stop sign"))
  }

  // MARK: What gets spoken

  func testANamedHazardIsAnnouncedWithItsDirectionAndDistance() {
    startWalking()
    session.observeHazard(
      HazardSighting(kind: .person, offsetDegrees: 0, meters: 2.1, timestamp: base))
    XCTAssertEqual(speaker.spoken, ["Person straight ahead, about 5 feet."])
  }

  func testAStepDownFromDepthIsAnnounced() {
    startWalking()
    session.observeHazard(
      HazardSighting(kind: .stepDown, offsetDegrees: -15, meters: 1.5, timestamp: base))
    XCTAssertEqual(speaker.spoken, ["Step down slightly left, about 5 feet."])
  }

  func testTheSameHazardRepeatsOnlyAfterTheWindow() {
    startWalking()
    session.observeHazard(
      HazardSighting(kind: .object, offsetDegrees: 0, meters: 2, timestamp: base))
    session.observeHazard(
      HazardSighting(
          kind: .object, offsetDegrees: 5, meters: 1.5,
          timestamp: base.addingTimeInterval(3)))
    XCTAssertEqual(speaker.spoken.count, 1, "said: \(speaker.spoken)")
    // After the window it counts as new — and says the updated distance.
    session.observeHazard(
      HazardSighting(
          kind: .object, offsetDegrees: 5, meters: 1,
          timestamp: base.addingTimeInterval(11)))
    XCTAssertEqual(speaker.spoken.count, 2, "said: \(speaker.spoken)")
  }

  func testDepthsSomethingIsSuppressedWhenTheDetectorNamedIt() {
    startWalking()
    // The detector sees a person slightly right; depth reports "something" in the
    // same spot on its next scan. One object must not become two announcements.
    session.observeHazard(
      HazardSighting(kind: .person, offsetDegrees: 12, meters: 2, timestamp: base))
    session.observeHazard(
      HazardSighting(
          kind: .object, offsetDegrees: 15, meters: 2,
          timestamp: base.addingTimeInterval(1)))
    XCTAssertEqual(speaker.spoken.count, 1, "said: \(speaker.spoken)")
    XCTAssertTrue(speaker.spoken[0].hasPrefix("Person"))
    // Far enough away in the frame, "something" is a different thing.
    session.observeHazard(
      HazardSighting(
          kind: .object, offsetDegrees: -20, meters: 2.5,
          timestamp: base.addingTimeInterval(2)))
    XCTAssertEqual(speaker.spoken.count, 2, "said: \(speaker.spoken)")
  }

  func testHazardsAreNotAnnouncedOutsideTheWalk() {
    // Still in the car: a hazard is noise.
    session.startRiding()
    XCTAssertFalse(
      session.observeHazard(
        HazardSighting(kind: .person, offsetDegrees: 0, timestamp: base)))
    XCTAssertTrue(speaker.spoken.isEmpty)
  }

  func testLowConfidenceSightingsAreIgnored() {
    startWalking()
    XCTAssertFalse(
      session.observeHazard(
        HazardSighting(kind: .person, offsetDegrees: 0, confidence: 0.2, timestamp: base)))
    XCTAssertTrue(speaker.spoken.isEmpty)
  }

  // MARK: Steering

  /// A scan with the centre slice blocked and the rest clear. Facing the door puts
  /// `offsetDegrees` at ~0, so the target slice is the centre one.
  private func scan(
    centre: FreeSpace.Status, timestamp: TimeInterval = 20
  ) -> FreeSpace {
    let centres: [Double] = [-28, -14, 0, 14, 28]
    return FreeSpace(
      slices: centres.map {
        FreeSpace.Slice(
          offsetDegrees: $0, status: $0 == 0 ? centre : .clear)
      },
      timestamp: base.addingTimeInterval(timestamp))
  }

  func testABlockedTargetSteersAroundItWithAReason() {
    startWalking()
    session.observeFreeSpace(scan(centre: .blocked(meters: 2)))
    XCTAssertEqual(
      speaker.spoken, ["Something straight ahead, about 5 feet. Go slightly left."])
  }

  func testANamedHazardSteersWithItsName() {
    startWalking()
    session.observeHazard(
      HazardSighting(
        kind: .person, offsetDegrees: 3, timestamp: base.addingTimeInterval(19)))
    session.observeFreeSpace(scan(centre: .blocked(meters: 2)))
    XCTAssertTrue(
      speaker.spoken.contains("Person straight ahead, about 5 feet. Go slightly left."),
      "said: \(speaker.spoken)")
  }

  func testAStepDownSteersAsAStepDown() {
    startWalking()
    session.observeFreeSpace(scan(centre: .drop(meters: 1.5)))
    XCTAssertEqual(
      speaker.spoken, ["Step down straight ahead, about 5 feet. Go slightly left."])
  }

  func testAWallSaysTheWayIsBlockedNotJustASteer() {
    startWalking()
    // The detector names the wall; depth reports the blocked slice in the same spot.
    session.observeHazard(
      HazardSighting(
        kind: .wall, offsetDegrees: 3, timestamp: base.addingTimeInterval(19)))
    session.observeFreeSpace(scan(centre: .blocked(meters: 2)))
    XCTAssertTrue(
      speaker.spoken.contains(
        "Wall straight ahead, about 5 feet, blocking the way. Go slightly left to get around it."),
      "said: \(speaker.spoken)")
  }

  func testAWalkAroundStillGetsASteerCueNotADetour() {
    startWalking()
    session.observeHazard(
      HazardSighting(
        kind: .cone, offsetDegrees: 3, timestamp: base.addingTimeInterval(19)))
    session.observeFreeSpace(scan(centre: .blocked(meters: 2)))
    XCTAssertTrue(
      speaker.spoken.contains("Cone straight ahead, about 5 feet. Go slightly left."),
      "said: \(speaker.spoken)")
    XCTAssertFalse(speaker.spoken.contains { $0.contains("blocking the way") })
  }

  func testEverythingBlockedSaysStop() {
    startWalking()
    session.observeFreeSpace(
      FreeSpace(
        slices: [-28, -14, 0, 14, 28].map {
          FreeSpace.Slice(offsetDegrees: $0, status: .blocked(meters: 1))
        },
        timestamp: base.addingTimeInterval(20)))
    XCTAssertTrue(speaker.spoken.contains(Phrases.pathBlocked), "said: \(speaker.spoken)")
  }

  func testClearAgainSendsThemBackOnCourse() {
    startWalking()
    session.observeFreeSpace(scan(centre: .blocked(meters: 2), timestamp: 20))
    XCTAssertEqual(speaker.spoken.count, 1)
    session.observeFreeSpace(scan(centre: .clear, timestamp: 25))
    XCTAssertEqual(
      speaker.spoken.last, "The way ahead looks clear. Go straight ahead.")
  }

  // MARK: Phrases

  func testHazardPhrasesHaveWordsAndNoClaims() {
    XCTAssertEqual(
      SpeechChannel.phrase(for: .hazardAhead(.cone, offsetDegrees: 10, meters: nil)),
      "Cone slightly right.")
    XCTAssertEqual(
      SpeechChannel.phrase(for: .hazardAhead(.object, offsetDegrees: 0, meters: 1.8)),
      "Something straight ahead, about 5 feet.")
    // A hazard notice never steers and never promises clearance: it names a thing
    // and where it is, and the cane decides.
    for kind in HazardSighting.Kind.allCases {
      let phrase = Phrases.hazardAhead(kind: kind, offsetDegrees: 0, meters: 2)
      XCTAssertFalse(phrase.lowercased().contains("safe"), phrase)
      XCTAssertFalse(phrase.lowercased().contains("clear"), phrase)
    }
  }
}
