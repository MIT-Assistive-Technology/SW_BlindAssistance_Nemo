//  ARFrameProvider.swift
//  nemo-software
//
//  Forwards ARKit's camera image through the same `FrameProvider` protocol as
//  `CameraFrameProvider`, so the perception pipeline doesn't care who owns the camera.
//  ARKit and AVCaptureSession can't run together; while guidance runs, ARGuide's session
//  owns the camera and feeds this provider.
//
//  `ingest(_:)` is called on ARGuide's serial background queue for every ARFrame. It drops
//  frames to at most `maxFramesPerSecond`, skips frames while the delegate is still busy with
//  the last one, and keeps only `capturedImage` (420YpCbCr), never the ARFrame itself.
//

import ARKit
import CoreVideo
import Foundation
import os

// `nonisolated` like CameraFrameProvider: frames arrive on ARGuide's background queue, and
// FrameProvider is a nonisolated protocol on the camera-stream branch.
nonisolated final class ARFrameProvider: NSObject, FrameProvider, @unchecked Sendable {
  nonisolated static let maxFramesPerSecond: Double = 10

  weak var delegate: FrameProviderDelegate?
  private(set) var isRunning = false

  private nonisolated struct Gate {
    var enabled = false
    var busy = false
    var lastTimestamp: TimeInterval = 0
    var portraitFieldOfViewDegrees: Double?
  }

  private let gate = OSAllocatedUnfairLock(initialState: Gate())

  /// Horizontal field of view of the frames as the text reader sees them (portrait),
  /// from ARKit's camera intrinsics. Nil until the first frame.
  var portraitFieldOfViewDegrees: Double? { gate.withLock { $0.portraitFieldOfViewDegrees } }

  // MARK: - FrameProvider

  /// Nothing to set up: ARGuide owns the ARSession and its camera permission prompt.
  /// A plain, non-throwing method also satisfies the `async throws(FrameProviderError)`
  /// requirement the protocol has on the camera-stream branch.
  func setupSession() {}

  func start() {
    isRunning = true
    gate.withLock { $0.enabled = true }
  }

  func stop() {
    isRunning = false
    gate.withLock { $0.enabled = false }
  }

  // MARK: - Called by ARGuide on its AR queue

  nonisolated func ingest(_ frame: ARFrame) {
    let timestamp = frame.timestamp
    let minInterval = 1 / Self.maxFramesPerSecond
    let accept = gate.withLock { gate -> Bool in
      guard gate.enabled, !gate.busy, timestamp - gate.lastTimestamp >= minInterval else {
        return false
      }
      gate.busy = true
      gate.lastTimestamp = timestamp
      return true
    }
    guard accept else { return }

    // Frames are landscape; held in portrait, the image's height runs left to right.
    let fy = Double(frame.camera.intrinsics[1][1])
    let height = Double(frame.camera.imageResolution.height)
    if fy > 0 {
      let fov = 2 * atan(height / 2 / fy) * 180 / .pi
      gate.withLock { $0.portraitFieldOfViewDegrees = fov }
    }

    // Keep the pixel buffer only; the ARFrame is released when this function returns.
    // PerceptionPipeline takes it on its own queue (or drops it), so no main-thread hop.
    let buffer = frame.capturedImage
    delegate?.processFrame(self, buffer: buffer)
    gate.withLock { $0.busy = false }
  }
}
