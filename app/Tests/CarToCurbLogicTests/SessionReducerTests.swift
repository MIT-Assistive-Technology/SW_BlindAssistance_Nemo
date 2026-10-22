import XCTest

@testable import CarToCurbLogic

/// Replays drop-offs at the contract example: the centerline runs south along lon -71.0928
/// and the door (c1, 42.35921 / -71.09298) is on its right, i.e. the west sidewalk.
final class SessionReducerTests: XCTestCase {
  static let door = (lat: 42.35921, lon: -71.09298)
  /// West sidewalk, ~33.5 m north of the door.
  static let westStart = (lat: 42.3595, lon: -71.09287)
  /// East sidewalk, across the street.
  static let eastStart = (lat: 42.3595, lon: -71.09273)
  static let buildingCentroid = (lat: 42.35925, lon: -71.0931)

  /// Drives a reducer with a simulated clock and records every effect.
  struct Trip {
    var reducer = SessionReducer()
    var now = Date(timeIntervalSince1970: 1_000_000)
    var log: [SessionEffect] = []

    @discardableResult
    mutating func send(_ input: SessionInput) -> [SessionEffect] {
      let effects = reducer.handle(input)
      log += effects
      return effects
    }

    /// Car drives `course` at 8 m/s for 12 s, then stops and the rider walks off.
    mutating func ride(course: Double) throws {
      send(.bundleLoaded(try Fixtures.example()))
      for _ in 0..<12 {
        send(.carCourse(degrees: course, speed: 8, accuracy: 5, at: now))
        now += 1
      }
      send(.carStopped(at: now))
      now += 5
      send(.walkingDetected)
    }

    @discardableResult
    mutating func pose(_ lat: Double, _ lon: Double, heading: Double) -> [SessionEffect] {
      defer { now += 1 }
      return send(.pose(lat: lat, lon: lon, headingDegrees: heading, accuracyMeters: 5, at: now))
    }

    /// Pose facing the current target.
    @discardableResult
    mutating func poseFacingTarget(_ lat: Double, _ lon: Double) -> [SessionEffect] {
      let t = reducer.target!
      return pose(lat, lon, heading: Geo.bearingDegrees(lat1: lat, lon1: lon, lat2: t.lat, lon2: t.lon))
    }

    /// Same-side ride, start tapped, rider locked on to the door at the west start.
    static func lockedOn() throws -> Trip {
      var trip = Trip()
      try trip.ride(course: 180)
      trip.send(.startTapped)
      trip.poseFacingTarget(westStart.lat, westStart.lon)
      trip.poseFacingTarget(westStart.lat, westStart.lon)
      XCTAssertEqual(trip.reducer.state, .guide)
      return trip
    }

    var said: [FeedbackEvent] {
      log.compactMap { if case .say(let e) = $0 { return e } else { return nil } }
    }
  }

  static func point(from start: (lat: Double, lon: Double), bearing: Double, meters: Double)
    -> (lat: Double, lon: Double)
  {
    let frame = LocalFrame(originLat: start.lat, originLon: start.lon)
    let b = bearing * .pi / 180
    return frame.toGeo(east: sin(b) * meters, north: cos(b) * meters)
  }

  static var doorBearingFromWest: Double {
    Geo.bearingDegrees(lat1: westStart.lat, lon1: westStart.lon, lat2: door.lat, lon2: door.lon)
  }

  // MARK: - Scenarios

