//  NavigationSession.swift
//  nemo-software
//
//  The trip state machine (FE-10). Drives which sensors run and what FeedbackKit says.
//  See docs/car-to-curb-plan.md sections 3 (user workflow) and 11 (phone).
//
//    Setup -> Riding -> Arrival -> Orient -> Guide -> Confirm -> Arrived
//                                    ^         |         |
//                                    +------ Lost <------+
//
//  Everything it needs arrives through `update(position:heading:)` as value types, so a
//  whole trip can be replayed from a recorded trace in a unit test instead of walked
//  (QA-4). It never touches CoreLocation, a synthesizer or the camera: positions come in,
//  FeedbackEvents go out.
//
//  Two rules it exists to enforce:
//    - The rider is never told to cross a road. If the door is on the far side, guidance
//      waits until they say they're across.
//    - Guidance never stops silently. Every exit from .guide says something.
//

import Combine
import Foundation

public enum SessionState: String, Codable, Equatable, Sendable {
  /// Destination set, bundle cached, waiting for the ride to start.
  case setup
  /// In the car. Course is being recorded for side-of-street detection (FE-13).
  case riding
  /// Out of the car: side of street known (or asked), waiting to start the walk.
  case arrival
  /// Rider turns until the heading is within 15° of the door for 1 s.
  case orient
  /// Walking: distance callouts, breadcrumbs, the first-steps check.
  case guide
  /// Last ~15 m: door facts, and the camera door finder. Only the camera or the rider
  /// ("I'm at the door") ends it; GPS can't place a door to the metre.
  case confirm
  case arrived
  /// Off by more than 60° for 5 s, or the first-steps check failed.
  case lost
}

/// A position as the state machine sees it. No CoreLocation, so a recorded trace can be
/// replayed headless.
nonisolated public struct GuidancePosition: Codable, Equatable, Sendable {
  public let latitude: Double
  public let longitude: Double
  public let horizontalAccuracyMeters: Double?
  public let timestamp: Date

  public init(
    latitude: Double,
    longitude: Double,
    horizontalAccuracyMeters: Double? = nil,
    timestamp: Date = Date()
  ) {
    self.latitude = latitude
    self.longitude = longitude
    self.horizontalAccuracyMeters = horizontalAccuracyMeters
    self.timestamp = timestamp
  }
}

