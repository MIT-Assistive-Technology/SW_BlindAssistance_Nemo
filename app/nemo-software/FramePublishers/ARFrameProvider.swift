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

final class ARFrameProvider: NSObject, FrameProvider {
  nonisolated static let maxFramesPerSecond: Double = 10

  weak var delegate: FrameProviderDelegate?
  private(set) var isRunning = false

  private nonisolated struct Gate {
    var enabled = false
    var busy = false
    var lastTimestamp: TimeInterval = 0
  }

  private let gate = OSAllocatedUnfairLock(initialState: Gate())

  // MARK: - FrameProvider

  /// Nothing to set up: ARGuide owns the ARSession and its camera permission prompt.
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

    // Keep the pixel buffer only; the ARFrame is released when this function returns.
    let buffer = frame.capturedImage
    // The current delegate (PerceptionPipeline) is main-actor isolated, so deliver there.
    // Move this hop into the pipeline once detection runs on its own queue.
    Task { @MainActor [weak self] in
      guard let self else { return }
      if self.isRunning { self.delegate?.processFrame(self, buffer: buffer) }
      self.gate.withLock { $0.busy = false }
    }
  }
}
