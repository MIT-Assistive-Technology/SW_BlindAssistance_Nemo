//  RideViewModel.swift
//  nemo-software
//
//  The ride screen: load the destination bundle (FE-11), track the car (FE-13), and
//  answer "did the car drop you on the door's side of the street?" when it stops.
//
//  The decision itself is `SideOfStreetResolver`, which is pure and unit tested. This
//  type only moves data between the sensors, the bundle and FeedbackKit — the handover
//  point for the session state machine (FE-10).
//

import Combine
import CoreLocation
import Foundation

@MainActor
public final class RideViewModel: ObservableObject {
  /// Pilot destination, so the screen does something useful before the destination
  /// picker exists (FE-9).
  @Published public var address = "77 Massachusetts Ave, Cambridge, MA"
  @Published public private(set) var bundle: ResolveResult?
  @Published public private(set) var status = "No destination loaded."
  @Published public private(set) var cacheNote: String?
  @Published public private(set) var isLoading = false
  @Published public private(set) var sideAnswer: SideOfStreetAnswer?
  /// What the rider said when the app had to ask (nil = not asked or not answered).
  @Published public private(set) var riderSaysSameSide: Bool?
  /// The phone noticed a stop and is asking whether this is the drop-off.
  @Published public private(set) var isAskingIfOutOfCar = false
  /// Set once the rider says they're out. Nothing the phone senses sets this.
  @Published public private(set) var isOutOfCar = false
  /// A sensor or permission problem, in the same words it was spoken in.
  @Published public private(set) var problem: String?

  private let location: LocationService
  private let feedback: FeedbackKit
  private let client: CachingEntranceClient
  private let session: NavigationSession?
  /// Stops further than this from the destination don't raise the question. "I'm out of
  /// the car" still works anywhere, so a driver who has to stop early costs nothing.
  public var maxPromptDistanceMeters: Double = 150

  private let resolver = SideOfStreetResolver()
  private var cancellables = Set<AnyCancellable>()
  /// The stop the rider has already been asked about, so a long red light isn't
  /// announced over and over.
  private var askedAboutStop: Date?
  /// The distance quoted in the question, so the screen shows what was said.
  private var promptedDistanceMeters: Double?

  public init(
    location: LocationService,
    feedback: FeedbackKit,
    client: CachingEntranceClient,
    session: NavigationSession? = nil
  ) {
    self.location = location
    self.feedback = feedback
    self.client = client
    // The trip state machine (FE-10). Optional so the ride screen still works on its
    // own, but when it's there the drop-off hands straight over to guidance.
    self.session = session

    // A stop after driving is only a hint: to GPS a red light looks exactly like a
    // drop-off. So the phone asks, and `confirmOutOfCar()` is what actually decides.
    location.$carTrack
      .sink { [weak self] track in self?.considerStop(in: track) }
      .store(in: &cancellables)

    // Sensor problems have to be audible from whichever screen the rider is on, not
    // only from the heading screen.
    location.$lastFailure
      .removeDuplicates()
      .sink { [weak self] failure in
        guard let self, let failure else { return }
        problem = failure
        if failure == Phrases.locationPermissionDenied {
          feedback.emit(.locationPermissionDenied)
        }
      }
      .store(in: &cancellables)

    // Permission granted after the prompt: now the ride really is being tracked.
    location.$authorizationStatus
      .removeDuplicates()
      .sink { [weak self] status in
        guard let self, location.isTrackingRide else { return }
        if status == .authorizedWhenInUse || status == .authorizedAlways {
          problem = nil
          feedback.emit(.rideTracking(started: true))
        }
      }
      .store(in: &cancellables)
  }

  public var isTrackingRide: Bool { location.isTrackingRide }

  public var trackSummary: String {
    let track = location.carTrack
    guard let latest = track.latest else {
      return location.isTrackingRide ? "Waiting for the first fix…" : "Not tracking."
    }
    let speed = max(latest.speedMetersPerSecond, 0)
    let course =
      latest.courseDegrees >= 0 ? "\(Int(latest.courseDegrees.rounded()))°" : "unknown"
    return String(
      format: "%d samples · %.1f m/s · course %@", track.samples.count, speed, course)
  }

  /// The same thing in words, because VoiceOver reads "·" and "m/s" badly.
  public var trackSummaryAccessibility: String {
    let track = location.carTrack
    guard let latest = track.latest else { return trackSummary }
    let speed = Int(max(latest.speedMetersPerSecond, 0).rounded())
    let course =
      latest.courseDegrees >= 0
      ? "course \(Int(latest.courseDegrees.rounded())) degrees" : "course unknown"
    return "\(track.samples.count) samples, \(speed) metres per second, \(course)."
  }

  public var briefText: String? {
    guard let bundle else { return nil }
    return Phrases.destinationBrief(bundle.destinationBrief(metersToDoor: metersToDoor()))
  }

