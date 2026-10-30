//  NavigationSessionSafetyTests.swift
//  nemo-softwareTests
//
//  The safety rules NavigationSession enforces, replayed against the real pilot bundles
//  in Resources/PilotBundles: road crossings and missing footways (SAFE-3, SAFE-4), GPS
//  too rough or too old to guide by (SAFE-9), the beacon held still in the world, where
//  it points while lost, and "I'm across" starting guidance.
//
//  Each test's comment says what break would make it fail. Positions are laid out in
//  meters north and east of the bundle's door, so "walking south" is a straight
//  approach on a bearing of 180°.
//

import CoreLocation
import XCTest

@testable import nemo_software

@MainActor
final class NavigationSessionSafetyTests: XCTestCase {

  private final class RecordingSpeaker: SpeechOutput {
    var spoken: [String] = []
    func speak(_ text: String) { spoken.append(text) }
    func stop() {}
  }

  /// Every event, spoken or not, so the silent `.beaconAim` can be checked.
  private final class RecordingChannel: FeedbackChannel {
    let name = "recording"
    var events: [FeedbackEvent] = []
    func play(_ event: FeedbackEvent) { events.append(event) }
    func stop() {}
  }

  private var speaker: RecordingSpeaker!
  private var recorder: RecordingChannel!
  private var session: NavigationSession!
  private var doorLat = 0.0
  private var doorLon = 0.0
  private let base = Date(timeIntervalSinceReferenceDate: 0)
  private let metersPerDegree = 111_194.93

  override func setUp() async throws {
    try await super.setUp()
    speaker = RecordingSpeaker()
    recorder = RecordingChannel()
    let channel = SpeechChannel(speaker: speaker)
    channel.repeatGuard = 0  // a whole walk replays in milliseconds
    session = NavigationSession(feedback: FeedbackKit(channels: [channel, recorder]))
  }

  // MARK: Fixtures

  /// A pilot bundle as the app ships it, optionally edited first (snake_case keys, as in
  /// the file) to build a case no pilot site has yet.
  private func pilotBundle(
    _ site: String, editing edit: ((inout [String: Any]) -> Void)? = nil
  ) throws -> ResolveResult {
    let url = try XCTUnwrap(
      Bundle.main.url(forResource: site, withExtension: "json"), "\(site) is not in the app")
    var data = try Data(contentsOf: url)
    if let edit {
      var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
      edit(&object)
      data = try JSONSerialization.data(withJSONObject: object)
    }
    return try JSONDecoder.entrance.decode(ResolveResult.self, from: data)
  }

  private func load(_ bundle: ResolveResult) throws {
    let door = try XCTUnwrap(bundle.candidates.first)
    doorLat = door.lat
    doorLon = door.lon
    session.setDestination(bundle, address: bundle.destinationId)
  }

  private func latitude(north: Double) -> Double { doorLat + north / metersPerDegree }

  private func longitude(east: Double) -> Double {
    doorLon + east / (metersPerDegree * cos(doorLat * .pi / 180))
  }

  private func position(
    north: Double, east: Double = 0, seconds: TimeInterval, accuracy: Double? = 5
  ) -> GuidancePosition {
    GuidancePosition(
      latitude: latitude(north: north), longitude: longitude(east: east),
      horizontalAccuracyMeters: accuracy, timestamp: base.addingTimeInterval(seconds))
  }

  private func heading(_ degrees: Double, seconds: TimeInterval, accuracy: Double = 10)
    -> HeadingReadout
  {
    HeadingReadout(
      trueHeadingDegrees: degrees, accuracyDegrees: accuracy,
      timestamp: base.addingTimeInterval(seconds))
  }

  private func step(
    north: Double, east: Double = 0, facing: Double, at seconds: TimeInterval,
    accuracy: Double? = 5
  ) {
    session.update(
      position: position(north: north, east: east, seconds: seconds, accuracy: accuracy),
      heading: heading(facing, seconds: seconds))
  }

  private func outOfTheCar(onDoorSide: Bool?) {
    session.startRiding()
    session.riderIsOutOfCar(isOnDoorSide: onDoorSide)
  }

