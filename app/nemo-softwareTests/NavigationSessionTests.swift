//  NavigationSessionTests.swift
//  nemo-softwareTests
//
//  FE-10. The task's definition of done is "tests replay a full trip, a lost-and-recover
//  trip and a relaunch mid-ride", so that's what these do: synthetic positions walking
//  towards the example bundle's door, no car and no walking required.
//
//  The door is at 42.35921, -71.09298. 0.0001° of latitude is about 11.1 m, so walking
//  south down that longitude is a straight approach on a bearing of 180°.
//

import XCTest

@testable import nemo_software

@MainActor
final class NavigationSessionTests: XCTestCase {

  private final class RecordingSpeaker: SpeechOutput {
    var spoken: [String] = []
    func speak(_ text: String) { spoken.append(text) }
    func stop() {}
  }

  private var speaker: RecordingSpeaker!
  private var store: SessionStore!
  private var session: NavigationSession!
  private var bundle: ResolveResult!
  private let address = "77 Example Avenue"
  private let base = Date(timeIntervalSinceReferenceDate: 0)

  private let doorLat = 42.35921
  private let doorLon = -71.09298

  override func setUp() async throws {
    try await super.setUp()
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("SessionTests-\(UUID().uuidString)", isDirectory: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }

    speaker = RecordingSpeaker()
    let channel = SpeechChannel(speaker: speaker)
    channel.repeatGuard = 0  // a whole trip replays in milliseconds
    store = SessionStore(directory: directory)
    session = NavigationSession(feedback: FeedbackKit(channels: [channel]), store: store)
    bundle = try await StubEntranceClient().resolve(address: address)
    session.setDestination(bundle, address: address)
  }

  /// A position `metersNorth` of the door, `seconds` into the trip.
  private func position(metersNorth: Double, seconds: TimeInterval, metersEast: Double = 0)
    -> GuidancePosition
  {
    let metersPerDegree = 111_194.93
    return GuidancePosition(
      latitude: doorLat + metersNorth / metersPerDegree,
      longitude: doorLon + metersEast / (metersPerDegree * cos(doorLat * .pi / 180)),
      horizontalAccuracyMeters: 5,
      timestamp: base.addingTimeInterval(seconds))
  }

  /// Facing south, straight at the door.
  private func heading(_ degrees: Double, seconds: TimeInterval) -> HeadingReadout {
    HeadingReadout(
      trueHeadingDegrees: degrees, accuracyDegrees: 10,
      timestamp: base.addingTimeInterval(seconds))
  }

  private func arriveAtCurb(onDoorSide: Bool = true) {
    session.startRiding()
    session.riderIsOutOfCar(isOnDoorSide: onDoorSide)
  }

  // MARK: A full trip