/// Every number the walk depends on, in one place. The plan fixes some of these
/// (15° lock, 10 m confirm, 60°-for-5 s lost, the ~5 m first-steps check, spoken
/// distances at 60 ft and 30 ft); the rest are starting points to be tuned with the
/// codesigners, not measured facts.
nonisolated public struct GuidanceThresholds: Equatable, Sendable {
  public var lockWithinDegrees = 15.0
  public var lockHoldSeconds = 1.0
  /// Where the door finder starts. Wider than the plan's 10 m because GPS is 5–15 m
  /// out near buildings and the camera needs time to find the door.
  public var confirmWithinMeters = 15.0
  /// Leaving .confirm again needs hysteresis, or GPS noise flaps the state.
  public var leaveConfirmBeyondMeters = 22.0
  /// GPS this close (or within the fix's own accuracy, up to `doorCloseMaxMeters`) says
  /// "the door should be close". It no longer ends the trip: only the camera or the
  /// rider does.
  public var arrivedWithinMeters = 3.0
  public var doorCloseMaxMeters = 8.0
  public var lostOffByDegrees = 60.0
  public var lostAfterSeconds = 5.0
  public var recoverWithinDegrees = 60.0
  public var recoverHoldSeconds = 2.0
  public var firstStepsAfterMeters = 5.0
  public var breadcrumbEveryMeters = 5.0
  /// 60 ft and 30 ft, in meters.
  public var distanceCalloutsMeters = [18.0, 9.0]

  // MARK: Camera building check (CV-9)

  /// A sighting more than this far from where the building should be is a different
  /// building with the same number, not a correction. The compass itself is only
  /// ±10–20° out, so anything past this can't be explained by compass error.
  public var sightingMustAgreeWithinDegrees = 25.0
  /// How much of a new correction to take at once. Half damps a single noisy read
  /// without making the correction sluggish.
  public var sightingSmoothing = 0.5
  /// Hard cap on the correction, so a stream of bad sightings can't spin the rider.
  public var maxHeadingBiasDegrees = 25.0
  /// Vision results below this are ignored.
  public var minSightingConfidence = 0.5
  /// The same building text isn't announced again inside this window. Every read is
  /// still checked and still corrects the compass.
  public var buildingConfirmedRepeatSeconds = 30.0

  // MARK: Door finder (camera, last stretch)

  /// A LiDAR door this close and this nearly straight ahead is the end of the walk.
  public var doorReachedWithinMeters = 1.2
  public var doorReachedWithinDegrees = 25.0
  /// Facing what the camera found: the lock buzz and "Door straight ahead".
  public var facingDoorWithinDegrees = 12.0
  /// A sighting after this long without one, or of a different thing, is spoken as new.
  /// Anything sooner only moves the beacon.
  public var doorSightingNewAfterSeconds = 6.0

  /// Side of street unknown at the start: the rider counts as on the door's side once
  /// GPS puts them at least this far from the centerline on that side, and at least as
  /// far as the fix's own accuracy. A sidewalk is usually 6–12 m from the centerline.
  public var sideFromGPSMinMeters = 6.0
  /// How often "stay on the sidewalk" is repeated while the side is still unknown.
  public var sideUnknownRepeatSeconds = 20.0

  /// Progress beats angle. Bundles have no walking route, so the door is aimed at in a
  /// straight line, often through the building when it's round a corner. Walking along
  /// the sidewalk then looks 30–80° "off" while the rider is getting closer the whole
  /// time. So: closing in by at least this much over `progressWindowSeconds` means on
  /// route, whatever the angle.
  public var progressMinMeters = 2.0
  public var progressWindowSeconds = 10.0
  /// First-steps check: the distance to the door must shrink by at least this fraction
  /// of the distance walked (0.3 ≈ heading within ~70° of the door). Walking away fails.
  public var firstStepsMinProgressRatio = 0.3

  public init() {}
}

/// What's saved so a relaunch mid-trip can pick up (plan section 11, ADR 0013).
nonisolated public struct SessionSnapshot: Codable, Equatable, Sendable {
  public var state: SessionState
  public var address: String
  public var destinationId: String
  public var riderIsOnDoorSide: Bool?
  public var breadcrumbs: [GuidancePosition]
  public var updatedAt: Date
}

@MainActor
public final class NavigationSession: ObservableObject {
  @Published public private(set) var state: SessionState = .setup
  /// Last computed distance to the target door, for the screen.
  @Published public private(set) var metersToDoor: Double?
  /// Signed angle from the rider's heading to the door, negative to the left.
  @Published public private(set) var offsetDegrees: Double?
  /// nil until the side of street is settled; false means the door is across the road.
  @Published public private(set) var riderIsOnDoorSide: Bool?
  /// How wrong the phone's heading appears to be, learned from the camera (CV-9).
  /// Positive means the compass reads higher than reality. Subtracted from every
  /// heading before any direction is worked out.
  @Published public private(set) var headingBiasDegrees = 0.0
  /// True once a sighting has agreed with the map. The camera can stop running after
  /// this, which is where most of its battery cost goes (plan section 7).
  @Published public private(set) var isBuildingConfirmed = false

  /// Guidance started without knowing which side of the street the rider is on. The
  /// rider is never asked to work it out: the app checks as they walk, and gives no
  /// direction toward a door across the road in the meantime.
  @Published public private(set) var sideUnconfirmed = false
  /// Why the walk last went to `.lost`, in plain words, for the debug panel.
  @Published public private(set) var lastLostReason: String?
  /// What the door finder saw last, for the debug panel and "Where am I".
  @Published public private(set) var lastDoorSighting: DoorSighting?
  private var facingDoorSaid = false
  /// When each kind of thing was last seen, so a door seen continuously is spoken once
  /// and the text reader flickering between "77" and ENTRANCE doesn't re-announce both.
  private var doorKindLastSeen: [DoorSighting.Kind: Date] = [:]
  private var doorCloseSaid = false
  private var lastBuildingConfirmed: (text: String, at: Date)?
  /// Recent distances to the door, for "is the rider getting closer?".
  private var distanceHistory: [(at: Date, meters: Double)] = []
  private var sideUnknownSaidAt: Date?

