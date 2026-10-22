//  ARGuide.swift
//  nemo-software
//
//  ARKit world tracking for the walk (FE-12). The session runs with `.gravityAndHeading`,
//  so AR x points east and -z points (true) north, with the world origin where tracking
//  started. That origin is anchored to the GPS fix at the start through `LocalFrame`, so a
//  camera position becomes lat/lon by adding its east/north meters to the start point.
//
//  Emits:
//    .pose        about 5 times a second: anchored position + camera heading
//    .arTracking  when tracking becomes usable or is lost
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
  /// Session inputs (.pose, .arTracking). Set by the composition root.
  var onInput: ((SessionInput) -> Void)?
  /// Called once each time the scene stays too dark for the camera check.
  var onLowLight: (() -> Void)?

  /// Camera frames for the perception pipeline while ARKit owns the camera.
  let frameProvider = ARFrameProvider()

  private(set) var isRunning = false
  private(set) var isTrackingOK = false

  static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

  private let session = ARSession()
  private let arQueue = DispatchQueue(label: "nemo.arguide", qos: .userInitiated)

  private var origin: LocalFrame?
  private var originAccuracyMeters: Double = 10
  private var lastHeading: Double?
  private var darkSince: Date?
  private var lowLightReported = false

  private nonisolated struct Throttle {
    var lastPose: TimeInterval = 0
  }
  private let throttle = OSAllocatedUnfairLock(initialState: Throttle())
  private nonisolated static let poseInterval: TimeInterval = 0.2

  // Light estimate thresholds in lumens (about 1000 is a well-lit scene).
  private static let darkLumens: CGFloat = 150
  private static let brightLumens: CGFloat = 300
  private static let darkSeconds: TimeInterval = 3
  /// ARKit drift per meter walked.
  private static let driftPerMeter = 0.03

  override init() {
    super.init()
    session.delegate = self
    session.delegateQueue = arQueue
  }

  // MARK: - Control

  /// Starts tracking, anchoring the AR origin at this GPS fix (the rider's position now).
  func start(originLat: Double, originLon: Double, accuracyMeters: Double) {
    guard Self.isSupported else {
      onInput?(.arTracking(ok: false))
      return
    }
    origin = LocalFrame(originLat: originLat, originLon: originLon)
    originAccuracyMeters = max(accuracyMeters, 0)
    lastHeading = nil
    darkSince = nil
    lowLightReported = false
    throttle.withLock { $0.lastPose = 0 }

    let configuration = ARWorldTrackingConfiguration()
    configuration.worldAlignment = .gravityAndHeading
    configuration.isLightEstimationEnabled = true
    // 30 fps is plenty and saves battery.
    if let format = ARWorldTrackingConfiguration.supportedVideoFormats.first(where: {
      $0.framesPerSecond == 30
    }) {
      configuration.videoFormat = format
    }
    session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    isRunning = true
  }

  func stop() {
    guard isRunning else { return }
    isRunning = false
    frameProvider.stop()
    session.pause()
    setTracking(false, report: false)
  }

  // MARK: - ARSessionDelegate (AR queue)

  nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
    frameProvider.ingest(frame)

    let timestamp = frame.timestamp
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
    if report, isRunning { onInput?(.arTracking(ok: ok)) }
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
    onInput?(
      .pose(
        lat: position.lat, lon: position.lon, headingDegrees: heading,
        accuracyMeters: originAccuracyMeters + walked * Self.driftPerMeter, at: Date()))
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
