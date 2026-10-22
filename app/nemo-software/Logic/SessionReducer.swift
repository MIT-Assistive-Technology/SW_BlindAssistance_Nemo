//  SessionReducer.swift
//  nemo-software
//
//  The trip state machine (FE-10) as a pure value type: inputs in, effects out, no clocks,
//  sensors or sound. `NavigationSession` (Session/) wraps it for SwiftUI.
//  See docs/car-to-curb-plan.md sections 3 (user workflow), 6 (side of street),
//  7 (building check), 11 (phone) and 16 (safety rules).
//
//    Setup -> Arrival -> Orient -> Guide -> Confirm -> Arrived
//                          ^         |
//                          +------ Lost
//
//  Safety rules enforced here:
//    - "Exit on the curb side." before anything else at drop-off.
//    - Door across the street: warn once, then say nothing about the door (no direction,
//      distance, landmark or door cue) until the rider is on the door's side.
//    - First-steps check, off-route recovery to the last breadcrumb, and a building check
//      that only counts when the text's bearing points at the building outline.
//

import Foundation

public enum SessionState: String, Codable, Equatable, Sendable {
  /// Destination set, bundle cached, waiting for the ride to end.
  case setup
  /// Car stopped: side of street worked out, "Exit on the curb side." said.
  case arrival
  /// Rider turns until the heading is within 15° of the target for 1 s.
  case orient
  /// Walking: beacon, landmarks, building check (camera-first mode).
  case guide
  /// Last ~10 m before the door.
  case confirm
  case arrived
  /// Off by more than 60° for 5 s: guiding back to the last breadcrumb.
  case lost
}

public enum SessionInput: Sendable {
  case bundleLoaded(ResolveResult)
  /// `CLLocation.course` / `speed` / `courseAccuracy` during the ride.
  case carCourse(degrees: Double, speed: Double, accuracy: Double, at: Date)
  case carStopped(at: Date)
  case walkingDetected
  case startTapped
  case pose(lat: Double, lon: Double, headingDegrees: Double, accuracyMeters: Double, at: Date)
  case arTracking(ok: Bool)
  /// Text recognized in a camera frame, and the true bearing it was seen at.
  case textSeen(String, bearingDegrees: Double)
  /// A door the camera found, relative to the rider's heading (negative = left).
  case doorSeen(offsetDegrees: Double, meters: Double)
  case pause
  case resume
  case stop
}

public enum SessionEffect: Equatable, Sendable {
  case say(FeedbackEvent)
  case startARTracking
  case stopARTracking
  case startCamera
  case stopCamera
  case saveBreadcrumb(lat: Double, lon: Double)
  /// Save the reducer (it is Codable) so a relaunch mid-trip resumes.
  case persist
}

public struct SessionReducer: Codable, Sendable {
  // MARK: Tuning (plan sections 3, 5, 16)
  static let trustedCarSpeed = 3.0  // m/s
  static let maxCourseAccuracy = 25.0  // degrees
  static let turnWindow = 10.0  // s
  static let turnDegrees = 30.0
  static let maxCourseAgeAtStop = 20.0  // s
  static let lockDegrees = 15.0
  static let lockSeconds = 1.0
  static let firstStepsMeters = 5.0
  static let firstStepsDegrees = 30.0
  static let offRouteDegrees = 60.0
  static let offRouteSeconds = 5.0
  static let breadcrumbMeters = 5.0
  static let breadcrumbReachedMeters = 3.0
  static let landmarkAheadMeters = 5.0
  static let confirmMeters = 10.0
  static let arrivalMeters = 2.0
  static let doorConfirmDegrees = 15.0
  static let acrossMarginMeters = 5.0  // past the centerline onto the door's side
  static let buildingToleranceDegrees = 10.0
  static let distanceMilestones = [30.0, 18.3, 9.1]  // ~100, 60 and 30 feet
  static let orientCueSeconds = 2.0
  static let guideCueSeconds = 3.0
  static let driftCueDegrees = 15.0