  public var thresholds = GuidanceThresholds()

  private let feedback: FeedbackKit
  private let store: SessionStore?
  private var bundle: ResolveResult?
  private var address = ""

  /// Where guidance started, used by the first-steps check.
  private var anchor: GuidancePosition?
  private var lastPosition: GuidancePosition?
  private var breadcrumbs: [GuidancePosition] = []
  private var lockedSince: Date?
  private var offRouteSince: Date?
  private var recoveringSince: Date?
  private var firstStepsChecked = false
  private var calloutsSpoken: Set<Double> = []

  public init(feedback: FeedbackKit, store: SessionStore? = nil) {
    self.feedback = feedback
    self.store = store
  }

  // MARK: - Destination

  public func setDestination(_ bundle: ResolveResult, address: String) {
    self.bundle = bundle
    self.address = address
    if state == .setup { persist() }
  }

  /// The door being guided to. The rest of `candidates` are backups.
  public var target: Candidate? { bundle?.candidates.first }

  /// Where the beacon should point. While lost that's the last breadcrumb, never the
  /// door: the rider got off track somewhere, and the breadcrumb is a place they
  /// actually stood.
  public var targetCoordinate: (lat: Double, lon: Double)? {
    if state == .lost, let crumb = breadcrumbs.last {
      return (crumb.latitude, crumb.longitude)
    }
    guard let target else { return nil }
    return (target.lat, target.lon)
  }

  // MARK: - Trip events (the rider, or the ride screen)

  /// "I'm in the car".
  public func startRiding() {
    state = .riding
    persist()
  }

  /// The rider said they're out of the car (FE-13). `isOnDoorSide` is nil when the side
  /// couldn't be decided, which means the rider still has to be asked.
  public func riderIsOutOfCar(isOnDoorSide: Bool?) {
    riderIsOnDoorSide = isOnDoorSide
    state = .arrival
    persist()
  }

  /// The rider answered the side-of-street question, or has just crossed.
  public func riderIsOnDoorSide(_ isOnDoorSide: Bool) {
    riderIsOnDoorSide = isOnDoorSide
    persist()
  }

  /// Can the walk start? False only while the door is known to be across the road. An
  /// unknown side doesn't block: the rider shouldn't have to work out where they are.
  public var canStartGuidance: Bool {
    bundle != nil && riderIsOnDoorSide != false
  }

  /// Back Tap, or the Start button.
  public func startGuidance() {
    guard bundle != nil else {
      feedback.emit(.noDestinationLoaded)
      return
    }
    switch riderIsOnDoorSide {
    case .some(true), .none:
      anchor = nil
      breadcrumbs = []
      lockedSince = nil
      offRouteSince = nil
      recoveringSince = nil
      firstStepsChecked = false
      calloutsSpoken = []
      // A new walk learns the compass error again; the old one was measured from a
      // different place and may not apply.
      headingBiasDegrees = 0
      isBuildingConfirmed = false
      state = .orient
      sideUnconfirmed = riderIsOnDoorSide == nil
      sideUnknownSaidAt = nil
      distanceHistory = []
      lastLostReason = nil
      resetDoorFinder()
      feedback.emit(.startingGuidance)
      persist()
    case .some(false):
      // Never guide, and never point a beacon, across a roadway.
      feedback.emit(.waitingToCrossStreet)
    }
  }

  /// Stop button, or the "Stop guiding" intent. Ends the trip out loud.
  public func stop() {
    feedback.stopAll()
    feedback.emit(.guidanceStopped, force: true)
    state = .setup
    anchor = nil
    breadcrumbs = []
    metersToDoor = nil
    offsetDegrees = nil
    sideUnconfirmed = false
    resetDoorFinder()
    store?.clear()
  }

  /// "I'm at the door": the rider found it. The authoritative end of the walk, like
  /// "I'm out of the car" is for the ride.
  public func riderIsAtDoor() {
    guard [.orient, .guide, .confirm, .lost].contains(state) else { return }
    arrive()
  }

