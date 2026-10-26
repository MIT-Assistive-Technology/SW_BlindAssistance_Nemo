//  CameraViewModel.swift
//  nemo-software
//
//  Owns the active frame provider and perception pipeline. Exposes a simple
//  start/stop surface for the SwiftUI view and binds to the latest results.
//

import AVFoundation
import Combine
import Foundation

/// Where the camera screen is in its setup.
public enum CameraStatus: Equatable {
  case notSetUp
  case settingUp
  case ready
  case unavailable(FrameProviderError)
}

@MainActor
public final class CameraViewModel: ObservableObject {
  /// Latest processed frame data for the UI.
  @Published public private(set) var presentation: FramePresentation?

  /// Whether the camera stream is currently running.
  @Published public private(set) var isRunning = false

  @Published public private(set) var status: CameraStatus = .notSetUp

  private let frameProvider: any FrameProvider
  private let pipeline: PerceptionPipeline

  public init(frameProvider: any FrameProvider, pipeline: PerceptionPipeline) {
    self.frameProvider = frameProvider
    self.pipeline = pipeline

    // Wire the provider to the pipeline.
    frameProvider.delegate = pipeline

    // The pipeline calls this on the main actor.
    pipeline.onPresentation = { [weak self] presentation in
      self?.presentation = presentation
    }
  }

  /// The capture session to preview, when the provider is the live camera.
  var previewSession: AVCaptureSession? {
    #if os(iOS)
      (frameProvider as? CameraFrameProvider)?.previewSession
    #else
      nil
    #endif
  }

  /// One-time setup (asks for camera permission the first time); safe to call multiple times.
  public func setup() async {
    guard status == .notSetUp else { return }
    status = .settingUp
    do {
      try await frameProvider.setupSession()
      status = .ready
    } catch {
      status = .unavailable(error)
    }
  }

  /// Start streaming.
  public func start() {
    guard status == .ready, !isRunning else { return }
    isRunning = true
    frameProvider.start()
  }

  /// Stop streaming.
  public func stop() {
    guard isRunning else { return }
    isRunning = false
    frameProvider.stop()
  }
}