  // MARK: Public state
  public private(set) var state: SessionState = .setup
  /// What the beacon points at: the door, or the last breadcrumb while `.lost`.
  public private(set) var target: Candidate?
  /// nil = unknown (one-way street, a recent turn, no car track).
  public private(set) var sameSide: Bool?
  public private(set) var isPaused = false
  public private(set) var bundle: ResolveResult?
  public private(set) var buildingConfirmed = false
  /// Start the camera (building check) at start. false = pocket mode.
  public var cameraFirst: Bool

  // MARK: Private state
  struct CarFix: Codable, Sendable {
    var degrees, speed, accuracy: Double
    var at: Date
  }
  struct Fix: Codable, Sendable {
    var lat, lon, heading: Double
    var at: Date
  }

  private var door: Candidate?
  private var carTrack: [CarFix] = []
  private var stoppedAt: Date?
  private var lastPose: Fix?
  private var briefed = false
  private var acrossStreet = false
  private var lockSince: Date?
  private var walkStart: Fix?
  private var expectedBearing: Double?
  private var firstStepsDone = false
  private var offCourseSince: Date?
  private var breadcrumbs: [Fix] = []
  private var lastCueAt: Date?
  private var milestonesLeft = SessionReducer.distanceMilestones
  private var announcedLandmarks: Set<Int> = []
  private var trackingLost = false

  public init(cameraFirst: Bool = true) {
    self.cameraFirst = cameraFirst
  }

  private var isWalking: Bool { [.orient, .guide, .confirm, .lost].contains(state) }

  // MARK: - Inputs

  public mutating func handle(_ input: SessionInput) -> [SessionEffect] {
    switch input {
    case .bundleLoaded(let result):
      bundle = result
      if state == .setup {
        door = result.candidates.first
        target = door
      }
      return [.persist]

    case .carCourse(let degrees, let speed, let accuracy, let at):
      carTrack.append(CarFix(degrees: degrees, speed: speed, accuracy: accuracy, at: at))
      carTrack.removeAll { at.timeIntervalSince($0.at) > 60 }
      // Moving again after a stop: it was a red light, not the drop-off.
      if let stop = stoppedAt, speed > Self.trustedCarSpeed, at > stop { stoppedAt = nil }
      return []

    case .carStopped(let at):
      guard state == .setup else { return [] }
      stoppedAt = at
      return []

    case .walkingDetected:
      guard state == .setup, bundle != nil else { return [] }
      return arrive()

    case .startTapped:
      guard bundle != nil, door != nil else { return [] }
      var effects: [SessionEffect] = []
      if state == .setup { effects += arrive() }
      guard state == .arrival else { return effects }
      state = .orient
      isPaused = false
      effects.append(.startARTracking)
      if cameraFirst { effects.append(.startCamera) }
      effects.append(.persist)
      return effects

    case .pose(let lat, let lon, let heading, _, let at):
      return onPose(Fix(lat: lat, lon: lon, heading: heading, at: at))

    case .arTracking(let ok):
      if ok {
        trackingLost = false
        return []
      }
      guard isWalking, !trackingLost else { return [] }
      trackingLost = true
      return [.say(.warning(.trackingLost))]

    case .textSeen(let text, let bearing):
      return onText(text, bearing: bearing)

    case .doorSeen(let offset, let meters):
      return onDoor(offset: offset, meters: meters)

    case .pause:
      guard !isPaused else { return [] }
      isPaused = true
      return [.persist]

    case .resume:
      guard isPaused else { return [] }
      isPaused = false
      lockSince = nil
      offCourseSince = nil
      lastCueAt = nil
      return [.persist]

    case .stop:
      let kept = bundle
      self = SessionReducer(cameraFirst: cameraFirst)
      if let kept { _ = handle(.bundleLoaded(kept)) }
      return [.stopARTracking, .stopCamera, .persist]
    }
  }

  // MARK: - Drop-off

  private mutating func arrive() -> [SessionEffect] {
    sameSide = stoppedAt.flatMap(sideOfStreet(stoppedAt:))
    acrossStreet = sameSide == false
    state = .arrival
    return [.say(.exitCurbSide), .persist]
  }