  /// Out of the car on the door's side, facing the door from `north` meters away, and
  /// held long enough to lock on.
  private func startWalking(north: Double, east: Double = 0) {
    outOfTheCar(onDoorSide: true)
    session.startGuidance()
    step(north: north, east: east, facing: 180, at: 0)
    step(north: north, east: east, facing: 180, at: 2)
  }

  /// Walk south from 40 m to the door; the last fix has `finalAccuracy`.
  private func walkToTheDoor(finalAccuracy: Double) {
    startWalking(north: 40)
    XCTAssertEqual(session.state, .guide)
    step(north: 30, facing: 180, at: 10)
    step(north: 20, facing: 180, at: 20)
    step(north: 8, facing: 180, at: 30)
    XCTAssertEqual(session.state, .confirm)
    step(north: 2, facing: 180, at: 40, accuracy: finalAccuracy)
  }

  /// The beacon aims sent so far, nil meaning "go quiet".
  private var beaconAims: [Double?] {
    var aims: [Double?] = []
    for event in recorder.events {
      if case .beaconAim(let offset) = event { aims.append(offset) }
    }
    return aims
  }

  private var saidBearingLock: Bool {
    speaker.spoken.contains { $0.hasPrefix("That's the direction") }
  }

  // MARK: S1: path checks (SAFE-3, SAFE-4)

  /// Kresge: `crosses_road` true, no marked crossing, no footway, `partial`.
  /// Fails if `crosses_road` is ignored (guidance starts and the beacon points at the
  /// door across the road), if the "no safe path" line isn't spoken, or if "I'm across"
  /// doesn't clear the hold.
  func testKresgeCrossesARoadWithNoMarkedCrossingSoGuidanceWaitsToBeTold() throws {
    let bundle = try pilotBundle("mit-kresge-auditorium")
    // Pin the fixture, so a re-fetched bundle can't quietly make this test vacuous.
    XCTAssertTrue(bundle.pathChecks.crossesRoad)
    XCTAssertNil(bundle.pathChecks.nearestCrossing)
    XCTAssertFalse(bundle.pathChecks.footwayToEntrance)
    try load(bundle)

    outOfTheCar(onDoorSide: true)
    session.startGuidance()
    XCTAssertEqual(session.state, .arrival, "never guide across a road")
    XCTAssertTrue(session.isWaitingAtRoad)
    XCTAssertTrue(session.isWaitingToCross)
    XCTAssertFalse(session.canStartGuidance)
    XCTAssertNil(session.targetCoordinate, "nothing safe for the beacon to point at")
    XCTAssertTrue(speaker.spoken.contains(Phrases.noSafePathAcrossRoad), "said: \(speaker.spoken)")
    XCTAssertFalse(speaker.spoken.contains(Phrases.startingGuidance))

    // Positions while waiting move nothing and aim nothing.
    step(north: 40, facing: 180, at: 0)
    XCTAssertEqual(session.state, .arrival)
    XCTAssertTrue(beaconAims.allSatisfy { $0 == nil }, "aims: \(beaconAims)")

    // A second Start while waiting still says why, rather than nothing.
    let before = speaker.spoken.count
    session.startGuidance()
    XCTAssertGreaterThan(speaker.spoken.count, before)

    // The rider says they're across: now the door is the target.
    session.riderIsAcross()
    XCTAssertEqual(session.state, .orient)
    XCTAssertFalse(session.isWaitingAtRoad)
    XCTAssertEqual(session.targetCoordinate?.lat ?? 0, doorLat, accuracy: 1e-9)
    XCTAssertEqual(session.targetCoordinate?.lon ?? 0, doorLon, accuracy: 1e-9)
  }