  func testSameSideFullTripToArrival() throws {
    var trip = Trip()
    try trip.ride(course: 180)
    XCTAssertEqual(trip.reducer.state, .arrival)
    XCTAssertEqual(trip.reducer.sameSide, true)
    XCTAssertEqual(trip.said, [.exitCurbSide], "curb-side prompt comes before anything else")
    XCTAssertEqual(trip.reducer.target?.id, "c1")

    let start = trip.send(.startTapped)
    XCTAssertEqual(start, [.startARTracking, .startCamera, .persist])
    XCTAssertEqual(trip.reducer.state, .orient)

    // Facing away first: the brief, then a direction cue toward the door.
    let first = trip.pose(Self.westStart.lat, Self.westStart.lon, heading: 90)
    guard case .say(.brief(let same, let meters, let offset))? = first.first else {
      return XCTFail("expected the brief, got \(first)")
    }
    XCTAssertEqual(same, true)
    XCTAssertEqual(meters, 33.5, accuracy: 1.5)
    XCTAssertEqual(offset, Self.doorBearingFromWest - 90, accuracy: 0.5, "door is behind-right")
    XCTAssertEqual(
      Phrases.text(for: first[0].event!, verbosity: .normal, units: .feet)?
        .hasPrefix("Your entrance should be on this side of the street, about 110 feet"), true)
    trip.now += 2
    let cueEffects = trip.pose(Self.westStart.lat, Self.westStart.lon, heading: 90)
    XCTAssertTrue(cueEffects.contains { if case .say(.direction) = $0 { return true }; return false })

    // Building check from the start: "77" seen toward the building.
    trip.poseFacingTarget(Self.westStart.lat, Self.westStart.lon)
    let towardBuilding = Geo.bearingDegrees(
      lat1: Self.westStart.lat, lon1: Self.westStart.lon,
      lat2: Self.buildingCentroid.lat, lon2: Self.buildingCentroid.lon)
    XCTAssertEqual(
      trip.send(.textSeen("77", bearingDegrees: towardBuilding)),
      [.say(.buildingConfirmed(text: "77"))])

    let lock = trip.poseFacingTarget(Self.westStart.lat, Self.westStart.lon)
    XCTAssertTrue(lock.contains(.say(.bearingLock)))
    XCTAssertTrue(lock.contains(.saveBreadcrumb(lat: Self.westStart.lat, lon: Self.westStart.lon)))
    XCTAssertEqual(trip.reducer.state, .guide)

    // Walk to the door, 1 m per second.
    let total = Geo.distanceMeters(
      lat1: Self.westStart.lat, lon1: Self.westStart.lon, lat2: Self.door.lat, lon2: Self.door.lon)
    var walked = 1.0
    var sawConfirm = false
    while trip.reducer.state != .arrived, walked < total + 2 {
      let p = Self.point(from: Self.westStart, bearing: Self.doorBearingFromWest, meters: walked)
      trip.poseFacingTarget(p.lat, p.lon)
      if trip.reducer.state == .confirm { sawConfirm = true }
      walked += 1
    }
    XCTAssertTrue(sawConfirm)
    XCTAssertEqual(trip.reducer.state, .arrived)
    XCTAssertEqual(Array(trip.log.suffix(4)), [.say(.arrival), .stopCamera, .stopARTracking, .persist])

    let said = trip.said
    XCTAssertFalse(said.contains(.warning(.notSure)), "first steps went the right way")
    XCTAssertFalse(said.contains(.offRoute))
    XCTAssertTrue(said.contains(.landmark(kind: "handrail", side: .right)) ||
      said.contains(.landmark(kind: "handrail", side: .left)) ||
      said.contains(.landmark(kind: "handrail", side: .unknown)), "handrail near the door")
    XCTAssertFalse(said.contains { if case .landmark("bench", _) = $0 { return true }; return false },
      "the bench is ~10 m off the path")
    let distances = said.compactMap { e -> Double? in
      if case .distance(let m) = e { return m } else { return nil }
    }
    XCTAssertEqual(distances.count, 3, "~100, 60 and 30 feet: \(distances)")
    let crumbs = trip.log.filter { if case .saveBreadcrumb = $0 { return true }; return false }
    XCTAssertGreaterThanOrEqual(crumbs.count, 5)
  }