  /// "Where am I / repeat": say the current state again, forced past the chatter guard.
  public func repeatGuidance() {
    switch state {
    case .orient:
      if let offset = offsetDegrees {
        feedback.emit(.direction(offsetDegrees: offset), force: true)
      } else {
        feedback.emit(.startingGuidance, force: true)
      }
    case .guide:
      if let meters = metersToDoor {
        feedback.emit(.bearingLock(metersToDoor: meters), force: true)
      }
    case .confirm:
      if let sighting = lastDoorSighting,
        Date().timeIntervalSince(sighting.timestamp) < thresholds.doorSightingNewAfterSeconds
      {
        feedback.emit(Self.announcement(for: sighting), force: true)
      } else {
        feedback.emit(.finalApproach(metersToDoor: metersToDoor, brief()), force: true)
      }
    case .lost:
      feedback.emit(.lost, force: true)
    case .arrived:
      feedback.emit(.arrival, force: true)
    case .arrival:
      if let isOnDoorSide = riderIsOnDoorSide {
        feedback.emit(
          .sideOfStreet(isOnDoorSide ? .sameSide : .acrossStreet, sideContext()), force: true)
      } else {
        feedback.emit(.askSideOfStreet(sideContext()), force: true)
      }
    case .setup, .riding:
      feedback.emit(.destinationBrief(brief()), force: true)
    }
  }

  // MARK: - What the camera saw (CV-9)

  /// Text the building check may match: the bundle's `recognize.text`, else its house
  /// number and name. Read by `AppServices` to filter camera reads (CV-9).
  public var expectedBuildingTexts: [String] {
    guard let bundle else { return [] }
    return bundle.recognize?.text
      ?? [bundle.building.housenumber, bundle.building.name].compactMap { $0 }
  }

  /// A building sighting from the camera. This is the only correction the app has for
  /// the error that matters most: the GPS anchor is 5–15 m off and the compass 10–20°,
  /// and nothing on the phone can tell from GPS alone. The camera can, because the
  /// building is a fixed thing in a known place.
  ///
  /// It is checked before it is believed. A sighting only counts if the direction it was
  /// read in agrees with where the building should be — that's what stops "77" on the
  /// building across the road from dragging guidance sideways (plan section 7). A
  /// disagreement is spoken as doubt, not silently dropped.
  ///
  /// The camera never decides *which* door is the entrance. The map does.
  @discardableResult
  public func observe(_ sighting: BuildingSighting) -> Bool {
    guard sighting.confidence >= thresholds.minSightingConfidence else { return false }
    guard let position = lastPosition, let bundle else { return false }
    let landmark = bundle.buildingCenter ?? target.map { ($0.lat, $0.lon) }
    guard let landmark else { return false }

    let expected = Geo.bearingDegrees(
      lat1: position.latitude, lon1: position.longitude, lat2: landmark.lat, lon2: landmark.lon)
    // How far the sighting is from where the map says the building is. The sighting's
    // bearing was computed from the compass, so this difference is the compass error.
    let disagreement = Geo.relativeAngle(
      heading: expected, target: sighting.bearingDegrees - headingBiasDegrees)

    guard abs(disagreement) <= thresholds.sightingMustAgreeWithinDegrees else {
      // Same number, wrong building. Say so; never re-anchor on it.
      feedback.emit(.buildingUncertain(text: sighting.text))
      return false
    }

    let corrected = headingBiasDegrees + disagreement * thresholds.sightingSmoothing
    headingBiasDegrees = min(
      max(corrected, -thresholds.maxHeadingBiasDegrees), thresholds.maxHeadingBiasDegrees)
    isBuildingConfirmed = true
    // The camera reads the number several times a second; say so once, not every read.
    if let last = lastBuildingConfirmed, last.text == sighting.text,
      sighting.timestamp.timeIntervalSince(last.at) < thresholds.buildingConfirmedRepeatSeconds
    {
      return true
    }
    lastBuildingConfirmed = (sighting.text, sighting.timestamp)
    feedback.emit(
      .buildingConfirmed(text: sighting.text, offsetDegrees: offsetDegrees))
    return true
  }

  // MARK: - The door finder (camera, last stretch)