  /// Side of street from the last trustworthy car course: speed > 3 m/s, good course
  /// accuracy, no turn in the 10 s before it, and recent enough to describe the stop.
  private func sideOfStreet(stoppedAt stop: Date) -> Bool? {
    guard let street = bundle?.streetSide, let road = Geo.polylineBearing(street.centerline)
    else { return nil }
    let trusted = carTrack.filter {
      $0.speed > Self.trustedCarSpeed && $0.accuracy >= 0
        && $0.accuracy <= Self.maxCourseAccuracy && $0.at <= stop
    }
    guard let last = trusted.last, stop.timeIntervalSince(last.at) <= Self.maxCourseAgeAtStop
    else { return nil }
    let turned = trusted.contains {
      last.at.timeIntervalSince($0.at) <= Self.turnWindow
        && abs(Geo.relativeAngle(heading: last.degrees, target: $0.degrees)) > Self.turnDegrees
    }
    if turned { return nil }
    return Geo.sameSide(
      courseDegrees: last.degrees, roadBearingDegrees: road,
      doorSideOfRoad: street.doorSideOfRoad, oneway: street.oneway)
  }

  // MARK: - Walking

  private mutating func onPose(_ p: Fix) -> [SessionEffect] {
    lastPose = p
    guard isWalking, !isPaused, let door, let bundle else { return [] }
    var effects: [SessionEffect] = []

    if acrossStreet {
      guard onDoorSide(p, street: bundle.streetSide) else {
        // Warn once, then stay silent about the door until the rider is across.
        if !briefed {
          briefed = true
          let crossing = bundle.pathChecks.nearestCrossing.flatMap { c -> Double? in
            c.count >= 2 ? Geo.distanceMeters(lat1: p.lat, lon1: p.lon, lat2: c[1], lon2: c[0]) : nil
          }
          effects.append(.say(.brief(sameSide: false, meters: distance(p, door), offsetDegrees: 0)))
          effects.append(.say(.warning(.crossStreet(crossingMeters: crossing))))
        }
        return effects
      }
      acrossStreet = false
      sameSide = true
      briefed = false
      state = .orient
      lockSince = nil
    }

    guard let goal = target else { return effects }
    let dist = distance(p, goal)
    let offset = Geo.relativeAngle(heading: p.heading, target: bearing(p, goal))

    if !briefed {
      briefed = true
      lastCueAt = p.at
      milestonesLeft.removeAll { dist <= $0 }
      effects.append(.say(.brief(sameSide: sameSide, meters: dist, offsetDegrees: offset)))
    }

    switch state {
    case .orient:
      if abs(offset) <= Self.lockDegrees {
        let since = lockSince ?? p.at
        lockSince = since
        if p.at.timeIntervalSince(since) >= Self.lockSeconds {
          state = .guide
          lockSince = nil
          effects.append(.say(.bearingLock))
          effects += startWalk(p, door: door)
        }
      } else {
        lockSince = nil
        effects += cue(offset, at: p.at, every: Self.orientCueSeconds)
      }

    case .guide, .confirm:
      effects += guideStep(p, door: door, dist: dist, offset: offset)

    case .lost:
      if dist <= Self.breadcrumbReachedMeters {
        // Back at the breadcrumb: re-orient toward the door.
        target = door
        state = .orient
        lockSince = nil
        effects.append(.persist)
      } else {
        effects += cue(offset, at: p.at, every: Self.orientCueSeconds)
      }

    default:
      break
    }
    return effects
  }

  private mutating func startWalk(_ p: Fix, door: Candidate) -> [SessionEffect] {
    walkStart = p
    expectedBearing = bearing(p, door)
    offCourseSince = nil
    var effects: [SessionEffect] = [.persist]
    if breadcrumbs.last.map({ distance($0, p) >= Self.breadcrumbMeters }) ?? true {
      breadcrumbs.append(p)
      effects.append(.saveBreadcrumb(lat: p.lat, lon: p.lon))
    }
    return effects
  }