  /// Exactly what the rider was told, so what's on screen and what was spoken can't
  /// drift apart. The developer-facing reason is separate (`sideReason`).
  public var sideText: String? {
    guard let answer = sideAnswer else { return nil }
    return SpeechChannel.phrase(for: .sideOfStreet(answer, sideContext()))
  }

  /// Why the app wouldn't answer. For testers and trial logs, never spoken.
  public var sideReason: String? {
    guard case .unknown(let reason) = sideAnswer else { return nil }
    return reason.rawValue
  }

  public var needsSideAnswerFromRider: Bool { sideAnswer?.isKnown == false }

  /// The drop-off question, in the words it was spoken in.
  public var dropOffPrompt: String {
    Phrases.possibleDropOff(metersToDoor: promptedDistanceMeters)
  }

  // MARK: - Destination (FE-11)

  public func load() async {
    guard !isLoading else { return }
    isLoading = true
    // Looking up an address takes seconds. Say so, or there's no way to know the tap
    // registered without watching the button change.
    feedback.emit(.lookingUpDestination)
    defer { isLoading = false }
    do {
      // The client falls back to the phone's copy by itself, and says which it used.
      let resolved = try await client.resolveBundle(address: address)
      bundle = resolved.result
      status =
        resolved.fromCache
        ? "Using the copy saved on this phone."
        : (resolved.result.target?.label ?? "Street-facing side")
      noteCacheAge()
      session?.setDestination(resolved.result, address: address)
      speakBrief()
      if !resolved.savedForOffline {
        feedback.emit(.bundleNotSavedForOffline)
      }
    } catch {
      bundle = nil
      cacheNote = nil
      status = Phrases.lookupFailed(error)
      // A failure the rider can't see has to be a failure they can hear.
      feedback.emit(.destinationLookupFailed(LookupFailure(error)))
    }
  }

  /// `force` when the rider asked again, so the chatter guard can't swallow it.
  public func speakBrief(force: Bool = false) {
    guard let bundle else {
      feedback.emit(.noDestinationLoaded, force: force)
      return
    }
    feedback.emit(
      .destinationBrief(bundle.destinationBrief(metersToDoor: metersToDoor())), force: force)
  }

  /// "Repeat": say the side-of-street answer again, or the question if it's unknown.
  public func repeatSideAnswer() {
    guard let answer = sideAnswer else {
      speakBrief(force: true)
      return
    }
    feedback.emit(.sideOfStreet(answer, sideContext()), force: true)
  }

  private func noteCacheAge() {
    guard let cached = client.cached(for: address) else {
      cacheNote = nil
      return
    }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    cacheNote = "Saved on this phone \(formatter.localizedString(for: cached.fetchedAt, relativeTo: Date()))."
  }

  // MARK: - The ride (FE-13)

  /// Start the sensors while the screen is up, so there's a position to measure the
  /// walk from. Permission is asked here, at the moment of use.
  public func onAppear() {
    location.start()
  }

  public func onDisappear() {
    if !location.isTrackingRide { location.stop() }
  }

  public func startRide() {
    sideAnswer = nil
    riderSaysSameSide = nil
    isAskingIfOutOfCar = false
    isOutOfCar = false
    askedAboutStop = nil
    location.startRideTracking()
    session?.startRiding()
    // Don't claim to be tracking when location is off: the rider would hear a promise
    // the app can't keep, and only find out at the drop-off.
    if location.isAuthorized {
      feedback.emit(.rideTracking(started: true))
    } else if location.authorizationStatus == .denied
      || location.authorizationStatus == .restricted
    {
      feedback.emit(.locationPermissionDenied)
    }
    // .notDetermined: iOS is showing its own prompt, which speaks for itself. The
    // authorization subscription announces tracking once permission is granted.
  }

  public func stopRide() {
    isAskingIfOutOfCar = false
    location.stopRideTracking()
    feedback.emit(.rideTracking(started: false))
  }

  /// The rider says they're out of the car. This is the **authoritative** drop-off
  /// signal: nothing the phone senses is as reliable, and acting on a guess could mean
  /// telling someone to open a door into traffic. Available any time during the ride,
  /// so the rider never has to wait for the app to notice.
  public func confirmOutOfCar() {
    isOutOfCar = true
    isAskingIfOutOfCar = false
    // Measure from the stop, not from the tap: the course that matters was recorded
    // just before the car stopped, and the rider may tap a minute later.
    let stopTime = askedAboutStop ?? location.carTrack.stopDetected(asOf: Date()) ?? Date()
    checkSideOfStreet(stopTime: stopTime)
    // Hand over to the trip state machine: Riding -> Arrival. It decides whether the
    // walk may start, and refuses while the door is across the road.
    session?.riderIsOutOfCar(isOnDoorSide: sideAnswer.flatMap(Self.isOnDoorSide))
    // The ride is over, so stop draining the battery on background location.
    location.stopRideTracking()
  }

  /// "Not yet": a red light or traffic. The same stop won't be raised again, but the
  /// next one after the car moves will be.
  public func stillInCar() {
    isAskingIfOutOfCar = false
  }