  /// No pilot site has a marked crossing yet, so building 7 is edited to have one 20 m
  /// east of the door. Fails if the beacon aims at the door instead of the crossing (the
  /// rider faces the crossing, 22° off the door, so it never locks), if the bearing
  /// lock quotes the distance to the door, or if guidance walks on past the crossing
  /// instead of stopping there and waiting.
  func testAMarkedCrossingIsTheTargetUntilTheRiderSaysTheyAreAcross() throws {
    let plain = try pilotBundle("mit-building-7")
    let door = try XCTUnwrap(plain.candidates.first)
    let crossingLat = door.lat
    let crossingLon = door.lon + 20 / (metersPerDegree * cos(door.lat * .pi / 180))
    let bundle = try pilotBundle("mit-building-7") { json in
      json["path_checks"] = [
        "crosses_road": true, "nearest_crossing": [crossingLon, crossingLat],
        "footway_to_entrance": true,
      ]
    }
    try load(bundle)

    // Standing 50 m north of the crossing, facing it.
    startWalking(north: 50, east: 20)
    XCTAssertEqual(session.targetCoordinate?.lat ?? 0, crossingLat, accuracy: 1e-9)
    XCTAssertEqual(session.targetCoordinate?.lon ?? 0, crossingLon, accuracy: 1e-9)
    XCTAssertTrue(
      speaker.spoken.contains { $0.hasPrefix("The way to your entrance crosses a road.") },
      "said: \(speaker.spoken)")
    XCTAssertEqual(session.state, .guide, "locked on to the crossing")
    XCTAssertTrue(speaker.spoken.contains(Phrases.bearingLock(metersToDoor: nil)))
    XCTAssertFalse(speaker.spoken.contains { $0.contains("The door should be") })

    step(north: 40, east: 20, facing: 180, at: 10)
    step(north: 25, east: 20, facing: 180, at: 20)
    XCTAssertEqual(session.state, .guide)
    step(north: 8, east: 20, facing: 180, at: 30)
    // At the crossing: stop pointing, never say when it's safe, wait to be told.
    XCTAssertEqual(session.state, .arrival)
    XCTAssertTrue(session.isWaitingAtRoad)
    XCTAssertTrue(speaker.spoken.contains(Phrases.atCrossing))
    XCTAssertEqual(beaconAims.last, .some(nil), "the beacon goes quiet at the crossing")

    session.riderIsAcross()
    XCTAssertEqual(session.state, .orient)
    XCTAssertEqual(session.targetCoordinate?.lat ?? 0, doorLat, accuracy: 1e-9)
    XCTAssertEqual(session.targetCoordinate?.lon ?? 0, doorLon, accuracy: 1e-9)
  }

  /// Sloan is `partial` with `footway_to_entrance` false. Fails if the footway check is
  /// dropped from the bearing lock.
  func testSloanHasNoFootwayToTheDoorSoTheLockSaysThereIsNoSafePath() throws {
    let bundle = try pilotBundle("mit-sloan")
    XCTAssertFalse(bundle.pathChecks.footwayToEntrance)
    XCTAssertFalse(bundle.pathChecks.crossesRoad)
    try load(bundle)

    startWalking(north: 40)
    XCTAssertEqual(session.state, .guide)
    XCTAssertTrue(saidBearingLock)
    XCTAssertTrue(speaker.spoken.contains(Phrases.noSafePath), "said: \(speaker.spoken)")
  }

  /// The control for the test above. Fails if the footway check is inverted, or the
  /// warning is spoken for every bundle.
  func testBuilding7HasAFootwaySoTheLockDoesNotWarn() throws {
    let bundle = try pilotBundle("mit-building-7")
    XCTAssertTrue(bundle.pathChecks.footwayToEntrance)
    try load(bundle)

    startWalking(north: 40)
    XCTAssertEqual(session.state, .guide)
    XCTAssertFalse(speaker.spoken.contains(Phrases.noSafePath))
    XCTAssertFalse(speaker.spoken.contains(Phrases.noSafePathAcrossRoad))
  }

  /// Building 7's top candidate is a tagged main entrance; marked `partial`, the server
  /// is saying the result is weak. Fails if `status` is not read: a good fix at the
  /// door would then say "right in front of you" about a guess.
  func testAPartialBundleNeverPutsTheDoorRightInFrontOfTheRider() throws {
    let bundle = try pilotBundle("mit-building-7") { $0["status"] = "partial" }
    XCTAssertEqual(bundle.candidates.first?.band, "main")
    XCTAssertEqual(bundle.spokenBand, "facade")
    try load(bundle)

    walkToTheDoor(finalAccuracy: 3)
    XCTAssertEqual(session.state, .arrived)
    XCTAssertTrue(speaker.spoken.contains(Phrases.arrivedNearDoor), "said: \(speaker.spoken)")
    XCTAssertFalse(speaker.spoken.contains(Phrases.arrivedAtDoor))
  }

