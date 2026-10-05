//  CameraViewModel.swift
//  nemo-software
//
//  Owns the active frame provider and perception pipeline. Exposes a simple
//  start/stop surface for the SwiftUI view and binds to the latest results.
//

import Combine
import Foundation

@MainActor
public final class CameraViewModel: ObservableObject {
  /// Latest processed frame data for the UI.
  @Published public private(set) var presentation: FramePresentation?

  /// Whether the camera stream is currently running.
  @Published public private(set) var isRunning = false

  private let frameProvider: any FrameProvider
  private let pipeline: PerceptionPipeline

  public init(frameProvider: any FrameProvider, pipeline: PerceptionPipeline) {
    self.frameProvider = frameProvider
    self.pipeline = pipeline

    // Wire the provider to the pipeline.
    frameProvider.delegate = pipeline

    // Forward pipeline presentation updates to this view model.
    pipeline.$presentation
      .receive(on: DispatchQueue.main)
      .sink { [weak self] presentation in
        self?.presentation = presentation
      }
      .store(in: &cancellables)
  }

  private var cancellables = Set<AnyCancellable>()

  /// One-time setup; safe to call multiple times.
  public func setup() {
    frameProvider.setupSession()
  }

  /// Start streaming.
  public func start() {
    guard !isRunning else { return }
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
