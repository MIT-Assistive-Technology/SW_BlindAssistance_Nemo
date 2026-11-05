//  ARGuide.swift
//  nemo-software
//
//  ARKit world tracking for the walk (FE-12). The session runs with `.gravityAndHeading`,
//  so AR x points east and -z points (true) north, with the world origin where tracking
//  started. That origin is anchored to the GPS fix at the start through `LocalFrame`, so a
//  camera position becomes lat/lon by adding its east/north meters to the start point.
//
//  From Minh's app/mvp, adapted to Jing's navigation types. Reports:
//    onPose      about 5 times a second: anchored position + camera heading, ready for
//                `NavigationSession.update(position:heading:)`
//    onTracking  when tracking becomes usable or is lost
//
//  Not switched on yet: the walk still runs on GPS + compass (FE-3). Turning this on is
//  FE-12, and while it runs ARKit owns the camera, so the building check must switch to
//  `frameProvider` instead of `CameraFrameProvider`.
//  and calls `onLowLight` when ARKit's light estimate stays dark ("Camera check unavailable
//  in low light"). Camera frames go to `frameProvider` at most 10 per second.
//
//  ARKit drifts 1-3 m over 50 m and inherits the GPS start error (5-15 m), so the reported
//  accuracy grows with the distance walked. ARKit and the camera stop when the screen locks.
//

import ARKit
import Foundation
import os
import simd

final class ARGuide: NSObject, ARSessionDelegate {
  /// Anchored position and camera heading, about 5 times a second.
  var onPose: ((GuidancePosition, HeadingReadout) -> Void)?
  /// Tracking became usable (true) or was lost (false).
  var onTracking: ((Bool) -> Void)?
  /// Called once each time the scene stays too dark for the camera check.
  var onLowLight: (() -> Void)?
  /// Door finder (LiDAR phones): the nearest door in front of the camera, about twice a
  /// second while `startDoorSearch()` runs.
  var onDoor: ((DoorMeshHit) -> Void)?
  /// Free-space scan (LiDAR phones): the wedges ahead, a couple of times a second while
  /// the walk runs. Feeds hazard speech now and the steering picker later.
  var onFreeSpace: ((FreeSpace) -> Void)?

  /// Camera frames for the perception pipeline while ARKit owns the camera.
  let frameProvider = ARFrameProvider()

  private(set) var isRunning = false
  private(set) var isTrackingOK = false
  /// Whether the current tracking session has a GPS origin and can publish poses.
  var hasAnchoredPose: Bool { origin != nil }