  func testAFullTripFromTheCurbToTheDoor() {
    XCTAssertEqual(session.state, .setup)
    session.startRiding()
    XCTAssertEqual(session.state, .riding)
    session.riderIsOutOfCar(isOnDoorSide: true)
    XCTAssertEqual(session.state, .arrival)
    XCTAssertTrue(session.canStartGuidance)

    session.startGuidance()
    XCTAssertEqual(session.state, .orient)
    XCTAssertTrue(speaker.spoken.contains(Phrases.startingGuidance))

    // Facing the wrong way: told which way to turn, and not locked on.
    session.update(position: position(metersNorth: 55, seconds: 0), heading: heading(90, seconds: 0))
    XCTAssertEqual(session.state, .orient)
    XCTAssertTrue(speaker.spoken.contains("To your right"), "said: \(speaker.spoken)")

    // Turned to face the door, held for a second.
    session.update(position: position(metersNorth: 55, seconds: 1), heading: heading(180, seconds: 1))
    XCTAssertEqual(session.state, .orient, "a lock needs to be held")
    session.update(position: position(metersNorth: 55, seconds: 3), heading: heading(180, seconds: 3))
    XCTAssertEqual(session.state, .guide)
    XCTAssertTrue(
      speaker.spoken.contains { $0.hasPrefix("That's the direction") }, "said: \(speaker.spoken)")

    // Walking south. Distance callouts at 60 ft and 30 ft, said once each.
    session.update(position: position(metersNorth: 33, seconds: 10), heading: heading(180, seconds: 10))
    XCTAssertEqual(session.state, .guide, "no first-steps complaint when walking the right way")
    session.update(position: position(metersNorth: 17, seconds: 20), heading: heading(180, seconds: 20))
    XCTAssertTrue(speaker.spoken.contains { $0.contains("60 feet") }, "said: \(speaker.spoken)")

    // Inside 10 m: the door facts from the bundle.
    session.update(position: position(metersNorth: 8, seconds: 30), heading: heading(180, seconds: 30))
    XCTAssertEqual(session.state, .confirm)
    XCTAssertTrue(
      speaker.spoken.contains { $0.contains("3 steps and a push-button door") },
      "said: \(speaker.spoken)")

    // At the door. Never "you have arrived" (SAFE-1).
    session.update(position: position(metersNorth: 2, seconds: 40), heading: heading(180, seconds: 40))
    XCTAssertEqual(session.state, .arrived)
    XCTAssertTrue(speaker.spoken.contains(Phrases.arrivedAtDoor))
    XCTAssertFalse(speaker.spoken.contains { $0.lowercased().contains("you have arrived") })
    // The trip is over, so there's nothing to resume.
    XCTAssertNil(store.load())
  }

  func testDistanceCalloutsAreSaidOnce() {
    arriveAtCurb()
    session.startGuidance()
    session.update(position: position(metersNorth: 55, seconds: 0), heading: heading(180, seconds: 0))
    session.update(position: position(metersNorth: 55, seconds: 2), heading: heading(180, seconds: 2))
    session.update(position: position(metersNorth: 17, seconds: 10), heading: heading(180, seconds: 10))
    session.update(position: position(metersNorth: 16, seconds: 12), heading: heading(180, seconds: 12))
    session.update(position: position(metersNorth: 15, seconds: 14), heading: heading(180, seconds: 14))
    XCTAssertEqual(speaker.spoken.filter { $0.contains("feet") && $0.hasPrefix("About") }.count, 1)
  }

  // MARK: Lost and recover

  private func startWalking() {
    arriveAtCurb()
    session.startGuidance()
    session.update(position: position(metersNorth: 55, seconds: 0), heading: heading(180, seconds: 0))
    session.update(position: position(metersNorth: 55, seconds: 2), heading: heading(180, seconds: 2))
    XCTAssertEqual(session.state, .guide)
  }

  func testWalkingOffCourseIsLostAndThenRecovers() {
    startWalking()
    // Walked a bit, then turned 120° off and stayed there.
    session.update(position: position(metersNorth: 45, seconds: 10), heading: heading(180, seconds: 10))
    session.update(position: position(metersNorth: 40, seconds: 14), heading: heading(300, seconds: 14))
    XCTAssertEqual(session.state, .guide, "being off course briefly is not lost")
    session.update(position: position(metersNorth: 38, seconds: 20), heading: heading(300, seconds: 20))
    XCTAssertEqual(session.state, .lost)
    XCTAssertTrue(speaker.spoken.contains(Phrases.offRoute))

    // While lost the target is a breadcrumb at least 10 m back, not the door and not the
    // newest crumb (40 m north, 2 m away, about where the rider already is). Here that is
    // the 55 m crumb. Fails if the aim is the door, the newest crumb, or anything closer
    // than 10 m.
    let crumb = session.targetCoordinate
    XCTAssertNotNil(crumb)
    XCTAssertEqual(crumb?.lat ?? 0, position(metersNorth: 55, seconds: 0).latitude, accuracy: 1e-7)
    let lostAt = position(metersNorth: 38, seconds: 20)
    XCTAssertGreaterThanOrEqual(
      Geo.distanceMeters(
        lat1: lostAt.latitude, lon1: lostAt.longitude, lat2: crumb?.lat ?? lostAt.latitude,
        lon2: crumb?.lon ?? lostAt.longitude), 10)

    // Turning back towards it for 2 s re-anchors and returns to orienting.
    let bearingToCrumb = Geo.bearingDegrees(
      lat1: position(metersNorth: 38, seconds: 0).latitude,
      lon1: position(metersNorth: 38, seconds: 0).longitude,
      lat2: crumb!.lat, lon2: crumb!.lon)
    session.update(
      position: position(metersNorth: 38, seconds: 24),
      heading: heading(bearingToCrumb, seconds: 24))
    XCTAssertEqual(session.state, .lost, "recovery is held for a moment too")
    session.update(
      position: position(metersNorth: 38, seconds: 27),
      heading: heading(bearingToCrumb, seconds: 27))
    XCTAssertEqual(session.state, .orient)
    // Never a silent change of plan (SAFE-10).
    XCTAssertTrue(speaker.spoken.contains(Phrases.reorienting), "said: \(speaker.spoken)")
  }