  // MARK: S2: GPS quality (SAFE-9)

  /// The control: a mapped door and a 3 m fix. Fails if arrival is never confident,
  /// which would make the two tests around it pass for the wrong reason.
  func testAGoodFixAtAMappedDoorSaysTheDoorIsInFront() throws {
    try load(pilotBundle("mit-building-7"))
    walkToTheDoor(finalAccuracy: 3)
    XCTAssertEqual(session.state, .arrived)
    XCTAssertTrue(speaker.spoken.contains(Phrases.arrivedAtDoor), "said: \(speaker.spoken)")
    XCTAssertFalse(speaker.spoken.contains(Phrases.arrivedNearDoor))
  }

  /// 2 m from the door by a 9 m fix: the door could be anywhere in that circle. Fails
  /// if `horizontalAccuracyMeters` is not checked at arrival.
  func testARoughFixAtTheDoorOnlySaysTheDoorIsClose() throws {
    try load(pilotBundle("mit-building-7"))
    walkToTheDoor(finalAccuracy: 9)
    XCTAssertEqual(session.state, .arrived)
    XCTAssertTrue(speaker.spoken.contains(Phrases.arrivedNearDoor), "said: \(speaker.spoken)")
    XCTAssertFalse(speaker.spoken.contains(Phrases.arrivedAtDoor))
  }

  /// Fails if accuracy is ignored while walking, if a bad fix still advances the state
  /// (here, into .confirm), if the pause is repeated on every update, or if the 12 m
  /// resume threshold is dropped (14 m would resume and the state would flap).
  func testARoughFixPausesGuidanceOutLoudAndResumesOnlyWhenItIsGood() throws {
    try load(pilotBundle("mit-building-7"))
    startWalking(north: 40)
    step(north: 30, facing: 180, at: 10)
    recorder.events = []

    step(north: 25, facing: 180, at: 12, accuracy: 20)
    XCTAssertTrue(speaker.spoken.contains(Phrases.positionUncertain), "said: \(speaker.spoken)")
    XCTAssertEqual(session.state, .guide)
    XCTAssertNil(session.offsetDegrees, "no direction from a guess")
    XCTAssertEqual(beaconAims.last, .some(nil), "the beacon goes quiet")

    // Inside the confirm radius by a bad fix: nothing advances.
    step(north: 5, facing: 180, at: 14, accuracy: 30)
    XCTAssertEqual(session.state, .guide)
    // Better, but not back under 12 m.
    step(north: 24, facing: 180, at: 16, accuracy: 14)
    XCTAssertFalse(speaker.spoken.contains(Phrases.guidanceResumed))
    XCTAssertEqual(speaker.spoken.filter { $0 == Phrases.positionUncertain }.count, 1)

    step(north: 23, facing: 180, at: 18, accuracy: 6)
    XCTAssertTrue(speaker.spoken.contains(Phrases.guidanceResumed))
    XCTAssertNotNil(session.offsetDegrees)
    XCTAssertNotNil(beaconAims.last.flatMap { $0 }, "the beacon comes back")
  }

  /// A fix that stopped updating while the compass keeps going: the position is 6 s
  /// older than the heading. Fails if staleness isn't measured against the heading's
  /// time, or the age check is removed.
  func testAFixThatStoppedUpdatingPausesGuidance() throws {
    try load(pilotBundle("mit-building-7"))
    startWalking(north: 40)
    session.update(
      position: position(north: 30, seconds: 4), heading: heading(180, seconds: 10))
    XCTAssertTrue(speaker.spoken.contains(Phrases.positionUncertain), "said: \(speaker.spoken)")
    XCTAssertEqual(session.state, .guide)

    step(north: 29, facing: 180, at: 11)
    XCTAssertTrue(speaker.spoken.contains(Phrases.guidanceResumed))
  }

