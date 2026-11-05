//  AppServices.swift
//  nemo-software
//
//  Composition root for the long-lived objects the screens share: sensors, feedback
//  channels and the bundle cache. One place to swap a live client or a replay provider
//  in, so no view has to know how its dependencies were built.
//

import AVFoundation
import Combine
import CoreLocation
import Foundation

@MainActor
public final class AppServices: ObservableObject {
  public let location: LocationService
  public let feedback: FeedbackKit
  public let bundleStore: BundleStore
  public let entranceClient: CachingEntranceClient
  /// One trip state machine shared by the ride and walk screens, so a hand-over at the
  /// drop-off doesn't lose it (FE-10).
  public let session: NavigationSession
  public let sessionStore: SessionStore
  /// The one camera pipeline. The debug screen shows it, and during a walk its
  /// building-number reads go to `session` (Amy's CV-9 → Jing's FE-10).
  public let camera: CameraViewModel

  private let pipeline: PerceptionPipeline
  private var cameraStartedForWalk = false
  /// The door finder's camera on LiDAR phones: in the last stretch ARKit takes over the
  /// camera, finds doors in its mesh, and passes frames on to the text reader.
  private let arGuide = ARGuide()
  /// LiDAR and scene reconstruction (Pro iPhones). Other phones use text reading only.
  public static var canDetectDoors: Bool { ARGuide.isSupported && DoorMeshDetector.isSupported }
  /// True only while ARKit is running and reporting a usable tracking state.
  public var arGuideIsTracking: Bool { arGuide.isRunning && arGuide.isTrackingOK }
  private var cancellables = Set<AnyCancellable>()

  /// Defaults are built inside the initializer, not as default arguments: a default
  /// argument is evaluated outside the actor, and `LocationService.shared` is
  /// main-actor isolated.
  public init(
    location: LocationService? = nil,
    bundleStore: BundleStore = BundleStore(),
    // Pilot bundles shipped in the app (real OSM data for the pilot sites); anything
    // else is "not found". The made-up example is only for tests. Swap in
    // `LiveEntranceClient(baseURL: ...)` once the server is up; the cache in front of
    // it means the walk still works with no signal (FE-11).
    upstream: EntranceClient? = nil,
    channels: [FeedbackChannel]? = nil
  ) {
    let location = location ?? .shared
    self.location = location
    self.bundleStore = bundleStore
    self.entranceClient = CachingEntranceClient(
      upstream: upstream ?? PilotBundleClient(), store: bundleStore)
    // One owner for the audio session, set up front rather than on first speak. The
    // default category is `soloAmbient`, which iOS silences on screen lock and with the
    // Ring/Silent switch, and which interrupts other audio — all three are wrong for a
    // beacon the rider walks by. TODO (FE-8): route changes (headphones unplugged).
    Self.configureAudioSession()
    let feedback = FeedbackKit(
      channels: channels ?? [SpeechChannel(speaker: Speaker()), BeaconChannel(), HapticsChannel()])
    self.feedback = feedback
    let sessionStore = SessionStore()
    self.sessionStore = sessionStore
    let session = NavigationSession(feedback: feedback, store: sessionStore)
    self.session = session

    // The Simulator has no camera, so it gets blank frames to exercise the pipeline.
    #if targetEnvironment(simulator)
      let frameProvider: any FrameProvider = SyntheticFrameProvider()
    #else
      let frameProvider: any FrameProvider = CameraFrameProvider()
    #endif
    let pipeline = PerceptionPipeline(
      detector: VisionObjectDetector(),
      numberRecognizer: VisionNumberRecognizer(),
      locationProvider: location,
      speaker: Speaker())
    self.pipeline = pipeline
    self.camera = CameraViewModel(frameProvider: frameProvider, pipeline: pipeline)

    pipeline.onTextRead = { [weak self] read in self?.buildingCheck(read) }
    arGuide.frameProvider.delegate = pipeline
    arGuide.onPose = { [weak self] position, heading in
      self?.session.update(position: position, heading: heading)
    }
    arGuide.onTracking = { [weak self] _ in self?.objectWillChange.send() }
    arGuide.onDoor = { [weak self] hit in
      // 12 faces is the detector's floor and counts as just sure enough.
      self?.session.observeDoor(
        DoorSighting(
          kind: .door, offsetDegrees: hit.offsetDegrees, meters: hit.meters,
          confidence: min(1, Double(hit.faceCount) / 24)))
    }
    arGuide.onLowLight = { [weak self] in self?.session.cameraCheckUnavailable(.lowLight) }
    session.$state
      .sink { [weak self] state in self?.cameraFollow(state) }
      .store(in: &cancellables)
    location.$currentSnapshot
      .sink { [weak self] _ in
        guard let self else { return }
        self.cameraFollow(self.session.state)
      }
      .store(in: &cancellables)
  }

  // MARK: - Building check (CV-9 → FE-10)

  private static let walkingStates: Set<SessionState> = [.orient, .guide, .confirm, .lost]