  func testTheFirstStepsCheckCatchesAWrongStart() {
    startWalking()
    // Six meters east instead of south: the anchor was probably wrong, so the app says
    // it isn't sure rather than confidently guiding the wrong way.
    session.update(
      position: position(metersNorth: 55, seconds: 10, metersEast: 6),
      heading: heading(180, seconds: 10))
    XCTAssertEqual(session.state, .lost)
    XCTAssertTrue(speaker.spoken.contains(Phrases.directionUncertain))
  }

  func testTheFirstStepsCheckDoesNotFireTooEarly() {
    startWalking()
    // Two meters off to the side is within the noise: no complaint yet.
    session.update(
      position: position(metersNorth: 54, seconds: 6, metersEast: 2),
      heading: heading(180, seconds: 6))
    XCTAssertEqual(session.state, .guide)
    XCTAssertFalse(speaker.spoken.contains(Phrases.directionUncertain))
  }

  // MARK: Across the street (plan section 6)

  func testGuidanceWaitsWhileTheDoorIsAcrossTheRoad() {
    arriveAtCurb(onDoorSide: false)
    XCTAssertFalse(session.canStartGuidance)
    session.startGuidance()
    XCTAssertEqual(session.state, .arrival, "never guide across a roadway")
    XCTAssertTrue(speaker.spoken.contains(Phrases.waitingToCrossStreet))

    // The rider says they're across; now it starts.
    session.riderIsOnDoorSide(true)
    session.startGuidance()
    XCTAssertEqual(session.state, .orient)
  }

  func testAnUnknownSideAsksInsteadOfGuessing() {
    session.startRiding()
    session.riderIsOutOfCar(isOnDoorSide: nil)
    session.startGuidance()
    XCTAssertEqual(session.state, .arrival)
    XCTAssertTrue(
      speaker.spoken.contains { $0.hasSuffix(Phrases.askSideOfStreet) },
      "said: \(speaker.spoken)")
  }

  // MARK: Relaunch

  func testARelaunchDuringTheRideAsksAboutTheSideOfStreetAgain() {
    session.startRiding()
    let saved = try? XCTUnwrap(store.load())
    XCTAssertEqual(saved?.state, .riding)

    // A fresh session, as a relaunched app would have.
    let resumed = NavigationSession(
      feedback: FeedbackKit(channels: [SpeechChannel(speaker: speaker)]), store: store)
    resumed.resume(from: saved!, bundle: bundle)
    XCTAssertEqual(resumed.state, .riding)
    // No car track survived the relaunch, so the side is unknown and it asks.
    XCTAssertNil(resumed.riderIsOnDoorSide)
    XCTAssertFalse(resumed.canStartGuidance)
    XCTAssertTrue(
      speaker.spoken.contains { $0.hasSuffix(Phrases.askSideOfStreet) },
      "said: \(speaker.spoken)")
  }

