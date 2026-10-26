//  SyntheticFrameProvider.swift
//  nemo-software
//
//  Generates blank frames on a timer, in the same size and format as the camera.
//  Used in the Simulator (no camera) and for tests, so the pipeline's threading and
//  frame dropping can be checked without a phone. Replace with a VideoFileFrameProvider
//  when there are recorded walks to replay.
//

import CoreVideo
import Foundation

nonisolated final class SyntheticFrameProvider: FrameProvider, @unchecked Sendable {
  weak var delegate: FrameProviderDelegate?

  var isRunning: Bool { queue.sync { timer != nil } }

  private let width: Int
  private let height: Int
  private let framesPerSecond: Double
  private let queue = DispatchQueue(label: "nemo.synthetic-frames", qos: .userInitiated)

  /// Only touched on `queue`.
  private var timer: DispatchSourceTimer?
  private var pool: CVPixelBufferPool?

  init(width: Int = 1920, height: Int = 1080, framesPerSecond: Double = 30) {
    self.width = width
    self.height = height
    self.framesPerSecond = framesPerSecond
  }

  func setupSession() async throws(FrameProviderError) {
    let attributes: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
      kCVPixelBufferWidthKey as String: width,
      kCVPixelBufferHeightKey as String: height,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
    ]
    var newPool: CVPixelBufferPool?
    let status = CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &newPool)
    guard status == kCVReturnSuccess, let newPool else {
      throw .configurationFailed("CVPixelBufferPoolCreate failed (\(status))")
    }
    queue.sync { pool = newPool }
  }

  func start() {
    queue.async { [weak self] in
      guard let self, self.timer == nil, self.pool != nil else { return }
      let timer = DispatchSource.makeTimerSource(queue: self.queue)
      timer.schedule(deadline: .now(), repeating: 1 / self.framesPerSecond)
      timer.setEventHandler { [weak self] in self?.emitFrame() }
      self.timer = timer
      timer.resume()
    }
  }

  func stop() {
    queue.async { [weak self] in
      self?.timer?.cancel()
      self?.timer = nil
    }
  }

  /// Runs on `queue`, like a camera callback.
  private func emitFrame() {
    guard let pool else { return }
    var buffer: CVPixelBuffer?
    // Fails when every pooled buffer is still held downstream, which is the same back
    // pressure the real camera applies. Drop the frame in that case.
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
      let buffer
    else { return }
    delegate?.processFrame(self, buffer: buffer)
  }
}