  /// Something the camera saw near the door: a LiDAR door, the building's number, or an
  /// entrance sign. Only used in `.confirm`, where GPS has done all it can.
  ///
  /// New sightings are spoken; repeats of the same one only move the beacon, so the
  /// rider hears one short phrase and then follows the tone. Facing it gives the lock
  /// buzz. A LiDAR door within arm's reach ends the walk.
  @discardableResult
  public func observeDoor(_ sighting: DoorSighting) -> Bool {
    guard state == .confirm, sighting.confidence >= thresholds.minSightingConfidence else {
      return false
    }
    lastDoorSighting = sighting

    if sighting.kind == .door, let meters = sighting.meters,
      meters <= thresholds.doorReachedWithinMeters,
      abs(sighting.offsetDegrees) <= thresholds.doorReachedWithinDegrees
    {
      arrive()
      return true
    }

    let isNew =
      doorKindLastSeen[sighting.kind].map {
        sighting.timestamp.timeIntervalSince($0) >= thresholds.doorSightingNewAfterSeconds
      } ?? true
    doorKindLastSeen[sighting.kind] = sighting.timestamp
    let facing = abs(sighting.offsetDegrees) <= thresholds.facingDoorWithinDegrees

    if isNew {
      facingDoorSaid = facing
      feedback.emit(Self.announcement(for: sighting))
    } else {
      feedback.emit(.doorAim(offsetDegrees: sighting.offsetDegrees))
      if facing, !facingDoorSaid {
        facingDoorSaid = true
        feedback.emit(.facingDoor(meters: sighting.meters))
      } else if abs(sighting.offsetDegrees) > thresholds.facingDoorWithinDegrees * 2 {
        // Turned well away again, so facing it later is worth saying again.
        facingDoorSaid = false
      }
    }
    return true
  }

  private static func announcement(for sighting: DoorSighting) -> FeedbackEvent {
    switch sighting.kind {
    case .door:
      if abs(sighting.offsetDegrees) < 10 { return .facingDoor(meters: sighting.meters) }
      return .doorDetected(offsetDegrees: sighting.offsetDegrees, meters: sighting.meters ?? 0)
    case .clue(let clue):
      return .doorClueSeen(clue, offsetDegrees: sighting.offsetDegrees)
    }
  }

  private func resetDoorFinder() {
    lastDoorSighting = nil
    doorKindLastSeen = [:]
    facingDoorSaid = false
    doorCloseSaid = false
    lastBuildingConfirmed = nil
  }

  private func arrive() {
    state = .arrived
    feedback.emit(.arrival)
    // The trip is over; nothing to resume.
    store?.clear()
  }

  /// Low light, no camera permission, pocket mode. Said out loud, because a rider who
  /// expected the building check has to know it isn't running (plan section 7).
  public func cameraCheckUnavailable(_ problem: CameraCheckProblem) {
    feedback.emit(.cameraCheckUnavailable(problem))
  }

  // MARK: - The walk

  /// Called for every position update while guiding. Heading is nil when the compass
  /// isn't usable, in which case orientation can't be judged and the state holds.
  public func update(position: GuidancePosition, heading: HeadingReadout?) {
    guard let target else { return }
    lastPosition = position
    let distance = Geo.distanceMeters(
      lat1: position.latitude, lon1: position.longitude, lat2: target.lat, lon2: target.lon)
    metersToDoor = distance
    distanceHistory.append((position.timestamp, distance))
    distanceHistory.removeAll {
      position.timestamp.timeIntervalSince($0.at) > thresholds.progressWindowSeconds * 2
    }

    let aim = targetCoordinate ?? (target.lat, target.lon)
    let bearingToAim = Geo.bearingDegrees(
      lat1: position.latitude, lon1: position.longitude, lat2: aim.lat, lon2: aim.lon)
    // Every direction in the app goes through the corrected heading, so a camera
    // sighting improves orienting, guiding, the lost check and the first-steps check
    // at once (plan section 7: the building check re-anchors the guidance).
    let offset = heading.map {
      Geo.relativeAngle(
        heading: $0.trueHeadingDegrees - headingBiasDegrees, target: bearingToAim)
    }
    offsetDegrees = offset

    if sideUnconfirmed, [.orient, .guide, .confirm, .lost].contains(state) {
      if riderIsClearlyOnDoorSide(position) {
        // Worked out by the app, not asked of the rider.
        sideUnconfirmed = false
        riderIsOnDoorSide = true
        feedback.emit(.sideOfStreet(.sameSide, sideContext()))
        persist()
      } else if lineToDoorCrossesStreet(from: position, to: aim) {
        // Possibly across the road: never point there. No turn cue, no beacon.
        offsetDegrees = nil
        lockedSince = nil
        if sideUnknownSaidAt.map({
          position.timestamp.timeIntervalSince($0) >= thresholds.sideUnknownRepeatSeconds
        }) ?? true {
          sideUnknownSaidAt = position.timestamp
          feedback.emit(.askSideOfStreet(sideContext()))
        }
        return
      }
    }

    switch state {
    case .orient:
      updateOrient(position: position, offset: offset, distance: distance)
    case .guide:
      updateGuide(position: position, offset: offset, distance: distance)
    case .confirm:
      updateConfirm(position: position, distance: distance)
    case .lost:
      updateLost(offset: offset, at: position.timestamp)
    case .setup, .riding, .arrival, .arrived:
      break
    }
  }

