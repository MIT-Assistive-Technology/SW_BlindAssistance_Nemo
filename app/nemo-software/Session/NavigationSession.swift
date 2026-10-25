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
  /// Last ~10 m: door facts, and later the camera door check.
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
  public var confirmWithinMeters = 10.0
  /// Leaving .confirm again needs hysteresis, or GPS noise flaps the state.
  public var leaveConfirmBeyondMeters = 15.0
  public var arrivedWithinMeters = 3.0
  public var lostOffByDegrees = 60.0
  public var lostAfterSeconds = 5.0
  public var recoverWithinDegrees = 60.0
  public var recoverHoldSeconds = 2.0
  public var firstStepsAfterMeters = 5.0
  public var firstStepsOffByDegrees = 30.0
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

  /// Can the walk start? False while the door is across the road or the side is unknown.
  public var canStartGuidance: Bool {
    bundle != nil && riderIsOnDoorSide == true
  }

  /// Back Tap, or the Start button.
  public func startGuidance() {
    guard bundle != nil else {
      feedback.emit(.noDestinationLoaded)
      return
    }
    switch riderIsOnDoorSide {
    case .some(true):
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
      feedback.emit(.startingGuidance)
      persist()
    case .some(false):
      // Never guide, and never point a beacon, across a roadway.
      feedback.emit(.waitingToCrossStreet)
    case .none:
      feedback.emit(.askSideOfStreet(sideContext()))
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
    store?.clear()
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
      feedback.emit(.finalApproach(metersToDoor: metersToDoor, brief()), force: true)
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
    feedback.emit(
      .buildingConfirmed(text: sighting.text, offsetDegrees: offsetDegrees))
    return true
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

    switch state {
    case .orient:
      updateOrient(position: position, offset: offset, distance: distance)
    case .guide:
      updateGuide(position: position, offset: offset, distance: distance)
    case .confirm:
      updateConfirm(distance: distance)
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
      if walked >= thresholds.firstStepsAfterMeters {
        firstStepsChecked = true
        let walkedBearing = Geo.bearingDegrees(
          lat1: anchor.latitude, lon1: anchor.longitude, lat2: position.latitude,
          lon2: position.longitude)
        let expected = Geo.bearingDegrees(
          lat1: anchor.latitude, lon1: anchor.longitude, lat2: target!.lat, lon2: target!.lon)
        if abs(Geo.relativeAngle(heading: expected, target: walkedBearing))
          > thresholds.firstStepsOffByDegrees
        {
          enterLost(reason: .directionUncertain)
          return
        }
      }
    }

    if distance <= thresholds.confirmWithinMeters {
      state = .confirm
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

    // Badly off course for long enough counts as lost.
    guard let offset else { return }
    if abs(offset) > thresholds.lostOffByDegrees {
      let since = offRouteSince ?? position.timestamp
      offRouteSince = since
      if position.timestamp.timeIntervalSince(since) >= thresholds.lostAfterSeconds {
        enterLost(reason: .lost)
      }
    } else {
      offRouteSince = nil
    }
  }

  private func updateConfirm(distance: Double) {
    if distance <= thresholds.arrivedWithinMeters {
      state = .arrived
      feedback.emit(.arrival)
      // The trip is over; nothing to resume.
      store?.clear()
      return
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

  private func sideContext() -> SideOfStreetContext {
    SideOfStreetContext(
      metersToDoor: metersToDoor,
      metersToCrossing: nil,
      entranceStreet: bundle?.streetSide?.entranceStreet,
      streetSideDescription: bundle?.streetSide.flatMap(StreetSideDescription.compassSide))
  }
}