  /// A stop the phone noticed. It only ever asks; it never decides.
  ///
  /// The detect → ask → "not yet" → detect again cycle:
  ///   1. A stop is detected. Ask once, with the distance to the entrance.
  ///   2. "Not yet" clears the question but remembers this stop, so a long red light
  ///      isn't announced over and over.
  ///   3. The car moves — at any speed, not just driving speed — which clears the
  ///      memory. `stopDetected` then produces a new timestamp for the next stop.
  ///   4. Ask again. Repeat for the whole ride.
  private func considerStop(in track: CarCourseTrack) {
    guard location.isTrackingRide, !isOutOfCar else { return }
    guard let stop = track.stopDetected(asOf: Date()) else {
      // Moving again, so whatever was asked about wasn't the drop-off. Any movement
      // counts: a car creeping forward in traffic never reaches driving speed.
      if track.latest?.isMoving == true {
        askedAboutStop = nil
        isAskingIfOutOfCar = false
      }
      return
    }
    guard askedAboutStop != stop else { return }

    // The only filter the sensors allow. Nothing distinguishes a red light from a
    // drop-off, but a stop half a kilometre from the destination is almost certainly
    // not one, and a 20-minute ride has a lot of red lights. When the distance isn't
    // known the question is still asked: it's a question, not an instruction.
    let metersAway = metersFromDestination(track)
    if let metersAway, metersAway > maxPromptDistanceMeters { return }

    askedAboutStop = stop
    promptedDistanceMeters = metersAway
    isAskingIfOutOfCar = true
    feedback.emit(.possibleDropOff(metersToDoor: metersAway))
  }

  /// Run the side-of-street rule for a given stop. Called by `confirmOutOfCar()`, and
  /// available to the session state machine (FE-10).
  public func checkSideOfStreet(stopTime: Date = Date()) {
    // Without a destination there's nothing to be on the same side as, and "which side
    // of the street are you on?" would be an unanswerable question.
    guard bundle != nil else {
      feedback.emit(.noDestinationLoaded)
      status = Phrases.noDestinationLoaded
      return
    }
    let answer = resolver.resolve(
      streetSide: bundle?.streetSide,
      track: location.carTrack,
      stopTime: stopTime)
    sideAnswer = answer
    feedback.emit(.sideOfStreet(answer, sideContext()))
  }

  /// The rider's answer to "are you on the sidewalk with the building side to your
  /// right?". It beats the app's guess, and is what the first-steps check confirms.
  public func answerSideQuestion(sameSide: Bool) {
    riderSaysSameSide = sameSide
    let answer: SideOfStreetAnswer = sameSide ? .sameSide : .acrossStreet
    sideAnswer = answer
    session?.riderIsOnDoorSide(sameSide)
    feedback.emit(.sideOfStreet(answer, sideContext()), force: true)
  }

  /// "I'm across the street now": the door's side is reachable, so guidance may start.
  /// Said back out loud, because a tap with no answer is indistinguishable from a broken
  /// app. Guidance itself starts from the Walk screen, which feeds it positions.
  public func riderCrossedStreet() {
    riderSaysSameSide = true
    sideAnswer = .sameSide
    if let session {
      session.riderIsAcross(startGuiding: false)
    } else {
      feedback.emit(.readyToStartGuidance, force: true)
    }
  }

  /// The door is across the street, so the screen offers "I'm across" (S5): without it
  /// guidance would wait forever.
  public var isWaitingToCross: Bool {
    if case .some(.acrossStreet) = sideAnswer { return true }
    return false
  }

  private static func isOnDoorSide(_ answer: SideOfStreetAnswer) -> Bool? {
    switch answer {
    case .sameSide: return true
    case .acrossStreet: return false
    case .unknown: return nil
    }
  }

  // MARK: - Helpers

  /// Everything the side-of-street phrase needs, including the street name, so the
  /// question the rider is asked can be matched against what the driver said.
  private func sideContext() -> SideOfStreetContext {
    SideOfStreetContext(
      metersToDoor: metersToDoor(),
      metersToCrossing: metersToCrossing(),
      entranceStreet: bundle?.streetSide?.entranceStreet,
      streetSideDescription: bundle?.streetSide.flatMap(StreetSideDescription.compassSide))
  }

  /// How far the car is from the entrance, measured from the newest ride sample.
  private func metersFromDestination(_ track: CarCourseTrack) -> Double? {
    guard let bundle, let latest = track.latest else { return nil }
    return bundle.metersToTarget(fromLat: latest.latitude, fromLon: latest.longitude)
  }

  private func metersToDoor() -> Double? {
    guard let coordinate = location.currentSnapshot.coordinate, let bundle else { return nil }
    return bundle.metersToTarget(
      fromLat: coordinate.latitude, fromLon: coordinate.longitude)
  }

  private func metersToCrossing() -> Double? {
    guard let coordinate = location.currentSnapshot.coordinate, let bundle else { return nil }
    return bundle.metersToNearestCrossing(
      fromLat: coordinate.latitude, fromLon: coordinate.longitude)
  }
}