  /// Turning on the spot until the heading holds within 15° for a second.
  private func updateOrient(position: GuidancePosition, offset: Double?, distance: Double) {
    guard let offset else { return }
    guard abs(offset) <= thresholds.lockWithinDegrees else {
      lockedSince = nil
      feedback.emit(.direction(offsetDegrees: offset))
      return
    }
    let since = lockedSince ?? position.timestamp
    lockedSince = since
    guard position.timestamp.timeIntervalSince(since) >= thresholds.lockHoldSeconds else {
      return
    }
    // Locked on. The anchor is set here, not at startGuidance(), because this is where
    // the rider actually starts walking from.
    anchor = position
    breadcrumbs = [position]
    offRouteSince = nil
    firstStepsChecked = false
    state = .guide
    feedback.emit(.bearingLock(metersToDoor: distance))
    persist()
  }

  private func updateGuide(position: GuidancePosition, offset: Double?, distance: Double) {
    recordBreadcrumb(position)

    // The first-steps check (plan section 5, ADR 0011). The starting point can be
    // 5–15 m off, so after a few meters the app compares where the rider actually went
    // with where it expected them to go, and admits it when they disagree.
    if !firstStepsChecked, let anchor {
      let walked = Geo.distanceMeters(
        lat1: anchor.latitude, lon1: anchor.longitude, lat2: position.latitude,
        lon2: position.longitude)
      // GPS wanders a few meters standing still, so "walked 5 m" alone is noise. Wait
      // until the rider has moved clearly further than the fix's error.
      let needed = max(
        thresholds.firstStepsAfterMeters, 2 * (position.horizontalAccuracyMeters ?? 10))
      if walked >= needed {
        firstStepsChecked = true
        let startDistance = Geo.distanceMeters(
          lat1: anchor.latitude, lon1: anchor.longitude, lat2: target!.lat, lon2: target!.lon)
        let progress = startDistance - distance
        if progress < walked * thresholds.firstStepsMinProgressRatio {
          lastLostReason =
            "First steps: walked \(Int(walked)) m but only \(Int(progress)) m closer to the door"
          enterLost(reason: .directionUncertain)
          return
        }
      }
    }

    if distance <= thresholds.confirmWithinMeters {
      state = .confirm
      doorCloseSaid = false
      lastDoorSighting = nil
      feedback.emit(.finalApproach(metersToDoor: distance, brief()))
      persist()
      return
    }

    // Spoken distances at 60 ft and 30 ft, each said once.
    for callout in thresholds.distanceCalloutsMeters
    where distance <= callout && !calloutsSpoken.contains(callout) {
      calloutsSpoken.insert(callout)
      feedback.emit(.distance(meters: distance))
    }

    // Badly off course for long enough counts as lost, but only if the rider isn't
    // getting closer: walking along the sidewalk towards a door round the corner is
    // "off" by angle and still exactly right.
    guard let offset else { return }
    if isGettingCloser(at: position.timestamp) {
      offRouteSince = nil
      return
    }
    if abs(offset) > thresholds.lostOffByDegrees {
      let since = offRouteSince ?? position.timestamp
      offRouteSince = since
      if position.timestamp.timeIntervalSince(since) >= thresholds.lostAfterSeconds {
        lastLostReason =
          "Off course: facing \(Int(abs(offset)))° from the door for \(Int(thresholds.lostAfterSeconds)) s and not getting closer"
        enterLost(reason: .lost)
      }
    } else {
      offRouteSince = nil
    }
  }