  func testARelaunchDuringTheWalkReAnchorsInsteadOfPretending() {
    startWalking()
    session.update(position: position(metersNorth: 40, seconds: 10), heading: heading(180, seconds: 10))
    let saved = try? XCTUnwrap(store.load())
    XCTAssertEqual(saved?.state, .guide)
    XCTAssertFalse(saved!.breadcrumbs.isEmpty, "breadcrumbs are saved for the re-anchor")

    let resumed = NavigationSession(
      feedback: FeedbackKit(channels: [SpeechChannel(speaker: speaker)]), store: store)
    resumed.resume(from: saved!, bundle: bundle)
    // The old heading lock can't be trusted, so it orients again rather than claiming
    // to still be on course.
    XCTAssertEqual(resumed.state, .orient)
    XCTAssertEqual(resumed.riderIsOnDoorSide, true)
    XCTAssertTrue(speaker.spoken.contains(Phrases.startingGuidance))
  }

  // MARK: Stopping and repeating

  func testStoppingEndsTheTripOutLoud() {
    startWalking()
    session.stop()
    XCTAssertEqual(session.state, .setup)
    XCTAssertTrue(speaker.spoken.contains(Phrases.guidanceStopped))
    XCTAssertNil(store.load(), "a stopped trip is not resumable")
  }

  func testWhereAmISaysSomethingInEveryState() {
    // "Where am I" is the one control a walking rider has, so it must never be silent.
    arriveAtCurb()
    for _ in 0..<1 {
      let before = speaker.spoken.count
      session.repeatGuidance()
      XCTAssertGreaterThan(speaker.spoken.count, before, "silent in \(session.state)")
    }
    session.startGuidance()
    for _ in 0..<1 {
      let before = speaker.spoken.count
      session.repeatGuidance()
      XCTAssertGreaterThan(speaker.spoken.count, before, "silent in \(session.state)")
    }
    startWalkingFromOrient()
    for state in [SessionState.guide] {
      XCTAssertEqual(session.state, state)
      let before = speaker.spoken.count
      session.repeatGuidance()
      XCTAssertGreaterThan(speaker.spoken.count, before, "silent in \(state)")
    }
  }

  private func startWalkingFromOrient() {
    session.update(position: position(metersNorth: 55, seconds: 0), heading: heading(180, seconds: 0))
    session.update(position: position(metersNorth: 55, seconds: 2), heading: heading(180, seconds: 2))
  }

  // MARK: What the camera saw (CV-9 feeding FE-10)

  /// The rider is 55 m north of the door with a compass reading 15° too high. Geometry
  /// alone can't know that; the camera can, because the building is where the map says.
  private func sighting(
    text: String = "77", offsetFromTruth: Double, confidence: Double = 0.9,
    seconds: TimeInterval = 10
  ) -> BuildingSighting {
    let position = position(metersNorth: 55, seconds: seconds)
    let centre = bundle.buildingCenter!
    let trueBearing = Geo.bearingDegrees(
      lat1: position.latitude, lon1: position.longitude, lat2: centre.lat, lon2: centre.lon)
    return BuildingSighting(
      text: text, bearingDegrees: trueBearing + offsetFromTruth, confidence: confidence,
      timestamp: base.addingTimeInterval(seconds))
  }

  func testASightingWhereTheMapSaysCorrectsTheCompass() {
    startWalking()
    XCTAssertEqual(session.headingBiasDegrees, 0)

    // The camera reads "77" 15° to the right of where the building should be, which is
    // the compass being 15° out, not the building having moved.
    XCTAssertTrue(session.observe(sighting(offsetFromTruth: 15)))
    XCTAssertEqual(session.headingBiasDegrees, 7.5, accuracy: 0.01, "half of the error, damped")
    XCTAssertTrue(session.isBuildingConfirmed)
    XCTAssertTrue(
      speaker.spoken.contains { $0.contains("That looks like your building") },
      "said: \(speaker.spoken)")
    // Never a certainty word (SAFE-1).
    XCTAssertFalse(speaker.spoken.contains { $0.contains("That's your building") })

    // A second agreeing sighting converges further.
    session.observe(sighting(offsetFromTruth: 15, seconds: 12))
    XCTAssertGreaterThan(session.headingBiasDegrees, 7.5)
    XCTAssertLessThanOrEqual(session.headingBiasDegrees, 15.0)
  }