  private mutating func guideStep(
    _ p: Fix, door: Candidate, dist: Double, offset: Double
  ) -> [SessionEffect] {
    var effects: [SessionEffect] = []

    if dist <= Self.arrivalMeters {
      state = .arrived
      return [.say(.arrival), .stopCamera, .stopARTracking, .persist]
    }
    if state == .guide, dist <= Self.confirmMeters {
      state = .confirm
      effects.append(.persist)
    }

    // First-steps check: after ~5 m, is the rider walking the expected way?
    if !firstStepsDone, let start = walkStart, let expected = expectedBearing,
      distance(start, p) >= Self.firstStepsMeters
    {
      firstStepsDone = true
      let walked = bearing(start, p)
      if abs(Geo.relativeAngle(heading: expected, target: walked)) > Self.firstStepsDegrees {
        state = .orient
        lockSince = nil
        return effects + [.say(.warning(.notSure)), .persist]
      }
    }

    // Off route: more than 60° off for 5 s -> guide back to the last breadcrumb.
    if state == .guide {
      if abs(offset) > Self.offRouteDegrees {
        let since = offCourseSince ?? p.at
        offCourseSince = since
        if p.at.timeIntervalSince(since) >= Self.offRouteSeconds {
          let crumb = breadcrumbs.last { $0.at < since } ?? breadcrumbs.first ?? walkStart ?? p
          target = Candidate(
            id: "breadcrumb", lat: crumb.lat, lon: crumb.lon, confidence: 0, band: "breadcrumb",
            label: "Last breadcrumb", speak: nil, provenance: [])
          state = .lost
          offCourseSince = nil
          lastCueAt = p.at
          return effects + [.say(.offRoute), .persist]
        }
      } else {
        offCourseSince = nil
      }
    }

    if offCourseSince == nil, let last = breadcrumbs.last,
      distance(last, p) >= Self.breadcrumbMeters
    {
      breadcrumbs.append(p)
      effects.append(.saveBreadcrumb(lat: p.lat, lon: p.lon))
    }

    if milestonesLeft.contains(where: { dist <= $0 }) {
      milestonesLeft.removeAll { dist <= $0 }
      effects.append(.say(.distance(meters: dist)))
    }

    effects += landmarksAhead(p)

    if abs(offset) > Self.driftCueDegrees {
      effects += cue(offset, at: p.at, every: Self.guideCueSeconds)
    }
    return effects
  }

  /// Landmarks within ~5 m and in front of the rider, each announced once.
  private mutating func landmarksAhead(_ p: Fix) -> [SessionEffect] {
    guard let landmarks = bundle?.landmarks else { return [] }
    var effects: [SessionEffect] = []
    let frame = LocalFrame(originLat: p.lat, originLon: p.lon)
    let h = Geo.radians(p.heading)
    for (i, lm) in landmarks.enumerated() where !announcedLandmarks.contains(i) {
      let d = Geo.distanceMeters(lat1: p.lat, lon1: p.lon, lat2: lm.lat, lon2: lm.lon)
      guard d <= Self.landmarkAheadMeters else { continue }
      let rel = Geo.relativeAngle(
        heading: p.heading,
        target: Geo.bearingDegrees(lat1: p.lat, lon1: p.lon, lat2: lm.lat, lon2: lm.lon))
      guard abs(rel) <= 90 else { continue }
      announcedLandmarks.insert(i)
      var side = Geo.side(
        direction: (sin(h), cos(h)), toPoint: frame.toLocal(lat: lm.lat, lon: lm.lon))
      if side == .unknown { side = Side(rawValue: lm.side.lowercased()) ?? .unknown }
      effects.append(.say(.landmark(kind: lm.kind, side: side)))
    }
    return effects
  }

  private mutating func cue(_ offset: Double, at: Date, every: Double) -> [SessionEffect] {
    if let last = lastCueAt, at.timeIntervalSince(last) < every { return [] }
    lastCueAt = at
    return [.say(.direction(offsetDegrees: offset))]
  }

  // MARK: - Camera

  /// Counts only when the text matches `recognize.text` AND its bearing points at the
  /// building outline. A matching number on the wrong building says nothing.
  private mutating func onText(_ seen: String, bearing: Double) -> [SessionEffect] {
    guard isWalking, !isPaused, !acrossStreet, !buildingConfirmed, let p = lastPose,
      let building = bundle?.building, let token = matchedToken(seen),
      pointsAt(building.footprint, from: p, bearing: bearing)
    else { return [] }
    buildingConfirmed = true
    return [.say(.buildingConfirmed(text: token))]
  }

