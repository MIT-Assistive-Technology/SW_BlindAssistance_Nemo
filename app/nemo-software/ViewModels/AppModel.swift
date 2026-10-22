//  AppModel.swift
//  nemo-software
//
//  The composition root. Owns the sensors, feedback and the trip, and wires them:
//    LocationService / ARGuide  --SessionInput-->  NavigationSession
//    NavigationSession          --SessionEffect--> FeedbackKit (say), ARGuide (tracking,
//                                                  camera), persistence
//  It also steers the beacon from each pose and the session's target, and saves the
//  session (the reducer is Codable) and the rider's profile so a relaunch resumes.
//  If the app was closed during the ride there is no car track, so the side of street is
//  unknown and the session asks.
//
//  A shared instance so App Intents (Siri, Back Tap) reach the same trip.
//

import AppIntents
import Combine
import CoreLocation
import Foundation
import UIKit

final class AppModel: ObservableObject {
  static let shared = AppModel()

  // MARK: Published UI state

  @Published var profile: FeedbackProfile {
    didSet { profileChanged(from: oldValue) }
  }
  @Published private(set) var session: NavigationSession?
  /// The last phrase spoken, for the session screen (same words the rider heard).
  @Published private(set) var status = ""
  @Published private(set) var savedPlaces: [SavedPlace] = SavedPlacesFile.load()
  @Published private(set) var pilotEntries: [BundleStore.Entry] = []
  @Published private(set) var isBusy = false
  @Published private(set) var isInCar = false
  /// One line about the last search or download, for the destination and settings screens.
  @Published private(set) var notice: String?
  @Published var serverURL: String {
    didSet { UserDefaults.standard.set(serverURL, forKey: LiveEntranceClient.baseURLKey) }
  }

  var hasTrip: Bool { session != nil }

  // MARK: Parts

  let location = LocationService.shared
  let arGuide = ARGuide()
  let feedback = FeedbackKit()
  let store = BundleStore()
  /// Platform announcements (permission problems) that aren't guidance events.
  private let announcer = Speaker()
  private lazy var pipeline = PerceptionPipeline(
    detector: VisionObjectDetector(), locationProvider: location, speaker: Speaker())
  /// Debug camera screen (Settings). Only used while no trip runs, since ARKit owns the
  /// camera during guidance.
  private(set) lazy var cameraDebug = CameraViewModel(
    frameProvider: CameraFrameProvider(), pipeline: pipeline)

  private var sessionCancellables = Set<AnyCancellable>()
  private var lastPose: (lat: Double, lon: Double, heading: Double, accuracy: Double)?
  private var lastSaid: FeedbackEvent?
  private var wantsAR = false

  private static let profileKey = "feedbackProfile"
  private static let tripFile = "trip.json"

  private var client: EntranceClient {
    if let url = LiveEntranceClient.savedBaseURL() {
      return LiveEntranceClient(baseURL: url, store: store)
    }
    return StubEntranceClient()
  }

  // MARK: - Init and launch

  private init() {
    let defaults = UserDefaults.standard
    profile =
      defaults.data(forKey: Self.profileKey).flatMap {
        try? JSONDecoder().decode(FeedbackProfile.self, from: $0)
      } ?? FeedbackProfile.audioFirst
    serverURL = defaults.string(forKey: LiveEntranceClient.baseURLKey) ?? ""
    pilotEntries = store.entries
    UIDevice.current.isBatteryMonitoringEnabled = true

    feedback.update(profile: profile)
    location.useCourseAsHeading = !profile.cameraFirst
    location.onInput = { [weak self] input in self?.locationInput(input) }
    location.onProblem = { [weak self] problem in self?.announce(problem) }
    arGuide.onInput = { [weak self] input in self?.arInput(input) }
    arGuide.onLowLight = { [weak self] in self?.say(.warning(.lowLight)) }
    arGuide.frameProvider.delegate = pipeline

    restoreTrip()
  }

  // MARK: - Destination