  func testTheCorrectionChangesWhereTheAppSteers() {
    startWalking()
    // Facing 195° while the door is due south: the app thinks the door is 15° to the
    // left, and would tell the rider to turn that way.
    session.update(position: position(metersNorth: 55, seconds: 8), heading: heading(195, seconds: 8))
    let before = session.offsetDegrees!
    XCTAssertEqual(before, -15, accuracy: 0.5)

    session.observe(sighting(offsetFromTruth: 15))
    session.update(position: position(metersNorth: 55, seconds: 14), heading: heading(195, seconds: 14))
    let after = session.offsetDegrees!
    // The same compass reading now steers closer to straight ahead, because the app has
    // learned that the compass itself reads high.
    XCTAssertLessThan(abs(after), abs(before))
    XCTAssertEqual(after, -7.5, accuracy: 0.5)
  }

  func testTheSameNumberOnTheWrongBuildingIsNotBelieved() {
    startWalking()
    // "77" read 60° away from where the building is: a sign on another building, or
    // across the road. It must not drag guidance sideways.
    XCTAssertFalse(session.observe(sighting(offsetFromTruth: 60)))
    XCTAssertEqual(session.headingBiasDegrees, 0)
    XCTAssertFalse(session.isBuildingConfirmed)
    XCTAssertTrue(
      speaker.spoken.contains(Phrases.buildingUncertain(text: "77")), "said: \(speaker.spoken)")
  }

  func testLowConfidenceSightingsAreIgnored() {
    startWalking()
    XCTAssertFalse(session.observe(sighting(offsetFromTruth: 10, confidence: 0.2)))
    XCTAssertEqual(session.headingBiasDegrees, 0)
  }

  func testTheCorrectionIsCapped() {
    startWalking()
    // A stream of sightings all claiming a large error can't spin the rider around.
    for i in 0..<20 {
      session.observe(sighting(offsetFromTruth: 24, seconds: 10 + Double(i)))
    }
    XCTAssertLessThanOrEqual(abs(session.headingBiasDegrees), 25.0)
  }

  func testANewWalkRelearnsTheCompassError() {
    startWalking()
    session.observe(sighting(offsetFromTruth: 15))
    XCTAssertNotEqual(session.headingBiasDegrees, 0)
    session.riderIsOutOfCar(isOnDoorSide: true)
    session.startGuidance()
    XCTAssertEqual(session.headingBiasDegrees, 0, "measured from somewhere else")
    XCTAssertFalse(session.isBuildingConfirmed)
  }

  func testASightingBuiltFromPixels() {
    // The same pinhole model the server uses on street photos (FE-2): compass 90°, the
    // text 700 px across a 1000 px frame, 60° field of view -> about 103°.
    let sighting = BuildingSighting(
      text: "77", headingDegrees: 90, xPixels: 700, widthPixels: 1000, fovDegrees: 60,
      confidence: 0.9)
    XCTAssertEqual(sighting.bearingDegrees, 103.0, accuracy: 0.05)
  }

  func testAnUnavailableCameraCheckIsSpoken() {
    startWalking()
    session.cameraCheckUnavailable(.lowLight)
    XCTAssertTrue(speaker.spoken.contains("Camera check unavailable in low light."))
  }

  func testNoHeadingMeansNoGuessAtDirection() {
    arriveAtCurb()
    session.startGuidance()
    // The compass is unusable (in a pocket, or uncalibrated). The state holds rather
    // than locking on to a direction the app can't actually measure.
    session.update(position: position(metersNorth: 55, seconds: 0), heading: nil)
    session.update(position: position(metersNorth: 55, seconds: 5), heading: nil)
    XCTAssertEqual(session.state, .orient)
    XCTAssertNil(session.offsetDegrees)
    XCTAssertNotNil(session.metersToDoor)
  }
}