  func testOppositeSideNeverPointsAtTheDoor() throws {
    var trip = Trip()
    try trip.ride(course: 0)  // north, against the southbound centerline: curb on the east
    XCTAssertEqual(trip.reducer.sameSide, false)
    XCTAssertEqual(trip.said, [.exitCurbSide])
    trip.send(.startTapped)

    let start = trip.log.count
    // The rider walks south along the east sidewalk, facing the door's direction at times.
    for i in 0..<30 {
      let lat = Self.eastStart.lat - Double(i) * 0.00001
      trip.poseFacingTarget(lat, Self.eastStart.lon)
      trip.send(.doorSeen(offsetDegrees: 0, meters: 15))
      trip.send(.textSeen("77", bearingDegrees: 250))
    }
    let effects = Array(trip.log[start...])
    let said = effects.compactMap { e -> FeedbackEvent? in
      if case .say(let ev) = e { return ev } else { return nil }
    }
    XCTAssertEqual(said.count, 2, "\(said)")
    guard case .brief(sameSide: false, _, _)? = said.first else {
      return XCTFail("expected the across-the-street brief, got \(said)")
    }
    XCTAssertEqual(said.last, .warning(.crossStreet(crossingMeters: nil)))
    for e in said {
      switch e {
      case .direction, .distance, .bearingLock, .doorDetected, .landmark, .buildingConfirmed:
        XCTFail("guided toward the door from across the street: \(e)")
      default: break
      }
    }
    XCTAssertEqual(trip.reducer.state, .orient)

    // Once the rider is on the door's side, guidance starts with a this-side brief.
    let across = trip.poseFacingTarget(Self.westStart.lat, Self.westStart.lon)
    guard case .say(.brief(sameSide: true, _, _))? = across.first else {
      return XCTFail("expected a this-side brief after crossing, got \(across)")
    }
    XCTAssertEqual(trip.reducer.sameSide, true)
  }

  func testUnknownSideWhenTurnedOrOneway() throws {
    var trip = Trip()
    trip.send(.bundleLoaded(try Fixtures.example()))
    for course in [90.0, 120, 150, 180, 180, 180] {
      trip.send(.carCourse(degrees: course, speed: 8, accuracy: 5, at: trip.now))
      trip.now += 1
    }
    trip.send(.carStopped(at: trip.now))
    trip.send(.walkingDetected)
    XCTAssertNil(trip.reducer.sameSide, "turned in the last 10 s")

    var noTrack = Trip()
    noTrack.send(.bundleLoaded(try Fixtures.example()))
    noTrack.send(.walkingDetected)
    XCTAssertEqual(noTrack.reducer.state, .arrival)
    XCTAssertNil(noTrack.reducer.sameSide, "app closed during the ride")
  }

  func testRedLightIsNotADropOff() throws {
    var trip = Trip()
    trip.send(.bundleLoaded(try Fixtures.example()))
    trip.send(.carCourse(degrees: 180, speed: 8, accuracy: 5, at: trip.now))
    trip.send(.carStopped(at: trip.now + 1))
    trip.now += 30
    trip.send(.carCourse(degrees: 0, speed: 8, accuracy: 5, at: trip.now))
    trip.now += 1
    trip.send(.carStopped(at: trip.now))
    trip.send(.walkingDetected)
    XCTAssertEqual(trip.reducer.sameSide, false, "uses the course before the last stop")
  }

  func testFirstStepsFortyDegreesOffSaysNotSure() throws {
    var trip = try Trip.lockedOn()
    let wrong = Self.doorBearingFromWest + 40
    var said: [SessionEffect] = []
    for k in 1...6 {
      let p = Self.point(from: Self.westStart, bearing: wrong, meters: Double(k) * 1.1)
      said += trip.poseFacingTarget(p.lat, p.lon)
      if trip.reducer.state != .guide { break }
    }
    XCTAssertTrue(said.contains(.say(.warning(.notSure))), "\(said)")
    XCTAssertEqual(trip.reducer.state, .orient)
  }