  private func updateConfirm(position: GuidancePosition, distance: Double) {
    // GPS can say "about here", not "here". Say so once and let the camera, or the
    // rider's hand, find the door.
    let closeWithin = max(
      thresholds.arrivedWithinMeters,
      min(position.horizontalAccuracyMeters ?? 0, thresholds.doorCloseMaxMeters))
    if distance <= closeWithin, !doorCloseSaid {
      doorCloseSaid = true
      feedback.emit(.doorShouldBeClose)
    }
    // Drifted back out: GPS noise, or the rider walked past. Hysteresis keeps this from
    // flapping between states.
    if distance > thresholds.leaveConfirmBeyondMeters {
      state = .guide
      persist()
    }
  }

  /// Lost recovers by turning back towards the last breadcrumb, which is somewhere the
  /// rider has actually stood.
  private func updateLost(offset: Double?, at moment: Date) {
    guard let offset else { return }
    guard abs(offset) <= thresholds.recoverWithinDegrees else {
      recoveringSince = nil
      return
    }
    let since = recoveringSince ?? moment
    recoveringSince = since
    guard moment.timeIntervalSince(since) >= thresholds.recoverHoldSeconds else { return }
    recoveringSince = nil
    lockedSince = nil
    state = .orient
    persist()
  }

  private func enterLost(reason: FeedbackEvent) {
    state = .lost
    offRouteSince = nil
    recoveringSince = nil
    feedback.emit(reason)
    persist()
  }

  /// Has the distance to the door shrunk by `progressMinMeters` over the last
  /// `progressWindowSeconds`?
  private func isGettingCloser(at moment: Date) -> Bool {
    guard let now = distanceHistory.last,
      let then = distanceHistory.last(where: {
        moment.timeIntervalSince($0.at) >= thresholds.progressWindowSeconds
      })
    else { return false }
    return then.meters - now.meters >= thresholds.progressMinMeters
  }

  private func recordBreadcrumb(_ position: GuidancePosition) {
    guard let last = breadcrumbs.last else {
      breadcrumbs = [position]
      return
    }
    let moved = Geo.distanceMeters(
      lat1: last.latitude, lon1: last.longitude, lat2: position.latitude,
      lon2: position.longitude)
    guard moved >= thresholds.breadcrumbEveryMeters else { return }
    breadcrumbs.append(position)
    // A trip's worth is plenty; this is a trail home, not a history.
    if breadcrumbs.count > 50 { breadcrumbs.removeFirst() }
  }

  // MARK: - Persistence (relaunch mid-trip)

  public var snapshot: SessionSnapshot? {
    guard let bundle else { return nil }
    return SessionSnapshot(
      state: state, address: address, destinationId: bundle.destinationId,
      riderIsOnDoorSide: riderIsOnDoorSide, breadcrumbs: breadcrumbs, updatedAt: Date())
  }

  /// Pick up where a killed app left off.
  ///
  /// Two rules from the plan: a relaunch during the **ride** has no car track, so the
  /// side of street becomes unknown and the rider is asked again; a relaunch during the
  /// **walk** can't trust its old heading lock, so it re-anchors at the last breadcrumb
  /// and goes back to .orient rather than pretending to still be on course.
  public func resume(from snapshot: SessionSnapshot, bundle: ResolveResult) {
    self.bundle = bundle
    address = snapshot.address
    breadcrumbs = snapshot.breadcrumbs
    riderIsOnDoorSide = snapshot.riderIsOnDoorSide
    lockedSince = nil
    offRouteSince = nil
    recoveringSince = nil
    firstStepsChecked = false
    calloutsSpoken = []
    anchor = nil

    switch snapshot.state {
    case .riding, .arrival:
      // No car track survived, so the side of street is a guess again.
      riderIsOnDoorSide = nil
      state = snapshot.state
      feedback.emit(.askSideOfStreet(sideContext()))
    case .orient, .guide, .confirm, .lost:
      state = .orient
      feedback.emit(.startingGuidance)
    case .setup, .arrived:
      state = snapshot.state
    }
    persist()
  }