  static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }
  /// Phones with LiDAR can measure depth, so the free-space scan gets real meters.
  static var canMeasureDepth: Bool {
    ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
  }

  private let session = ARSession()
  private let arQueue = DispatchQueue(label: "nemo.arguide", qos: .userInitiated)

  private var origin: LocalFrame?
  private var originAccuracyMeters: Double = 10
  private var lastHeading: Double?
  private var darkSince: Date?
  private var lowLightReported = false

  private nonisolated struct Throttle {
    var lastPose: TimeInterval = 0
    var lastDoorScan: TimeInterval = 0
    var lastFreeSpaceScan: TimeInterval = 0
    var searchingForDoors = false
  }
  private let throttle = OSAllocatedUnfairLock(initialState: Throttle())
  private nonisolated static let poseInterval: TimeInterval = 0.2
  private nonisolated static let doorScanInterval: TimeInterval = 0.5
  /// The free-space scan is heavier than the pose readout; every 0.4 s is often
  /// enough for hazards without heating the phone.
  private nonisolated static let freeSpaceInterval: TimeInterval = 0.4

  // Light estimate thresholds in lumens (about 1000 is a well-lit scene).
  private static let darkLumens: CGFloat = 150
  private static let brightLumens: CGFloat = 300
  private static let darkSeconds: TimeInterval = 3
  /// ARKit drift per meter walked.
  private static let driftPerMeter = 0.03
  /// Compass error ARKit inherits at start (plan section 5: 10–20° beside a car).
  private static let headingAccuracyDegrees = 15.0

  override init() {
    super.init()
    session.delegate = self
    session.delegateQueue = arQueue
  }

  // MARK: - Control

  /// Starts tracking for the walk. With a GPS fix, the AR origin is anchored to it so
  /// `onPose` can report positions (the snap-to-route step wires those in); without
  /// one, `start()` still runs the camera and depth, just publishes no poses.
  func start(originLat: Double? = nil, originLon: Double? = nil, accuracyMeters: Double = 10) {
    guard Self.isSupported else {
      onTracking?(false)
      return
    }
    if let originLat, let originLon {
      origin = LocalFrame(originLat: originLat, originLon: originLon)
      originAccuracyMeters = max(accuracyMeters, 0)
    } else {
      origin = nil
    }
    lastHeading = nil
    darkSince = nil
    lowLightReported = false
    throttle.withLock { $0.lastPose = 0 }
    session.run(Self.walkConfiguration(), options: [.resetTracking, .removeExistingAnchors])
    isRunning = true
  }

  /// The walk configuration: world tracking aligned to gravity and heading, plus
  /// LiDAR depth and scene reconstruction on phones that have it — `sceneDepth` feeds
  /// the free-space scan, and the mesh feeds both its ground level and the door
  /// finder, so the last stretch needs no session restart.
  private static func walkConfiguration() -> ARWorldTrackingConfiguration {
    let configuration = ARWorldTrackingConfiguration()
    configuration.worldAlignment = .gravityAndHeading
    configuration.isLightEstimationEnabled = true
    // Keep depth and the mesh available on LiDAR phones: depth feeds the free-space
    // scan, and the mesh lets the door finder start without resetting tracking.
    if canMeasureDepth {
      configuration.frameSemantics.insert(.sceneDepth)
    }
    if DoorMeshDetector.isSupported {
      configuration.sceneReconstruction = .meshWithClassification
    }
    // 30 fps is plenty and saves battery.
    if let format = ARWorldTrackingConfiguration.supportedVideoFormats.first(where: {
      $0.framesPerSecond == 30
    }) {
      configuration.videoFormat = format
    }
    return configuration
  }

  /// The door finder's half in the last stretch. The walk configuration already
  /// carries the mesh, so this just turns the scan on; only when the walk isn't
  /// running (e.g. resumed straight into the last stretch) does it run its own
  /// session. Needs no GPS anchor; poses aren't published.
  func startDoorSearch() {
    guard Self.isSupported, DoorMeshDetector.isSupported else { return }
    if isRunning {
      throttle.withLock { $0.searchingForDoors = true }
      return
    }
    origin = nil
    darkSince = nil
    lowLightReported = false
    throttle.withLock {
      $0.lastPose = 0
      $0.lastDoorScan = 0
      $0.searchingForDoors = true
    }
    let configuration = ARWorldTrackingConfiguration()
    configuration.worldAlignment = .gravity
    configuration.isLightEstimationEnabled = true
    configuration.sceneReconstruction = .meshWithClassification
    if Self.canMeasureDepth {
      configuration.frameSemantics.insert(.sceneDepth)
    }
    session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    isRunning = true
  }

  /// Turn mesh door scanning on/off without restarting the walk's anchored tracking.
  func setDoorSearchEnabled(_ enabled: Bool) {
    guard isRunning else { return }
    throttle.withLock {
      $0.searchingForDoors = enabled && DoorMeshDetector.isSupported
    }
  }

  func stop() {
    guard isRunning else { return }
    isRunning = false
    throttle.withLock { $0.searchingForDoors = false }
    frameProvider.stop()
    session.pause()
    setTracking(false, report: false)
  }

  // MARK: - ARSessionDelegate (AR queue)

  nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
    frameProvider.ingest(frame)

    let timestamp = frame.timestamp
    let doorScanDue = throttle.withLock { state -> Bool in
      guard state.searchingForDoors, timestamp - state.lastDoorScan >= Self.doorScanInterval
      else { return false }
      state.lastDoorScan = timestamp
      return true
    }
    if doorScanDue {
      let meshes = frame.anchors.compactMap { $0 as? ARMeshAnchor }
      if let hit = DoorMeshDetector.nearestDoor(anchors: meshes, camera: frame.camera.transform) {
        Task { @MainActor [weak self] in
          guard let self, self.isRunning else { return }
          self.onDoor?(hit)
        }
      }
    }

    // Free-space scan: sceneDepth on LiDAR phones, with the mesh's floor faces as the
    // ground reference when reconstruction is on. Everything is read here on the AR
    // queue; only the value-type result hops to the main actor.
    let freeSpaceDue = throttle.withLock { state -> Bool in
      guard timestamp - state.lastFreeSpaceScan >= Self.freeSpaceInterval else {
        return false
      }
      state.lastFreeSpaceScan = timestamp
      return true
    }
    if freeSpaceDue, let freeSpace = Self.freeSpaceScan(frame) {
      Task { @MainActor [weak self] in
        guard let self, self.isRunning else { return }
        self.onFreeSpace?(freeSpace)
      }
    }

    let due = throttle.withLock { state -> Bool in
      guard timestamp - state.lastPose >= Self.poseInterval else { return false }
      state.lastPose = timestamp
      return true
    }
    guard due else { return }
    // Copy plain values out; the frame itself must not outlive this call.
    let transform = frame.camera.transform
    let lumens = frame.lightEstimate?.ambientIntensity
    Task { @MainActor [weak self] in
      self?.publish(transform: transform, lumens: lumens)
    }
  }

  /// One free-space reading from a frame, or nil without depth. Runs on the AR queue
  /// and retains nothing from the frame.
  private nonisolated static func freeSpaceScan(_ frame: ARFrame) -> FreeSpace? {
    guard let depth = frame.sceneDepth,
      let depthFrame = DepthFrame(depthData: depth, camera: frame.camera)
    else { return nil }
    // Scene reconstruction's floor faces pin down the ground level when the mesh is
    // on; without them the depth map estimates it itself.
    let floorPoints = frame.anchors.compactMap { $0 as? ARMeshAnchor }.flatMap {
      DoorMeshDetector.faceCentres(
        of: $0, matching: UInt8(ARMeshClassification.floor.rawValue))
    }
    return FreeSpaceAnalyzer.analyze(depthFrame, floorPoints: floorPoints)
  }

  nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
    let ok: Bool?
    switch camera.trackingState {
    case .normal:
      ok = true
    case .limited(.initializing), .limited(.relocalizing):
      ok = nil  // starting up; not a loss
    case .limited, .notAvailable:
      ok = false
    }
    guard let ok else { return }
    Task { @MainActor [weak self] in self?.setTracking(ok, report: true) }
  }

  nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
    Task { @MainActor [weak self] in self?.setTracking(false, report: true) }
  }

  nonisolated func sessionWasInterrupted(_ session: ARSession) {
    Task { @MainActor [weak self] in self?.setTracking(false, report: true) }
  }

  // MARK: - Private (main actor)

  private func setTracking(_ ok: Bool, report: Bool) {
    guard ok != isTrackingOK else { return }
    isTrackingOK = ok
    if report, isRunning { onTracking?(ok) }
  }

  private func publish(transform: simd_float4x4, lumens: CGFloat?) {
    guard isRunning else { return }
    checkLight(lumens)
    guard isTrackingOK, let origin else { return }

    let east = Double(transform.columns.3.x)
    let north = Double(-transform.columns.3.z)
    // The back camera looks along the camera's -Z axis. In world terms east is +x and
    // north is -z, so forward = (-c2.x east, +c2.z north).
    let forwardEast = Double(-transform.columns.2.x)
    let forwardNorth = Double(transform.columns.2.z)
    if hypot(forwardEast, forwardNorth) > 0.3 {
      let degrees = atan2(forwardEast, forwardNorth) * 180 / .pi
      lastHeading = degrees < 0 ? degrees + 360 : degrees
    }
    // Phone pointing straight down or up: keep the last good heading.
    guard let heading = lastHeading else { return }

    let position = origin.toGeo(east: east, north: north)
    let walked = hypot(east, north)
    let now = Date()
    onPose?(
      GuidancePosition(
        latitude: position.lat, longitude: position.lon,
        horizontalAccuracyMeters: originAccuracyMeters + walked * Self.driftPerMeter,
        timestamp: now),
      // ARKit's heading is aligned to the compass at start, so it carries that error.
      HeadingReadout(
        trueHeadingDegrees: heading, accuracyDegrees: Self.headingAccuracyDegrees,
        timestamp: now))
  }

  private func checkLight(_ lumens: CGFloat?) {
    guard let lumens else { return }
    if lumens < Self.darkLumens {
      let since = darkSince ?? Date()
      darkSince = since
      if !lowLightReported, Date().timeIntervalSince(since) >= Self.darkSeconds {
        lowLightReported = true
        onLowLight?()
      }
    } else if lumens > Self.brightLumens {
      darkSince = nil
      lowLightReported = false
    }
  }
}
