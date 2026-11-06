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

  private func bundleWithRoute(_ route: [[Double]]) -> ResolveResult {
    ResolveResult(
      destinationId: bundle.destinationId,
      status: bundle.status,
      building: bundle.building,
      candidates: bundle.candidates,
      pathChecks: bundle.pathChecks,
      streetSide: bundle.streetSide,
      recognize: bundle.recognize,
      landmarks: bundle.landmarks,
      route: route,
      attribution: bundle.attribution,
      dataVersion: bundle.dataVersion)
  }

  private func routePoint(north: Double, east: Double) -> [Double] {
    let metersPerDegree = 111_194.93
    return [
      doorLon + east / (metersPerDegree * cos(doorLat * .pi / 180)),
      doorLat + north / metersPerDegree
    ]
  }

  /// An L-shaped route: east along the sidewalk, then south-west to the door.
  private var testRoute: [[Double]] {
    [
      routePoint(north: 50, east: 0),
      routePoint(north: 50, east: 20),
      routePoint(north: 0, east: 0)
    ]
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

    // Inside 15 m: the door facts from the bundle, and the door finder starts.
    session.update(position: position(metersNorth: 8, seconds: 30), heading: heading(180, seconds: 30))
    XCTAssertEqual(session.state, .confirm)
    XCTAssertTrue(
      speaker.spoken.contains { $0.contains("3 steps and a push-button door") },
      "said: \(speaker.spoken)")
    XCTAssertTrue(speaker.spoken.contains { $0.contains(Phrases.holdPhoneUp) })

    // GPS at the door only says it should be close: GPS can't place a door.
    session.update(position: position(metersNorth: 2, seconds: 40), heading: heading(180, seconds: 40))
    XCTAssertEqual(session.state, .confirm)
    XCTAssertTrue(speaker.spoken.contains(Phrases.doorShouldBeClose))

    // The rider finds it. Never "you have arrived" (SAFE-1).
    session.riderIsAtDoor()
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
    // Walked a bit, then turned 120° off and wandered, no longer getting closer.
    session.update(position: position(metersNorth: 45, seconds: 10), heading: heading(180, seconds: 10))
    session.update(position: position(metersNorth: 40, seconds: 14), heading: heading(300, seconds: 14))
    XCTAssertEqual(session.state, .guide, "being off course briefly is not lost")
    session.update(position: position(metersNorth: 39, seconds: 17), heading: heading(300, seconds: 17))
    session.update(position: position(metersNorth: 38, seconds: 20), heading: heading(300, seconds: 20))
    session.update(position: position(metersNorth: 38, seconds: 24), heading: heading(300, seconds: 24))
    session.update(position: position(metersNorth: 38, seconds: 30), heading: heading(300, seconds: 30))
    XCTAssertEqual(session.state, .lost)
    XCTAssertTrue(speaker.spoken.contains(Phrases.offRoute))

    // While lost the target is the last breadcrumb, not the door: somewhere the rider
    // has actually stood.
    let crumb = session.targetCoordinate
    XCTAssertNotNil(crumb)
    XCTAssertNotEqual(crumb?.lat, doorLat)

    // Turning back towards it for 2 s re-anchors and returns to orienting.
    let bearingToCrumb = Geo.bearingDegrees(
      lat1: position(metersNorth: 38, seconds: 0).latitude,
      lon1: position(metersNorth: 38, seconds: 0).longitude,
      lat2: crumb!.lat, lon2: crumb!.lon)
    session.update(
      position: position(metersNorth: 38, seconds: 34),
      heading: heading(bearingToCrumb, seconds: 34))
    XCTAssertEqual(session.state, .lost, "recovery is held for a moment too")
    session.update(
      position: position(metersNorth: 38, seconds: 37),
      heading: heading(bearingToCrumb, seconds: 37))
    XCTAssertEqual(session.state, .orient)
  }

  func testTheFirstStepsCheckCatchesAWrongStart() {
    startWalking()
    // Twelve meters east instead of south (well past the ±5 m GPS error): no closer to
    // the door, so the anchor was probably wrong. The app says it isn't sure rather than
    // confidently guiding the wrong way.
    session.update(
      position: position(metersNorth: 55, seconds: 10, metersEast: 12),
      heading: heading(180, seconds: 10))
    XCTAssertEqual(session.state, .lost)
    XCTAssertTrue(speaker.spoken.contains(Phrases.directionUncertain))
  }

  /// The bug from the first street test: the door is round the corner, so the straight
  /// line to it cuts through the building. Walking straight along the sidewalk looks up
  /// to ~70° "off", but the rider gets closer the whole way and must never hear
  /// "off route" or be sent back to a breadcrumb behind them.
  func testWalkingAlongTheSidewalkToADoorRoundTheCornerIsNotLost() {
    arriveAtCurb()
    session.startGuidance()
    // 30 m east of the door's line, 80 m north. Face the door to lock on.
    let lockBearing = Geo.bearingDegrees(
      lat1: position(metersNorth: 80, seconds: 0, metersEast: 30).latitude,
      lon1: position(metersNorth: 80, seconds: 0, metersEast: 30).longitude,
      lat2: doorLat, lon2: doorLon)
    session.update(
      position: position(metersNorth: 80, seconds: 0, metersEast: 30),
      heading: heading(lockBearing, seconds: 0))
    session.update(
      position: position(metersNorth: 80, seconds: 2, metersEast: 30),
      heading: heading(lockBearing, seconds: 2))
    XCTAssertEqual(session.state, .guide)

    // Then walk due south along the sidewalk at a normal pace, 2.5 m every 2 s.
    var north = 80.0
    var seconds = 2.0
    while north > 12 {
      north -= 2.5
      seconds += 2
      session.update(
        position: position(metersNorth: north, seconds: seconds, metersEast: 30),
        heading: heading(180, seconds: seconds))
      XCTAssertEqual(session.state, .guide, "at \(north) m north: \(session.lastLostReason ?? "")")
    }
    XCTAssertGreaterThan(abs(session.offsetDegrees ?? 0), 60, "the angle really was large")
    XCTAssertFalse(speaker.spoken.contains(Phrases.offRoute))
    XCTAssertFalse(speaker.spoken.contains(Phrases.directionUncertain))
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

  // MARK: Side of street unknown: never ask the rider to work it out

  /// The sample bundle's centerline runs north–south about 15 m east of the door, so
  /// `metersEast: 0` is on the door's side and `metersEast: 25` is across the road.
  private func startWithUnknownSide() {
    session.startRiding()
    session.riderIsOutOfCar(isOnDoorSide: nil)
    XCTAssertTrue(session.canStartGuidance, "an unknown side doesn't block the walk")
    session.startGuidance()
  }

  func testAnUnknownSideStartsGuidanceWithoutQuestioningTheRider() {
    startWithUnknownSide()
    XCTAssertEqual(session.state, .orient)
    XCTAssertTrue(session.sideUnconfirmed)
    XCTAssertFalse(speaker.spoken.contains { $0.contains("?") }, "said: \(speaker.spoken)")
  }

  func testAnUnknownSideNeverPointsAcrossTheStreet() {
    startWithUnknownSide()
    speaker.spoken = []
    session.update(
      position: position(metersNorth: 30, seconds: 1, metersEast: 25),
      heading: heading(90, seconds: 1))
    XCTAssertNil(session.offsetDegrees, "no direction toward a door across the road")
    XCTAssertEqual(session.state, .orient)
    XCTAssertTrue(session.sideUnconfirmed)
    XCTAssertEqual(speaker.spoken, [Phrases.askSideOfStreet(
      entranceStreet: bundle.streetSide?.entranceStreet,
      streetSideDescription: bundle.streetSide.flatMap(StreetSideDescription.compassSide))])
  }

  func testAnUnknownSideIsWorkedOutFromGPSOnTheDoorSide() {
    startWithUnknownSide()
    session.update(
      position: position(metersNorth: 30, seconds: 1), heading: heading(180, seconds: 1))
    XCTAssertFalse(session.sideUnconfirmed)
    XCTAssertEqual(session.riderIsOnDoorSide, true)
    XCTAssertNotNil(session.offsetDegrees)
    XCTAssertTrue(
      speaker.spoken.contains { $0.hasPrefix("Your entrance should be on this side") },
      "said: \(speaker.spoken)")
  }

  func testAPoorFixNearTheStreetDoesNotDecideTheSide() {
    startWithUnknownSide()
    // On the door's side by GPS, but the fix is 20 m either way: not trusted.
    let fuzzy = GuidancePosition(
      latitude: doorLat + 30 / 111_194.93, longitude: doorLon,
      horizontalAccuracyMeters: 20, timestamp: base.addingTimeInterval(1))
    session.update(position: fuzzy, heading: heading(180, seconds: 1))
    XCTAssertTrue(session.sideUnconfirmed)
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
    // No car track survived the relaunch, so the side is unknown. It says so, but the
    // walk isn't blocked on the rider working it out.
    XCTAssertNil(resumed.riderIsOnDoorSide)
    XCTAssertTrue(resumed.canStartGuidance)
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

  // MARK: The door finder (camera, last stretch)

  private func walkToTheLastStretch() {
    startWalking()
    session.update(position: position(metersNorth: 33, seconds: 10), heading: heading(180, seconds: 10))
    session.update(position: position(metersNorth: 17, seconds: 20), heading: heading(180, seconds: 20))
    session.update(position: position(metersNorth: 8, seconds: 30), heading: heading(180, seconds: 30))
    XCTAssertEqual(session.state, .confirm)
  }

  private func door(offset: Double, meters: Double?, seconds: TimeInterval) -> DoorSighting {
    DoorSighting(
      kind: .door, offsetDegrees: offset, meters: meters, confidence: 1,
      timestamp: base.addingTimeInterval(seconds))
  }

  func testDoorSightingsWaitForTheLastStretch() {
    startWalking()
    XCTAssertFalse(session.observeDoor(door(offset: 20, meters: 5, seconds: 5)))
    XCTAssertFalse(speaker.spoken.contains { $0.hasPrefix("Door") })
  }

  func testADoorIsSpokenOnceThenOnlyMovesTheBeacon() {
    walkToTheLastStretch()
    speaker.spoken = []
    session.observeDoor(door(offset: 30, meters: 4, seconds: 31))
    XCTAssertEqual(speaker.spoken, ["Door, slightly right, about 15 feet."])
    // Seen again moments later and further round: no new words.
    session.observeDoor(door(offset: 25, meters: 3.8, seconds: 32))
    session.observeDoor(door(offset: 20, meters: 3.6, seconds: 33))
    XCTAssertEqual(speaker.spoken.count, 1, "said: \(speaker.spoken)")
  }

  func testTurningToFaceTheDoorIsSaid() {
    walkToTheLastStretch()
    session.observeDoor(door(offset: 40, meters: 4, seconds: 31))
    speaker.spoken = []
    session.observeDoor(door(offset: 5, meters: 3, seconds: 32))
    XCTAssertEqual(speaker.spoken, ["Door straight ahead, about 10 feet."])
    // Still facing it: said once, not on every frame.
    session.observeDoor(door(offset: 3, meters: 2.8, seconds: 33))
    XCTAssertEqual(speaker.spoken.count, 1)
  }

  func testADoorWithinReachEndsTheWalk() {
    walkToTheLastStretch()
    session.observeDoor(door(offset: 8, meters: 1, seconds: 31))
    XCTAssertEqual(session.state, .arrived)
    XCTAssertTrue(speaker.spoken.contains(Phrases.arrivedAtDoor))
    XCTAssertNil(store.load())
  }

  func testADoorWithinReachButOffToTheSideDoesNotEndTheWalk() {
    walkToTheLastStretch()
    session.observeDoor(door(offset: 60, meters: 1, seconds: 31))
    XCTAssertEqual(session.state, .confirm)
  }

  func testAnEntranceSignIsSpokenAsAClueNotAsTheDoor() {
    walkToTheLastStretch()
    speaker.spoken = []
    session.observeDoor(
      DoorSighting(
        kind: .clue(.entranceSign(.entrance)), offsetDegrees: -20, confidence: 0.8,
        timestamp: base.addingTimeInterval(31)))
    XCTAssertEqual(speaker.spoken, ["I can see an entrance sign slightly left."])
    XCTAssertEqual(session.state, .confirm, "a sign never ends the walk on its own")
  }

  func testWhereAmINearTheDoorRepeatsWhatTheCameraSees() {
    walkToTheLastStretch()
    session.observeDoor(
      DoorSighting(kind: .clue(.buildingText("77")), offsetDegrees: 0, confidence: 0.9))
    speaker.spoken = []
    session.repeatGuidance()
    XCTAssertEqual(speaker.spoken, ["I can see 77 straight ahead."])
  }

  func testTheBuildingNumberIsAnnouncedOnceNotOnEveryRead() {
    startWalking()
    session.observe(sighting(offsetFromTruth: 5, seconds: 3))
    session.observe(sighting(offsetFromTruth: 5, seconds: 7))
    session.observe(sighting(offsetFromTruth: 5, seconds: 11))
    XCTAssertEqual(
      speaker.spoken.filter { $0.contains("That looks like your building") }.count, 1,
      "said: \(speaker.spoken)")
  }

  func testTheRiderCanEndTheWalkAtTheDoor() {
    startWalking()
    session.riderIsAtDoor()
    XCTAssertEqual(session.state, .arrived)
    XCTAssertTrue(speaker.spoken.contains(Phrases.arrivedAtDoor))
  }

  // MARK: Route following

  func testBlockedRouteDirectionChoosesTheClosestClearSlice() {
    startWalking()
    session.update(
      position: position(metersNorth: 45, seconds: 5),
      heading: heading(180, seconds: 5))
    speaker.spoken = []

    session.observeFreeSpace(
      FreeSpace(
        slices: [
          FreeSpace.Slice(offsetDegrees: 0, status: .blocked(meters: 0.5)),
          FreeSpace.Slice(offsetDegrees: 15, status: .clear),
          FreeSpace.Slice(offsetDegrees: -35, status: .clear)
        ]))

    // The route target stays straight ahead; the separate steering cue chooses the
    // nearest clear slice around the obstruction.
    XCTAssertEqual(session.offsetDegrees ?? 999, 0, accuracy: 0.001)
    XCTAssertTrue(
      speaker.spoken.contains(
        Phrases.steerAround(
          kind: .object, hazardOffsetDegrees: 0, clearOffsetDegrees: 15, meters: 0.5)),
      "said: \(speaker.spoken)")
  }

  func testNoClearSliceProducesAStopCue() {
    startWalking()
    session.update(
      position: position(metersNorth: 45, seconds: 5),
      heading: heading(180, seconds: 5))
    speaker.spoken = []

    session.observeFreeSpace(
      FreeSpace(
        slices: [
          FreeSpace.Slice(offsetDegrees: 0, status: .blocked(meters: 0.5)),
          FreeSpace.Slice(offsetDegrees: 25, status: .blocked(meters: 1))
        ]))

    XCTAssertEqual(session.offsetDegrees ?? 999, 0, accuracy: 0.001)
    XCTAssertTrue(speaker.spoken.contains(Phrases.pathBlocked))
  }

  func testFollowingAWalkRouteDoesNotBecomeLost() {
    session.setDestination(bundleWithRoute(testRoute), address: address)
    session.thresholds.lostAfterSeconds = 1

    arriveAtCurb()
    session.startGuidance()

    session.update(
      position: position(metersNorth: 50, seconds: 0),
      heading: heading(90, seconds: 0))
    session.update(
      position: position(metersNorth: 50, seconds: 2),
      heading: heading(90, seconds: 2))
    XCTAssertEqual(session.state, .guide)

    session.update(
      position: position(metersNorth: 50, seconds: 5, metersEast: 10),
      heading: heading(90, seconds: 5))
    session.update(
      position: position(metersNorth: 45, seconds: 10, metersEast: 20),
      heading: heading(160, seconds: 10))

    XCTAssertEqual(session.state, .guide)
    XCTAssertFalse(speaker.spoken.contains(Phrases.offRoute))
  }

  func testTheFirstStepsCheckCatchesWalkingTheWrongWayFromARoute() {
    session.setDestination(bundleWithRoute(testRoute), address: address)

    arriveAtCurb()
    session.startGuidance()

    session.update(
      position: position(metersNorth: 50, seconds: 0),
      heading: heading(90, seconds: 0))
    session.update(
      position: position(metersNorth: 50, seconds: 2),
      heading: heading(90, seconds: 2))
    XCTAssertEqual(session.state, .guide)

    // The route starts east; the rider heads west.
    session.update(
      position: position(metersNorth: 50, seconds: 5, metersEast: -12),
      heading: heading(90, seconds: 5))

    XCTAssertEqual(session.state, .lost)
    XCTAssertTrue(speaker.spoken.contains(Phrases.directionUncertain))
  }

  func testLeavingTheRouteBecomesLost() {
    session.setDestination(bundleWithRoute(testRoute), address: address)
    session.thresholds.lostAfterSeconds = 1
    session.thresholds.routeOffRouteMeters = 8

    arriveAtCurb()
    session.startGuidance()

    session.update(
      position: position(metersNorth: 50, seconds: 0),
      heading: heading(90, seconds: 0))
    session.update(
      position: position(metersNorth: 50, seconds: 2),
      heading: heading(90, seconds: 2))

    session.update(
      position: position(metersNorth: 50, seconds: 4, metersEast: -20),
      heading: heading(90, seconds: 4))
    session.update(
      position: position(metersNorth: 50, seconds: 6, metersEast: -20),
      heading: heading(90, seconds: 6))

    XCTAssertEqual(session.state, .lost)
  }

  func testReturningToTheRouteRecoversFromLost() {
    session.setDestination(bundleWithRoute(testRoute), address: address)
    session.thresholds.lostAfterSeconds = 1
    session.thresholds.routeOffRouteMeters = 8
    session.thresholds.recoverHoldSeconds = 1

    arriveAtCurb()
    session.startGuidance()

    session.update(
      position: position(metersNorth: 50, seconds: 0),
      heading: heading(90, seconds: 0))
    session.update(
      position: position(metersNorth: 50, seconds: 2),
      heading: heading(90, seconds: 2))
    session.update(
      position: position(metersNorth: 50, seconds: 5, metersEast: -20),
      heading: heading(90, seconds: 5))
    XCTAssertEqual(session.state, .lost)

    session.update(
      position: position(metersNorth: 50, seconds: 7, metersEast: 2),
      heading: heading(90, seconds: 7))
    session.update(
      position: position(metersNorth: 50, seconds: 9, metersEast: 2),
      heading: heading(90, seconds: 9))
    XCTAssertEqual(session.state, .orient)
  }
}