  func testOffRouteSeventyDegreesForSixSecondsGoesToLastBreadcrumb() throws {
    var trip = try Trip.lockedOn()
    var lastCrumb: (lat: Double, lon: Double)?
    for k in 1...6 {
      let p = Self.point(from: Self.westStart, bearing: Self.doorBearingFromWest, meters: Double(k) * 1.1)
      for e in trip.poseFacingTarget(p.lat, p.lon) {
        if case .saveBreadcrumb(let lat, let lon) = e { lastCrumb = (lat, lon) }
      }
    }
    XCTAssertEqual(trip.reducer.state, .guide)
    let crumb = try XCTUnwrap(lastCrumb)
    XCTAssertNotEqual(crumb.lat, Self.westStart.lat, "a breadcrumb was saved along the walk")

    let here = Self.point(from: Self.westStart, bearing: Self.doorBearingFromWest, meters: 6.6)
    let toDoor = Geo.bearingDegrees(lat1: here.lat, lon1: here.lon, lat2: Self.door.lat, lon2: Self.door.lon)
    var effects: [SessionEffect] = []
    for second in 0...6 {
      // Drifting around a planter: walking 70° off the door at 1 m/s.
      let p = Self.point(from: here, bearing: toDoor + 70, meters: Double(second))
      effects += trip.pose(p.lat, p.lon, heading: toDoor + 70)
      if second < 5 { XCTAssertEqual(trip.reducer.state, .guide, "too early at \(second) s") }
    }
    XCTAssertTrue(effects.contains(.say(.offRoute)))
    XCTAssertEqual(trip.reducer.state, .lost)
    let target = try XCTUnwrap(trip.reducer.target)
    XCTAssertEqual(target.id, "breadcrumb")
    XCTAssertEqual(target.lat, crumb.lat, accuracy: 1e-9)
    XCTAssertEqual(target.lon, crumb.lon, accuracy: 1e-9)

    // Back at the breadcrumb: re-orient toward the door.
    trip.poseFacingTarget(crumb.lat, crumb.lon)
    XCTAssertEqual(trip.reducer.state, .orient)
    XCTAssertEqual(trip.reducer.target?.id, "c1")
  }

  func testShortDriftIsNotOffRoute() throws {
    var trip = try Trip.lockedOn()
    let toDoor = Self.doorBearingFromWest
    for _ in 0..<4 { trip.pose(Self.westStart.lat, Self.westStart.lon, heading: toDoor + 70) }
    trip.pose(Self.westStart.lat, Self.westStart.lon, heading: toDoor)
    for _ in 0..<4 { trip.pose(Self.westStart.lat, Self.westStart.lon, heading: toDoor + 70) }
    XCTAssertEqual(trip.reducer.state, .guide)
    XCTAssertFalse(trip.said.contains(.offRoute))
  }

  func testBuildingCheckNeedsTheRightDirection() throws {
    var elsewhere = try Trip.lockedOn()
    XCTAssertEqual(elsewhere.send(.textSeen("77", bearingDegrees: 60)), [], "77 on another building")
    XCTAssertEqual(elsewhere.send(.textSeen("177", bearingDegrees: 220)), [], "177 is not 77")
    XCTAssertFalse(elsewhere.reducer.buildingConfirmed)

    var toward = try Trip.lockedOn()
    let bearing = Geo.bearingDegrees(
      lat1: Self.westStart.lat, lon1: Self.westStart.lon,
      lat2: Self.buildingCentroid.lat, lon2: Self.buildingCentroid.lon)
    XCTAssertEqual(
      toward.send(.textSeen("No. 77", bearingDegrees: bearing)), [.say(.buildingConfirmed(text: "77"))])
    XCTAssertTrue(toward.reducer.buildingConfirmed)
    XCTAssertEqual(toward.send(.textSeen("77", bearingDegrees: bearing)), [], "said once")
  }