  /// Camera-first mode (plan section 7): the building check runs while walking. Raw
  /// "Number 77" speech is off then, so only the session's reviewed phrases are spoken.
  private func cameraFollow(_ state: SessionState) {
    let walking = Self.walkingStates.contains(state)
    pipeline.announcesReads = !walking
    if walking { pipeline.setExpectedBundleTexts(session.expectedBuildingTexts) }

    // ARKit owns the camera whenever it is available for the walk, and on LiDAR phones
    // keeps running through `.confirm` so pose updates and door mesh scanning share one
    // tracking session. AVCaptureSession and ARKit can't both have the camera.
    let wantsDoorScan = state == .confirm && Self.canDetectDoors
    let canStartARWalk = walking && ARGuide.isSupported && location.currentSnapshot.coordinate != nil
    if wantsDoorScan || canStartARWalk {
      cameraStartedForWalk = false
      camera.stop()
      if !arGuide.isRunning {
        if let coordinate = location.currentSnapshot.coordinate {
          arGuide.start(
            originLat: coordinate.latitude,
            originLon: coordinate.longitude,
            accuracyMeters: location.currentSnapshot.horizontalAccuracy ?? 10)
        } else {
          arGuide.startDoorSearch()
        }
      }
      arGuide.frameProvider.start()
      arGuide.setDoorSearchEnabled(wantsDoorScan)
      return
    }

    if arGuide.isRunning { arGuide.stop() }

    if walking {
      guard !camera.isRunning else { return }
      cameraStartedForWalk = true
      Task {
        await camera.setup()
        camera.start()
      }
    } else if cameraStartedForWalk {
      cameraStartedForWalk = false
      camera.stop()
    }
  }

  /// A building number Amy's reader saw becomes a `BuildingSighting` for Jing's session,
  /// which checks the direction against the map before believing it. Only text the
  /// bundle already has counts, so nothing free-form is spoken.
  private func buildingCheck(_ read: CameraTextRead) {
    if session.state == .confirm {
      doorCheck(read)
      return
    }
    guard Self.walkingStates.contains(session.state),
      let heading = location.currentSnapshot.headingReadout,
      let fov = camera.fieldOfViewDegrees
    else { return }
    let expected = session.expectedBuildingTexts
    for number in read.numbers {
      guard let text = BundleTextMatcher.match(read: number.value, expected: expected) else {
        continue
      }
      // Vision's box is normalized to the portrait image, so width 1 and the box centre.
      session.observe(
        BuildingSighting(
          text: text,
          headingDegrees: heading.trueHeadingDegrees,
          xPixels: number.boundingBox.midX,
          widthPixels: 1,
          fovDegrees: fov,
          confidence: Double(number.confidence)))
      return
    }
  }

  /// The door finder's text half: in the last stretch an entrance word, or the
  /// building's own number or name, becomes a `DoorSighting`, placed by where it is in
  /// the frame. Entrance words win: they're on the door, the number may be above it.
  private func doorCheck(_ read: CameraTextRead) {
    let fov =
      arGuide.isRunning ? arGuide.frameProvider.portraitFieldOfViewDegrees : camera.fieldOfViewDegrees
    guard let fov else { return }
    let clue: (DoorClue, CGRect, Float)?
    if let sign = read.entranceSigns.first {
      clue = (.entranceSign(sign.word), sign.boundingBox, sign.confidence)
    } else {
      let expected = session.expectedBuildingTexts
      clue = read.numbers.lazy.compactMap { number -> (DoorClue, CGRect, Float)? in
        BundleTextMatcher.match(read: number.value, expected: expected).map {
          (.buildingText($0), number.boundingBox, number.confidence)
        }
      }.first
    }
    guard let (kind, box, confidence) = clue else { return }
    session.observeDoor(
      DoorSighting(
        kind: .clue(kind),
        offsetDegrees: DoorSighting.offsetDegrees(normalizedX: box.midX, fovDegrees: fov),
        confidence: Double(confidence)))
  }

  /// One owner for the audio session: Trish's `AudioSessionManager` (FE-8), which also
  /// handles call interruptions.
  private static func configureAudioSession() {
    #if os(iOS)
      AudioSessionManager.shared.start()
    #endif
  }

  /// An unfinished trip found at launch, waiting for the rider to resume or end it.
  /// Nothing is resumed or spoken until they choose (FE-10).
  @Published public private(set) var unfinishedTrip: SessionSnapshot?

  /// Call once at launch. Finds an interrupted trip but doesn't act on it: the home
  /// screen offers "Resume trip" and "End trip". Trips older than `maxResumeAge` were
  /// abandoned, not interrupted, and are deleted.
  public func checkForUnfinishedTrip() {
    guard let snapshot = sessionStore.load() else { return }
    guard Date().timeIntervalSince(snapshot.updatedAt) <= Self.maxResumeAge,
      snapshot.state != .setup, snapshot.state != .arrived,
      bundleStore.result(for: snapshot.address) != nil
    else {
      sessionStore.clear()
      return
    }
    unfinishedTrip = snapshot
  }

  /// "Resume trip": pick up where the relaunch left off (asks the side of street again
  /// during a ride, re-orients during a walk).
  public func resumeUnfinishedTrip() {
    guard let snapshot = unfinishedTrip,
      let bundle = bundleStore.result(for: snapshot.address)
    else {
      unfinishedTrip = nil
      return
    }
    unfinishedTrip = nil
    session.resume(from: snapshot, bundle: bundle)
  }

  /// "End trip": stop the trip and forget it.
  public func endTrip() {
    unfinishedTrip = nil
    session.stop()
    sessionStore.clear()
    if location.isTrackingRide { location.stopRideTracking() }
  }

  /// "End trip and reset": also delete every saved entrance bundle, so the next lookup
  /// starts clean.
  public func resetAll() {
    endTrip()
    try? bundleStore.removeAll()
  }

  /// Longer than any ride plus walk; a trip older than this was abandoned, not interrupted.
  private static let maxResumeAge: TimeInterval = 2 * 60 * 60
}