  /// Loads the entrance for an address (phone first, then the service) and starts a trip.
  /// Returns false when there is no map data for it.
  @discardableResult
  func startTrip(address: String, name: String? = nil) async -> Bool {
    let query = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return false }
    isBusy = true
    defer { isBusy = false }
    let result: ResolveResult?
    if let cached = store.bundle(matchingAddress: query) {
      result = cached
    } else {
      result = try? await client.resolve(address: query)
    }
    guard let result else {
      notice = "No map data for that address."
      return false
    }
    notice = nil
    begin(with: result)
    return true
  }

  func startTrip(entry: BundleStore.Entry) {
    guard let result = store.bundle(id: entry.id) else {
      notice = "That building's map data is missing. Download pilot buildings again."
      return
    }
    begin(with: result)
  }

  func savePlace(name: String, address: String) {
    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !savedPlaces.contains(where: { $0.address == trimmed }) else { return }
    savedPlaces.append(SavedPlace(name: name.isEmpty ? trimmed : name, address: trimmed))
    savedPlacesChanged()
  }

  func deletePlace(_ place: SavedPlace) {
    savedPlaces.removeAll { $0.id == place.id }
    savedPlacesChanged()
  }

  func deleteAllPlaces() {
    savedPlaces = []
    savedPlacesChanged()
  }

  /// Downloads the pilot bundles from the entrance service (Settings, and "I'm in the car").
  func refreshBundles() async {
    guard let url = LiveEntranceClient.savedBaseURL() else {
      notice = "Add the entrance service address first."
      return
    }
    isBusy = true
    defer { isBusy = false }
    do {
      let saved = try await LiveEntranceClient(baseURL: url, store: store).refreshBundles()
      notice = saved == 0 ? "Pilot buildings are up to date." : "Downloaded \(saved) buildings."
    } catch {
      notice = "Couldn't reach the entrance service. Saved buildings still work offline."
    }
    pilotEntries = store.entries
  }

  // MARK: - Trip controls

  /// "I'm in the car": background location for the ride and the car's course.
  func imInTheCar() {
    guard hasTrip, !isInCar else { return }
    isInCar = true
    location.startCarTracking()
    if LiveEntranceClient.savedBaseURL() != nil {
      Task { await refreshBundles() }
    }
  }

  /// The big button and Back Tap: start guidance before walking, otherwise "Where am I".
  func primaryAction() {
    guard let session else { return }
    switch session.state {
    case .setup, .arrival:
      warnIfBatteryLow()
      session.start()
    default:
      whereAmI()
    }
  }

  var primaryActionTitle: String {
    switch session?.state {
    case .setup?, .arrival?: return "Start guidance"
    default: return "Where am I. Repeat"
    }
  }

  /// Repeats guidance for the current position, ignoring the chatter guard.
  func whereAmI() {
    guard let session else { return }
    if let pose = lastPose, let target = session.target, session.state != .arrived {
      let meters = Geo.distanceMeters(
        lat1: pose.lat, lon1: pose.lon, lat2: target.lat, lon2: target.lon)
      let bearing = Geo.bearingDegrees(
        lat1: pose.lat, lon1: pose.lon, lat2: target.lat, lon2: target.lon)
      // Across the street: never point toward the door.
      let offset =
        session.sameSide == false ? 0 : Geo.relativeAngle(heading: pose.heading, target: bearing)
      say(.brief(sameSide: session.sameSide, meters: meters, offsetDegrees: offset), force: true)
    } else if let lastSaid {
      say(lastSaid, force: true)
    }
  }

  /// Magic tap.
  func togglePause() {
    guard let session else { return }
    if session.isPaused {
      feedback.resume()
    } else {
      feedback.pause()
    }
    session.togglePause()
    updateBeacon()
  }

  /// Stop button and "Stop guiding": ends the trip and silences everything.
  func stopTrip() {
    guard let session else { return }
    feedback.stopAll()
    session.stop()
    arGuide.stop()
    location.stop()
    sessionCancellables.removeAll()
    self.session = nil
    isInCar = false
    wantsAR = false
    lastPose = nil
    lastSaid = nil
    status = ""
    deleteTrip()
  }

  /// Save the trip when the app leaves the foreground.
  func saveTrip() {
    guard let reducer = session?.reducer, let url = Self.tripURL,
      let data = try? JSONEncoder().encode(reducer)
    else { return }
    try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var fileURL = url
    try? fileURL.setResourceValues(values)
  }

  // MARK: - Session wiring

  private func begin(with result: ResolveResult) {
    if hasTrip { stopTrip() }
    attach(NavigationSession(reducer: SessionReducer(cameraFirst: profile.cameraFirst)))
    session?.load(result)
    location.start()
  }

  private func attach(_ session: NavigationSession) {
    sessionCancellables.removeAll()
    session.onEffect = { [weak self] effect in self?.perform(effect) }
    // Beacon follows the session's state and target.
    session.objectWillChange
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in self?.updateBeacon() }
      .store(in: &sessionCancellables)
    self.session = session
  }

  private func perform(_ effect: SessionEffect) {
    switch effect {
    case .say(let event):
      say(event)
    case .startARTracking:
      // Pocket mode keeps ARKit off; the beacon follows GPS course.
      guard profile.cameraFirst else { return }
      wantsAR = true
      startARIfPossible()
    case .stopARTracking:
      wantsAR = false
      arGuide.stop()
    case .startCamera:
      if profile.cameraFirst { arGuide.frameProvider.start() }
    case .stopCamera:
      arGuide.frameProvider.stop()
    case .saveBreadcrumb:
      // The reducer keeps breadcrumbs itself and they are saved with it on `.persist`.
      break
    case .persist:
      saveTrip()
    }
  }

  private func locationInput(_ input: SessionInput) {
    if case .pose(let lat, let lon, let heading, let accuracy, _) = input {
      if wantsAR, !arGuide.isRunning { startARIfPossible() }
      // ARKit gives better relative poses while it tracks.
      if arGuide.isRunning, arGuide.isTrackingOK { return }
      lastPose = (lat, lon, heading, accuracy)
      updateBeacon()
    }
    session?.send(input)
  }

  private func arInput(_ input: SessionInput) {
    if case .pose(let lat, let lon, let heading, let accuracy, _) = input {
      lastPose = (lat, lon, heading, accuracy)
      updateBeacon()
    }
    session?.send(input)
  }

  /// ARKit is anchored at a GPS fix, so it waits for the first one.
  private func startARIfPossible() {
    guard wantsAR, !arGuide.isRunning, let coordinate = location.currentSnapshot.coordinate else {
      return
    }
    arGuide.start(
      originLat: coordinate.latitude, originLon: coordinate.longitude,
      accuracyMeters: location.currentSnapshot.horizontalAccuracy ?? 10)
  }

  private func updateBeacon() {
    let beacon = feedback.beacon
    guard let session, profile.beaconOn, !session.isPaused,
      [.orient, .guide, .confirm, .lost].contains(session.state)
    else {
      if beacon.isRunning { beacon.stop() }
      return
    }
    // Door across the street: the beacon never points at it.
    guard session.sameSide != false, let target = session.target, let pose = lastPose else {
      beacon.clearTarget()
      return
    }
    if !beacon.isRunning { beacon.start() }
    beacon.setListenerHeading(pose.heading)
    beacon.setTarget(
      bearingDegrees: Geo.bearingDegrees(
        lat1: pose.lat, lon1: pose.lon, lat2: target.lat, lon2: target.lon),
      distanceMeters: Geo.distanceMeters(
        lat1: pose.lat, lon1: pose.lon, lat2: target.lat, lon2: target.lon))
  }

  private func say(_ event: FeedbackEvent, force: Bool = false) {
    lastSaid = event
    if let text = Phrases.text(for: event, verbosity: profile.verbosity, units: profile.units) {
      status = text
    }
    feedback.emit(event, profile: profile, force: force)
  }

  private func warnIfBatteryLow() {
    let level = UIDevice.current.batteryLevel
    if level >= 0, level < 0.15 { say(.warning(.lowBattery)) }
  }

  private func announce(_ problem: LocationProblem) {
    let text: String
    switch problem {
    case .permissionDenied:
      text = "Location is off for this app. Turn it on in Settings, under Privacy, Location Services."
    case .locationUnavailable:
      text = "Location isn't available right now. Guidance paused."
    case .compassNeedsCalibration:
      text = "The compass needs calibrating. Move the phone in a figure eight, away from the car."
    }
    status = text
    announcer.speak(text, priority: .high)
  }

  private func profileChanged(from old: FeedbackProfile) {
    guard profile != old else { return }
    if let data = try? JSONEncoder().encode(profile) {
      UserDefaults.standard.set(data, forKey: Self.profileKey)
    }
    feedback.update(profile: profile)
    location.useCourseAsHeading = !profile.cameraFirst
    if !profile.cameraFirst {
      arGuide.stop()
      wantsAR = false
    }
    updateBeacon()
  }

  private func savedPlacesChanged() {
    SavedPlacesFile.save(savedPlaces)
    NemoShortcuts.updateAppShortcutParameters()
  }

  // MARK: - Trip file

  private static var tripURL: URL? {
    try? FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
    ).appendingPathComponent(tripFile)
  }

  private func restoreTrip() {
    guard let url = Self.tripURL, let data = try? Data(contentsOf: url),
      let reducer = try? JSONDecoder().decode(SessionReducer.self, from: data),
      reducer.bundle != nil, reducer.state != .arrived
    else { return }
    attach(NavigationSession(reducer: reducer))
    location.start()
    // Mid-walk: bring the sensors back. ARKit re-anchors at the next GPS fix.
    if [.orient, .guide, .confirm, .lost].contains(reducer.state) {
      perform(.startARTracking)
      if reducer.cameraFirst { perform(.startCamera) }
    }
  }

  private func deleteTrip() {
    guard let url = Self.tripURL else { return }
    try? FileManager.default.removeItem(at: url)
  }
}