  private func matchedToken(_ seen: String) -> String? {
    let tokens =
      bundle?.recognize?.text
      ?? [bundle?.building.housenumber, bundle?.building.name].compactMap { $0 }
    let lowered = seen.lowercased()
    let words = lowered.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    return tokens.first { token in
      let t = token.lowercased().trimmingCharacters(in: .whitespaces)
      guard !t.isEmpty else { return false }
      // Numbers must match a whole word, so "177" doesn't count as "77".
      return t.allSatisfy(\.isNumber) ? words.contains(t) : lowered.contains(t)
    }
  }

  private func pointsAt(_ ring: [[Double]], from p: Fix, bearing: Double) -> Bool {
    let ring = ring.filter { $0.count >= 2 }
    guard !ring.isEmpty else { return false }
    if Geo.contains(ring, lat: p.lat, lon: p.lon) { return true }
    // Angles relative to the outline's centroid direction, so the span never wraps past
    // ±180° (from outside, a building covers well under 180°).
    let lat = ring.map { $0[1] }.reduce(0, +) / Double(ring.count)
    let lon = ring.map { $0[0] }.reduce(0, +) / Double(ring.count)
    let center = Geo.bearingDegrees(lat1: p.lat, lon1: p.lon, lat2: lat, lon2: lon)
    let rel = ring.map {
      Geo.relativeAngle(
        heading: center,
        target: Geo.bearingDegrees(lat1: p.lat, lon1: p.lon, lat2: $0[1], lon2: $0[0]))
    }
    let seen = Geo.relativeAngle(heading: center, target: bearing)
    let tol = Self.buildingToleranceDegrees
    return seen >= rel.min()! - tol && seen <= rel.max()! + tol
  }

  /// Door cue only when the camera's door is within ±15° of where the target should be.
  private func onDoor(offset: Double, meters: Double) -> [SessionEffect] {
    guard state == .guide || state == .confirm, !isPaused, !acrossStreet,
      let p = lastPose, let door, target?.id == door.id
    else { return [] }
    let expected = Geo.relativeAngle(heading: p.heading, target: bearing(p, door))
    guard abs(Geo.relativeAngle(heading: expected, target: offset)) <= Self.doorConfirmDegrees
    else { return [] }
    return [.say(.doorDetected(offsetDegrees: offset, meters: meters))]
  }

  // MARK: - Geometry helpers

  /// Is the rider past the centerline, on the door's side, by a margin?
  private func onDoorSide(_ p: Fix, street: StreetSide?) -> Bool {
    guard let street, let first = street.centerline.first, let last = street.centerline.last,
      first.count >= 2, last.count >= 2,
      let doorSide = Side(rawValue: street.doorSideOfRoad.lowercased())
    else { return false }
    let frame = LocalFrame(originLat: first[1], originLon: first[0])
    let road = frame.toLocal(lat: last[1], lon: last[0])
    let rider = frame.toLocal(lat: p.lat, lon: p.lon)
    let length = hypot(road.east, road.north)
    guard length > 0 else { return false }
    let leftOfRoad = (road.east * rider.north - road.north * rider.east) / length
    switch doorSide {
    case .left: return leftOfRoad >= Self.acrossMarginMeters
    case .right: return leftOfRoad <= -Self.acrossMarginMeters
    case .unknown: return false
    }
  }

  private func distance(_ p: Fix, _ c: Candidate) -> Double {
    Geo.distanceMeters(lat1: p.lat, lon1: p.lon, lat2: c.lat, lon2: c.lon)
  }
  private func distance(_ a: Fix, _ b: Fix) -> Double {
    Geo.distanceMeters(lat1: a.lat, lon1: a.lon, lat2: b.lat, lon2: b.lon)
  }
  private func bearing(_ p: Fix, _ c: Candidate) -> Double {
    Geo.bearingDegrees(lat1: p.lat, lon1: p.lon, lat2: c.lat, lon2: c.lon)
  }
  private func bearing(_ a: Fix, _ b: Fix) -> Double {
    Geo.bearingDegrees(lat1: a.lat, lon1: a.lon, lat2: b.lat, lon2: b.lon)
  }
}