  /// Fails if the anchor and bearing lock can come from a 25 m fix.
  func testNoLockAndNoAnchorFromARoughFix() throws {
    try load(pilotBundle("mit-building-7"))
    outOfTheCar(onDoorSide: true)
    session.startGuidance()
    for seconds in [0.0, 2, 4] {
      step(north: 40, facing: 180, at: seconds, accuracy: 25)
    }
    XCTAssertEqual(session.state, .orient)
    XCTAssertFalse(saidBearingLock)
    XCTAssertTrue(speaker.spoken.contains(Phrases.positionUncertain))
  }

  /// Fails if compass accuracy isn't checked before the 15° lock.
  func testNoLockFromARoughCompass() throws {
    try load(pilotBundle("mit-building-7"))
    outOfTheCar(onDoorSide: true)
    session.startGuidance()
    for seconds in [0.0, 2, 4] {
      session.update(
        position: position(north: 40, seconds: seconds),
        heading: heading(180, seconds: seconds, accuracy: 35))
    }
    XCTAssertEqual(session.state, .orient)
    XCTAssertFalse(saidBearingLock)
    XCTAssertTrue(speaker.spoken.contains(Phrases.compassCalibration))
  }

  /// The walk screen builds the session's positions from LocationService. Fails if the
  /// GPS accuracy is dropped on the way, which would make every check above dead code
  /// on a phone.
  func testTheWalkScreenPassesGPSAccuracyToTheSession() throws {
    try load(pilotBundle("mit-building-7"))
    let location = LocationService(locationManager: CLLocationManager())
    let walk = GuidanceViewModel(session: session, location: location)
    outOfTheCar(onDoorSide: true)
    session.startGuidance()

    let rough = CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: latitude(north: 40), longitude: doorLon),
      altitude: 0, horizontalAccuracy: 40, verticalAccuracy: 5, timestamp: Date())
    location.locationManager(CLLocationManager(), didUpdateLocations: [rough])
    XCTAssertTrue(speaker.spoken.contains(Phrases.positionUncertain), "said: \(speaker.spoken)")
    withExtendedLifetime(walk) {}
  }

  /// CLHeading has no public initializer; overriding its properties is the usual way
  /// to make one in a test.
  private final class FakeHeading: CLHeading {
    override var trueHeading: CLLocationDirection { 180 }
    override var magneticHeading: CLLocationDirection { 180 }
    override var headingAccuracy: CLLocationDirection { 10 }
    override var timestamp: Date { Date() }
  }

  /// Fails if a heading update overwrites the snapshot's timestamp with its own, which
  /// makes a 30 s old fix look current to the staleness check.
  func testAHeadingUpdateDoesNotMakeAnOldFixLookFresh() {
    let location = LocationService(locationManager: CLLocationManager())
    let fixTime = Date().addingTimeInterval(-30)
    let fix = CLLocation(
      coordinate: CLLocationCoordinate2D(latitude: 42.3591, longitude: -71.0933),
      altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: fixTime)
    location.locationManager(CLLocationManager(), didUpdateLocations: [fix])
    location.locationManager(CLLocationManager(), didUpdateHeading: FakeHeading())

    XCTAssertNotNil(location.currentSnapshot.headingReadout, "the heading was taken")
    XCTAssertEqual(
      location.currentSnapshot.timestamp.timeIntervalSinceReferenceDate,
      fixTime.timeIntervalSinceReferenceDate, accuracy: 0.001)
  }

  // MARK: S3: the beacon stays put in the world

  /// Standing still and turning: the door stays south, so its angle has to follow the
  /// heading. Fails if `.beaconAim` is only sent in orient (or only when far off), or
  /// if the angle isn't worked out again from each new heading.
  func testTheBeaconIsAimedOnEveryWalkingUpdate() throws {
    try load(pilotBundle("mit-building-7"))
    startWalking(north: 40)
    XCTAssertEqual(session.state, .guide)
    recorder.events = []

    step(north: 35, facing: 180, at: 6)
    step(north: 35, facing: 270, at: 7)
    step(north: 35, facing: 90, at: 8)
    XCTAssertEqual(session.state, .guide)
    let aims = beaconAims
    XCTAssertEqual(aims.count, 3, "aims: \(aims)")
    XCTAssertEqual(aims[0] ?? 999, 0, accuracy: 1)
    XCTAssertEqual(aims[1] ?? 999, -90, accuracy: 1, "facing west, the door is to the left")
    XCTAssertEqual(aims[2] ?? 999, 90, accuracy: 1, "facing east, the door is to the right")
  }

  // MARK: S4: where the beacon points while lost

  /// Breadcrumbs every 5 m from 55 m to 30 m, then lost at 28 m. Fails if the lost aim
  /// is the newest crumb (30 m, about where the rider is), the anchor (55 m), or the
  /// door, or if the beacon is silent while lost.
  func testWhileLostTheBeaconAimsAtACrumbAtLeast10MetersBack() throws {
    try load(pilotBundle("mit-building-7"))
    startWalking(north: 55)
    for (north, seconds) in [(50.0, 4.0), (45, 6), (40, 8), (35, 10), (30, 12)] {
      step(north: north, facing: 180, at: seconds)
    }
    step(north: 29, facing: 300, at: 13)
    step(north: 28, facing: 300, at: 19)
    XCTAssertEqual(session.state, .lost)
    XCTAssertTrue(speaker.spoken.contains(Phrases.offRoute))

    let aim = try XCTUnwrap(session.targetCoordinate)
    XCTAssertEqual(aim.lat, latitude(north: 40), accuracy: 1e-7, "the crumb 12 m back")
    XCTAssertEqual(aim.lon, doorLon, accuracy: 1e-7)
    let here = position(north: 28, seconds: 19)
    XCTAssertGreaterThanOrEqual(
      Geo.distanceMeters(
        lat1: here.latitude, lon1: here.longitude, lat2: aim.lat, lon2: aim.lon), 10)

    // Facing 300° with the crumb due north: the tone is 60° to the right, not at the
    // door 120° to the left.
    recorder.events = []
    step(north: 28, facing: 300, at: 20)
    XCTAssertEqual(beaconAims.last.flatMap { $0 } ?? 999, 60, accuracy: 1)
  }

  // MARK: S5: across the street, then guidance

  /// Fails if "I'm across" doesn't move the rider to the door's side and start
  /// guidance, which before S5 left them waiting with no way out.
  func testAcrossTheStreetThenImAcrossStartsGuidance() throws {
    try load(pilotBundle("mit-building-7"))
    outOfTheCar(onDoorSide: false)
    session.startGuidance()
    XCTAssertEqual(session.state, .arrival)
    XCTAssertTrue(session.isWaitingToCross)
    XCTAssertTrue(speaker.spoken.contains(Phrases.waitingToCrossStreet))

    session.riderIsAcross()
    XCTAssertEqual(session.riderIsOnDoorSide, true)
    XCTAssertFalse(session.isWaitingToCross)
    XCTAssertEqual(session.state, .orient)
    XCTAssertTrue(speaker.spoken.contains(Phrases.startingGuidance))
    step(north: 40, facing: 180, at: 0)
    step(north: 40, facing: 180, at: 2)
    XCTAssertEqual(session.state, .guide)
  }

  /// From the ride screen, which feeds no positions. Fails if it starts the walk there
  /// ("Starting" and then silence) or says nothing at all.
  func testImAcrossFromTheRideScreenSaysWhereToStart() throws {
    try load(pilotBundle("mit-building-7"))
    outOfTheCar(onDoorSide: false)
    session.riderIsAcross(startGuiding: false)
    XCTAssertEqual(session.state, .arrival)
    XCTAssertTrue(session.canStartGuidance)
    XCTAssertTrue(speaker.spoken.contains(Phrases.readyToStartGuidance))
    XCTAssertFalse(speaker.spoken.contains(Phrases.startingGuidance))
  }

  /// Fails if "I'm across" with an unknown side assumes the door's side.
  func testImAcrossWithAnUnknownSideAsksInsteadOfAssuming() throws {
    try load(pilotBundle("mit-building-7"))
    outOfTheCar(onDoorSide: nil)
    session.riderIsAcross()
    XCTAssertNil(session.riderIsOnDoorSide)
    XCTAssertEqual(session.state, .arrival)
    XCTAssertTrue(
      speaker.spoken.contains { $0.hasSuffix(Phrases.askSideOfStreet) }, "said: \(speaker.spoken)")
  }
}
