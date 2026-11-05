//  TripViewModel.swift
//  nemo-software
//
//  The one rider screen. A blind rider can't hunt between Ride, Walk and Heading pages,
//  so the trip is a single screen whose one "next step" button always does the next
//  thing: load the destination, "I'm in the car", "I'm out of the car", and at the end
//  "I'm at the door". Guidance starts by itself once the rider is out of the car.
//
//  It owns no trip logic. The ride (`RideViewModel`), the walk (`GuidanceViewModel`) and
//  the state machine (`NavigationSession`) do the work; this only decides which of
//  their actions the screen offers right now.
//

import Combine
import Foundation

@MainActor
public final class TripViewModel: ObservableObject {
  /// The single action the screen offers at this point of the trip.
  public enum NextStep: Equatable {
    case loadDestination
    case inTheCar
    case outOfTheCar
    case acrossTheStreet
    case startGuiding
    case atTheDoor
    case finish
  }

  public let ride: RideViewModel
  public let guidance: GuidanceViewModel
  private let services: AppServices
  private var session: NavigationSession { services.session }
  private var cancellables = Set<AnyCancellable>()

  public init(services: AppServices) {
    self.services = services
    ride = RideViewModel(
      location: services.location, feedback: services.feedback,
      client: services.entranceClient, session: services.session)
    guidance = GuidanceViewModel(
      session: services.session, location: services.location, feedback: services.feedback)
    guidance.prefersARPose = { [weak services] in
      services?.arGuideIsTracking == true
    }

    // Redraw when any part of the trip changes.
    let changes: [AnyPublisher<Void, Never>] = [
      ride.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
      guidance.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
      services.session.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
      services.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
    ]
    Publishers.MergeMany(changes)
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in self?.objectWillChange.send() }
      .store(in: &cancellables)
  }

  public var state: SessionState { session.state }
  public var address: String {
    get { ride.address }
    set { ride.address = newValue }
  }
  public var unfinishedTrip: SessionSnapshot? { services.unfinishedTrip }
  public var hasDestination: Bool { session.target != nil }
  public var isTripActive: Bool { state != .setup || hasDestination }

  public var nextStep: NextStep? {
    guard unfinishedTrip == nil else { return nil }
    switch state {
    case .setup: return hasDestination ? .inTheCar : .loadDestination
    case .riding: return .outOfTheCar
    case .arrival: return session.riderIsOnDoorSide == false ? .acrossTheStreet : .startGuiding
    case .orient, .guide, .confirm, .lost: return .atTheDoor
    case .arrived: return .finish
    }
  }

  public var nextStepTitle: String {
    switch nextStep {
    case .loadDestination: return ride.isLoading ? "Loading…" : "Load entrance details"
    case .inTheCar: return "I'm in the car"
    case .outOfTheCar: return "I'm out of the car"
    case .acrossTheStreet: return "I'm across the street"
    case .startGuiding: return "Start guiding"
    case .atTheDoor: return "I'm at the door"
    case .finish: return "Finish trip"
    case nil: return ""
    }
  }

  public var nextStepHint: String {
    switch nextStep {
    case .loadDestination: return "Fetches the entrance details and saves them on this phone."
    case .inTheCar: return "Tap when your ride starts. The app follows the car to tell which side of the street you're dropped on."
    case .outOfTheCar: return "Tap once you're on the ground. Guidance to the entrance starts by itself."
    case .acrossTheStreet: return "Tap once you've crossed. Guidance to the entrance starts."
    case .startGuiding: return "Starts the walk to the entrance."
    case .atTheDoor: return "Tap when you've found the door. Ends the walk."
    case .finish: return "Ends the trip."
    case nil: return ""
    }
  }

  /// What the screen shows at the top, and what VoiceOver reads first.
  public var headline: String {
    if unfinishedTrip != nil { return "Unfinished trip" }
    switch state {
    case .setup: return hasDestination ? "Ready for your ride" : "Where are you going?"
    case .riding: return "In the car"
    case .arrival: return "At the drop-off"
    case .orient: return "Turn until I say that's the direction"
    case .guide: return "Walking to the entrance"
    case .confirm: return "Looking for the door"
    case .arrived: return "At the door"
    case .lost: return "Off route"
    }
  }

  public var detail: String {
    if let trip = unfinishedTrip { return trip.address }
    switch state {
    case .setup:
      return ride.briefText ?? ride.status
    case .riding:
      return ride.isAskingIfOutOfCar ? ride.dropOffPrompt : ride.address
    case .arrival:
      return ride.sideText ?? "Working out where the entrance is."
    case .confirm:
      if let sighting = session.lastDoorSighting,
        Date().timeIntervalSince(sighting.timestamp) < 6
      {
        return Self.describe(sighting)
      }
      return "Hold the phone up, camera facing forward. " + guidance.detailText
    case .orient, .guide, .lost:
      return guidance.detailText
    case .arrived:
      return Phrases.arrivedAtDoor
    }
  }

  // MARK: - Actions

  public func performNextStep() {
    switch nextStep {
    case .loadDestination:
      // Location is asked for here, at the moment of use, not at launch.
      services.location.start()
      Task { await ride.load() }
    case .inTheCar:
      services.location.start()
      ride.startRide()
    case .outOfTheCar:
      ride.confirmOutOfCar()
      // Straight into the walk. The session refuses if the door is across the road,
      // and the side-of-street answer just spoken says so.
      if session.canStartGuidance { session.startGuidance() }
    case .acrossTheStreet:
      ride.riderCrossedStreet()
      session.startGuidance()
    case .startGuiding:
      session.startGuidance()
    case .atTheDoor:
      session.riderIsAtDoor()
    case .finish:
      endTrip()
    case nil:
      break
    }
  }

  /// "Where am I / Repeat": the current state again, whatever the stage.
  public func whereAmI() {
    if state == .setup, !hasDestination {
      services.feedback.emit(.noDestinationLoaded, force: true)
      return
    }
    session.repeatGuidance()
  }

  public func endTrip() {
    services.endTrip()
    if !services.location.isTrackingRide { services.location.stop() }
  }

  public func resumeTrip() {
    services.location.start()
    services.resumeUnfinishedTrip()
  }

  public func stillInCar() { ride.stillInCar() }

  private static func describe(_ sighting: DoorSighting) -> String {
    switch sighting.kind {
    case .door:
      return Phrases.doorDetected(offsetDegrees: sighting.offsetDegrees, meters: sighting.meters)
    case .clue(let clue):
      return Phrases.doorClueSeen(clue, offsetDegrees: sighting.offsetDegrees)
    }
  }
}