  private func persist() {
    guard let snapshot else { return }
    store?.save(snapshot)
  }

  // MARK: - Helpers

  private func brief() -> DestinationBrief {
    bundle?.destinationBrief(metersToDoor: metersToDoor)
      ?? DestinationBrief(band: "facade", metersToDoor: metersToDoor)
  }

  // MARK: - Side of street while walking

  /// The street centerline in local meters around `origin`, or nil without one.
  private func localCenterline(around origin: GuidancePosition)
    -> (frame: LocalFrame, points: [(east: Double, north: Double)])?
  {
    guard let line = bundle?.streetSide?.centerline, line.count >= 2 else { return nil }
    let frame = LocalFrame(originLat: origin.latitude, originLon: origin.longitude)
    let points = line.compactMap { pair -> (east: Double, north: Double)? in
      guard pair.count >= 2 else { return nil }
      return frame.toLocal(lat: pair[1], lon: pair[0])
    }
    return points.count >= 2 ? (frame, points) : nil
  }

  /// Does the straight line from the rider to the door cross the street centerline?
  /// With no centerline in the bundle there's nothing to check against: say yes, so an
  /// unknown side never turns into a direction across a road.
  private func lineToDoorCrossesStreet(
    from position: GuidancePosition, to aim: (lat: Double, lon: Double)
  ) -> Bool {
    guard let (frame, line) = localCenterline(around: position) else { return true }
    let door = frame.toLocal(lat: aim.lat, lon: aim.lon)
    let rider = (east: 0.0, north: 0.0)
    for i in 0..<(line.count - 1) where Self.segmentsIntersect(rider, door, line[i], line[i + 1]) {
      return true
    }
    return false
  }

  /// GPS puts the rider on the door's side of the centerline, far enough from it that
  /// the fix's error can't flip the answer.
  private func riderIsClearlyOnDoorSide(_ position: GuidancePosition) -> Bool {
    guard let doorSide = bundle?.streetSide?.doorSideOfRoad.lowercased(),
      doorSide == "left" || doorSide == "right",
      let (_, line) = localCenterline(around: position)
    else { return false }
    // Nearest centerline segment to the rider (who is at the local origin).
    var best: (distance: Double, side: Side)?
    for i in 0..<(line.count - 1) {
      let a = line[i], b = line[i + 1]
      let dir = (east: b.east - a.east, north: b.north - a.north)
      let lengthSquared = dir.east * dir.east + dir.north * dir.north
      guard lengthSquared > 0 else { continue }
      let t = max(0, min(1, -(a.east * dir.east + a.north * dir.north) / lengthSquared))
      let nearest = (east: a.east + t * dir.east, north: a.north + t * dir.north)
      let distance = hypot(nearest.east, nearest.north)
      if best == nil || distance < best!.distance {
        best = (distance, Geo.side(direction: dir, toPoint: (-a.east, -a.north)))
      }
    }
    guard let best else { return false }
    let margin = max(thresholds.sideFromGPSMinMeters, position.horizontalAccuracyMeters ?? .infinity)
    return best.side.rawValue == doorSide && best.distance >= margin
  }

  private static func segmentsIntersect(
    _ p1: (east: Double, north: Double), _ p2: (east: Double, north: Double),
    _ q1: (east: Double, north: Double), _ q2: (east: Double, north: Double)
  ) -> Bool {
    func cross(_ o: (east: Double, north: Double), _ a: (east: Double, north: Double),
      _ b: (east: Double, north: Double)) -> Double {
      (a.east - o.east) * (b.north - o.north) - (a.north - o.north) * (b.east - o.east)
    }
    let d1 = cross(q1, q2, p1), d2 = cross(q1, q2, p2)
    let d3 = cross(p1, p2, q1), d4 = cross(p1, p2, q2)
    return (d1 > 0) != (d2 > 0) && (d3 > 0) != (d4 > 0)
  }

  private func sideContext() -> SideOfStreetContext {
    SideOfStreetContext(
      metersToDoor: metersToDoor,
      metersToCrossing: nil,
      entranceStreet: bundle?.streetSide?.entranceStreet,
      streetSideDescription: bundle?.streetSide.flatMap(StreetSideDescription.compassSide))
  }
}
