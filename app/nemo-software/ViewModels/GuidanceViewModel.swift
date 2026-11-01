//  GuidanceViewModel.swift
//  nemo-software
//
//  Feeds the trip state machine (FE-10) from the live sensors, and nothing else. All
//  the decisions are in `NavigationSession`, which is why they can be unit tested
//  against a recorded trace; this type only converts a `LocationSnapshot` into a
//  `GuidancePosition` and hands it over.
//

import Combine
import CoreLocation
import Foundation

@MainActor
public final class GuidanceViewModel: ObservableObject {
  @Published public private(set) var state: SessionState = .setup
  @Published public private(set) var metersToDoor: Double?
  @Published public private(set) var offsetDegrees: Double?
  @Published public private(set) var hasFix = false

  // Debug panel (testing only): what the app is working from right now.
  @Published public private(set) var debugGPS = "–"
  @Published public private(set) var debugHeading = "–"
  @Published public private(set) var debugBearing = "–"
  @Published public private(set) var debugLastSaid = "–"
  public var debugLostReason: String { session.lastLostReason ?? "–" }
  public var debugSide: String {
    switch session.riderIsOnDoorSide {
    case .some(true): return "door side"
    case .some(false): return "across the street"
    case .none: return session.sideUnconfirmed ? "unknown, working it out" : "unknown"
    }
  }

  /// Walking faster than this, with a course this accurate, steers by the direction
  /// of travel instead of the compass. Held upright at the chest, the compass can flip
  /// by 180° with a small tilt; the direction you're actually walking can't.
  private static let courseMinSpeed = 0.7  // m/s, a slow walk
  private static let courseMaxAccuracy = 30.0  // degrees

  private let session: NavigationSession
  private let location: LocationService
  private var saidWaitingForFix = false
  private let feedback: FeedbackKit?
  private var cancellables = Set<AnyCancellable>()

  public init(session: NavigationSession, location: LocationService, feedback: FeedbackKit? = nil) {
    self.session = session
    self.location = location
    self.feedback = feedback

    session.$state.sink { [weak self] in self?.state = $0 }.store(in: &cancellables)
    session.$metersToDoor.sink { [weak self] in self?.metersToDoor = $0 }.store(in: &cancellables)
    session.$offsetDegrees.sink { [weak self] in self?.offsetDegrees = $0 }
      .store(in: &cancellables)
    feedback?.onEmit = { [weak self] event in
      self?.debugLastSaid = SpeechChannel.phrase(for: event) ?? "(\(event))"
    }

    // Every position update drives one step of the machine.
    location.$currentSnapshot
      .sink { [weak self] snapshot in self?.feed(snapshot) }
      .store(in: &cancellables)
  }

  public var canStartGuidance: Bool { session.canStartGuidance }
  public var isGuiding: Bool {
    [.orient, .guide, .confirm, .lost].contains(state)
  }

  /// What the screen shows, and what VoiceOver reads.
  public var stateText: String {
    switch state {
    case .setup: return "No trip yet"
    case .riding: return "In the car"
    case .arrival: return "At the drop-off"
    case .orient: return "Turn until I say that's the direction"
    case .guide: return "Walking"
    case .confirm: return "Nearly at the door"
    case .arrived: return "At the door"
    case .lost: return "Off route"
    }
  }

  public var detailText: String {
    guard let metersToDoor else { return "Waiting for a position fix." }
    let distance = Phrases.distance(meters: metersToDoor)
    guard let offsetDegrees else { return "The door is \(distance) away." }
    return "The door is \(distance) away, \(Phrases.turn(offsetDegrees: offsetDegrees))."
  }

  public func onAppear() { location.start() }

  public func onDisappear() {
    // Keep the sensors on while a walk is in progress, even if the screen is left.
    if !isGuiding && !location.isTrackingRide { location.stop() }
  }

  public func start() { session.startGuidance() }
  public func stop() { session.stop() }
  public func repeatGuidance() { session.repeatGuidance() }

  private func feed(_ snapshot: LocationSnapshot) {
    guard snapshot.hasUsableFix, let coordinate = snapshot.coordinate else {
      // A bad fix would put the door hundreds of feet away in the wrong direction.
      // Hold guidance and say why, once, instead of guiding from it.
      hasFix = false
      if isGuiding, !saidWaitingForFix {
        saidWaitingForFix = true
        feedback?.emit(.waitingForLocation)
      }
      return
    }
    saidWaitingForFix = false
    hasFix = true
    let heading = steeringHeading(snapshot)
    updateDebug(snapshot, heading: heading)
    session.update(
      position: GuidancePosition(
        latitude: coordinate.latitude,
        longitude: coordinate.longitude,
        horizontalAccuracyMeters: snapshot.horizontalAccuracy,
        timestamp: snapshot.timestamp),
      heading: heading.readout)
  }

  /// Direction of travel while walking, the compass otherwise.
  private func steeringHeading(_ snapshot: LocationSnapshot)
    -> (readout: HeadingReadout?, source: String)
  {
    if let speed = snapshot.speedMetersPerSecond, speed >= Self.courseMinSpeed,
      let course = snapshot.courseDegrees, course >= 0,
      let accuracy = snapshot.courseAccuracyDegrees, accuracy >= 0,
      accuracy <= Self.courseMaxAccuracy
    {
      return (
        HeadingReadout(
          trueHeadingDegrees: course, accuracyDegrees: accuracy, timestamp: snapshot.timestamp),
        "walking direction"
      )
    }
    return (snapshot.headingReadout, "compass")
  }

  private func updateDebug(
    _ snapshot: LocationSnapshot, heading: (readout: HeadingReadout?, source: String)
  ) {
    debugGPS = snapshot.horizontalAccuracy.map { "±\(Int($0)) m" } ?? "–"
    if let readout = heading.readout {
      debugHeading =
        "\(Int(readout.trueHeadingDegrees))° ±\(Int(readout.accuracyDegrees))° (\(heading.source))"
    } else {
      debugHeading = "none (\(heading.source))"
    }
    if let coordinate = snapshot.coordinate, let target = session.target {
      let bearing = Geo.bearingDegrees(
        lat1: coordinate.latitude, lon1: coordinate.longitude, lat2: target.lat,
        lon2: target.lon)
      debugBearing = "\(Int(bearing))°"
    }
  }
}
