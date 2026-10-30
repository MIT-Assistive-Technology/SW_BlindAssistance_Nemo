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
  /// The door is across the street, or the way to it crosses a road: the screen offers
  /// "I'm across", or guidance would wait forever (S5).
  @Published public private(set) var isWaitingToCross = false

  private let session: NavigationSession
  private let location: LocationService
  private var cancellables = Set<AnyCancellable>()

  public init(session: NavigationSession, location: LocationService) {
    self.session = session
    self.location = location

    session.$state.sink { [weak self] in self?.state = $0 }.store(in: &cancellables)
    session.$metersToDoor.sink { [weak self] in self?.metersToDoor = $0 }.store(in: &cancellables)
    session.$offsetDegrees.sink { [weak self] in self?.offsetDegrees = $0 }
      .store(in: &cancellables)
    session.$riderIsOnDoorSide.combineLatest(session.$isWaitingAtRoad)
      .sink { [weak self] onDoorSide, atRoad in
        self?.isWaitingToCross = onDoorSide == false || atRoad
      }
      .store(in: &cancellables)

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
  /// This screen feeds the session positions, so guidance can start straight away.
  public func riderIsAcross() { session.riderIsAcross(startGuiding: true) }
  public func stop() { session.stop() }
  public func repeatGuidance() { session.repeatGuidance() }

  private func feed(_ snapshot: LocationSnapshot) {
    guard let coordinate = snapshot.coordinate else { return }
    hasFix = true
    session.update(
      position: GuidancePosition(
        latitude: coordinate.latitude,
        longitude: coordinate.longitude,
        horizontalAccuracyMeters: snapshot.horizontalAccuracy,
        timestamp: snapshot.timestamp),
      heading: snapshot.headingReadout)
  }
}