  func testDoorConfirmOnlyNearTheTarget() throws {
    var trip = try Trip.lockedOn()  // facing the door: target offset ~0
    XCTAssertEqual(trip.send(.doorSeen(offsetDegrees: 30, meters: 30)), [])
    XCTAssertEqual(trip.send(.doorSeen(offsetDegrees: -30, meters: 30)), [])
    XCTAssertEqual(
      trip.send(.doorSeen(offsetDegrees: 10, meters: 30)),
      [.say(.doorDetected(offsetDegrees: 10, meters: 30))])
  }

  func testPauseResumeStop() throws {
    var trip = try Trip.lockedOn()
    XCTAssertEqual(trip.send(.pause), [.persist])
    XCTAssertTrue(trip.reducer.isPaused)
    XCTAssertEqual(trip.send(.pause), [])

    // Nothing is said while paused, even a long time pointing the wrong way.
    let bearing = Geo.bearingDegrees(
      lat1: Self.westStart.lat, lon1: Self.westStart.lon,
      lat2: Self.buildingCentroid.lat, lon2: Self.buildingCentroid.lon)
    var paused: [SessionEffect] = []
    for _ in 0..<10 {
      paused += trip.pose(Self.westStart.lat, Self.westStart.lon, heading: Self.doorBearingFromWest + 90)
    }
    paused += trip.send(.textSeen("77", bearingDegrees: bearing))
    paused += trip.send(.doorSeen(offsetDegrees: 90, meters: 5))
    XCTAssertEqual(paused, [])
    XCTAssertEqual(trip.reducer.state, .guide)

    XCTAssertEqual(trip.send(.resume), [.persist])
    XCTAssertFalse(trip.reducer.isPaused)
    trip.poseFacingTarget(Self.westStart.lat, Self.westStart.lon)
    XCTAssertEqual(
      trip.send(.textSeen("77", bearingDegrees: bearing)), [.say(.buildingConfirmed(text: "77"))])

    XCTAssertEqual(trip.send(.stop), [.stopARTracking, .stopCamera, .persist])
    XCTAssertEqual(trip.reducer.state, .setup)
    XCTAssertEqual(trip.reducer.target?.id, "c1", "bundle kept for the next trip")
    XCTAssertEqual(trip.poseFacingTarget(Self.westStart.lat, Self.westStart.lon), [])
  }

  func testTrackingLostWarnsOnce() throws {
    var trip = try Trip.lockedOn()
    XCTAssertEqual(trip.send(.arTracking(ok: false)), [.say(.warning(.trackingLost))])
    XCTAssertEqual(trip.send(.arTracking(ok: false)), [])
    XCTAssertEqual(trip.send(.arTracking(ok: true)), [])
    XCTAssertEqual(trip.send(.arTracking(ok: false)), [.say(.warning(.trackingLost))])
  }

  func testReducerRoundTripsForRelaunch() throws {
    var trip = try Trip.lockedOn()
    let data = try JSONEncoder().encode(trip.reducer)
    var restored = try JSONDecoder().decode(SessionReducer.self, from: data)
    XCTAssertEqual(restored.state, .guide)
    XCTAssertEqual(restored.sameSide, true)
    XCTAssertEqual(restored.target?.id, "c1")
    let p = Self.point(from: Self.westStart, bearing: Self.doorBearingFromWest, meters: 2)
    let a = trip.poseFacingTarget(p.lat, p.lon)
    let b = restored.handle(
      .pose(lat: p.lat, lon: p.lon, headingDegrees: Geo.bearingDegrees(
        lat1: p.lat, lon1: p.lon, lat2: Self.door.lat, lon2: Self.door.lon),
        accuracyMeters: 5, at: trip.now - 1))
    XCTAssertEqual(a, b)
  }

  func testPocketModeSkipsCamera() throws {
    var trip = Trip(reducer: SessionReducer(cameraFirst: false))
    try trip.ride(course: 180)
    XCTAssertEqual(trip.send(.startTapped), [.startARTracking, .persist])
  }
}

extension SessionEffect {
  var event: FeedbackEvent? {
    if case .say(let e) = self { return e }
    return nil
  }
}
