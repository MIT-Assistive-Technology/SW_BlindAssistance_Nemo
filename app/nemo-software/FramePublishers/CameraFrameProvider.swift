//  CameraFrameProvider.swift
//  nemo-software
//
//  Live camera capture using AVFoundation. Streams frames to the perception pipeline
//  on a background queue.
//

import AVFoundation
import CoreVideo
import Foundation
import os

#if canImport(UIKit)
  import UIKit
#endif

#if os(iOS)

  /// Picks the best available back camera, or nil (Simulator, CI).
  nonisolated func bestCaptureDevice() -> AVCaptureDevice? {
    // Plain wide-angle first: the multi-camera virtual devices switch lenses on their own,
    // which changes the field of view under the building check.
    let deviceTypes: [AVCaptureDevice.DeviceType] = [
      .builtInWideAngleCamera,
      .builtInDualWideCamera,
      .builtInDualCamera,
      .builtInTripleCamera,
    ]
    let discoverySession = AVCaptureDevice.DiscoverySession(
      deviceTypes: deviceTypes, mediaType: .video, position: .back)
    return discoverySession.devices.first
  }

  /// Plain AVFoundation camera, good for the first detection milestone.
  /// NOTE: once ARKit guidance lands (FE-12), ARKit owns the camera and the two
  /// can't run at the same time. Add an `ARFrameProvider` that forwards
  /// `ARFrame.capturedImage` through this same `FrameProvider` protocol.
  ///
  /// Threading: every session call runs on `cameraQueue`, and frames are delivered to the
  /// delegate on that queue. Nothing here touches the main thread.
  nonisolated final class CameraFrameProvider: NSObject, FrameProvider, @unchecked Sendable {
    var isRunning: Bool { captureSession.isRunning }
    weak var delegate: FrameProviderDelegate?

    /// The session, for an `AVCaptureVideoPreviewLayer` on the debug screen only.
    var previewSession: AVCaptureSession { captureSession }

    private let captureDevice: AVCaptureDevice?
    private let captureSession: AVCaptureSession
    private let videoOutput = AVCaptureVideoDataOutput()

    /// Queue used for all camera session work so the main thread stays responsive.
    private let cameraQueue = DispatchQueue(label: "nemo.camera", qos: .userInitiated)

    /// Only read and written on `cameraQueue`.
    private var isConfigured = false

    private let log = Logger(subsystem: "nemo-software", category: "camera")

    override init() {
      self.captureDevice = bestCaptureDevice()
      self.captureSession = AVCaptureSession()
      super.init()
    }

    // MARK: - FrameProvider

    func setupSession() async throws(FrameProviderError) {
      guard captureDevice != nil else {
        log.info("No camera on this device; skipping capture setup")
        throw .noCamera
      }

      switch AVCaptureDevice.authorizationStatus(for: .video) {
      case .authorized:
        break
      case .notDetermined:
        guard await AVCaptureDevice.requestAccess(for: .video) else { throw .permissionDenied }
      default:
        throw .permissionDenied
      }

      let result: Result<Void, FrameProviderError> = await withCheckedContinuation { continuation in
        cameraQueue.async {
          continuation.resume(returning: self.configure())
        }
      }
      try result.get()
    }

    func start() {
      cameraQueue.async { [weak self] in
        guard let self, self.isConfigured, !self.captureSession.isRunning else { return }
        self.captureSession.startRunning()
      }
    }

    func stop() {
      cameraQueue.async { [weak self] in
        guard let self, self.captureSession.isRunning else { return }
        self.captureSession.stopRunning()
      }
    }

    // MARK: - Configuration

    /// Runs on `cameraQueue`.
    private func configure() -> Result<Void, FrameProviderError> {
      if isConfigured { return .success(()) }
      guard let device = captureDevice else { return .failure(.noCamera) }

      captureSession.beginConfiguration()
      defer { captureSession.commitConfiguration() }

      // 1080p is close to ARKit's 1920×1440, so the building check sees similar pixels on
      // both providers, and it's enough for 15–30 cm house numbers at 10–20 m.
      if captureSession.canSetSessionPreset(.hd1920x1080) {
        captureSession.sessionPreset = .hd1920x1080
      }

      do {
        let input = try AVCaptureDeviceInput(device: device)
        guard captureSession.canAddInput(input) else {
          return .failure(.configurationFailed("Can't add camera input"))
        }
        captureSession.addInput(input)
      } catch {
        return .failure(.configurationFailed(error.localizedDescription))
      }

      // Bi-planar YCbCr matches ARKit's `capturedImage`, and Vision reads it without a
      // conversion. Late frames are dropped instead of queued, so we always see the newest.
      videoOutput.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey as String:
          kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
      ]
      videoOutput.alwaysDiscardsLateVideoFrames = true
      guard captureSession.canAddOutput(videoOutput) else {
        return .failure(.configurationFailed("Can't add video output"))
      }
      captureSession.addOutput(videoOutput)
      videoOutput.setSampleBufferDelegate(self, queue: cameraQueue)

      // 30 fps is plenty for perception and saves battery (plan section 11).
      do {
        try device.lockForConfiguration()
        let frameDuration = CMTime(value: 1, timescale: 30)
        if device.activeFormat.videoSupportedFrameRateRanges.contains(where: {
          $0.minFrameDuration <= frameDuration && frameDuration <= $0.maxFrameDuration
        }) {
          device.activeVideoMinFrameDuration = frameDuration
          device.activeVideoMaxFrameDuration = frameDuration
        }
        device.unlockForConfiguration()
      } catch {
        log.error("Couldn't set frame rate: \(error.localizedDescription)")
      }

      isConfigured = true
      log.info("Camera configured: \(device.localizedName)")
      return .success(())
    }
  }

  // MARK: - Video frame delegate

  nonisolated extension CameraFrameProvider: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
      _ output: AVCaptureOutput,
      didOutput sampleBuffer: CMSampleBuffer,
      from connection: AVCaptureConnection
    ) {
      // Stays on `cameraQueue`. The pipeline decides whether to process or drop the frame.
      guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
      delegate?.processFrame(self, buffer: pixelBuffer)
    }
  }

#else

  /// Non-iOS stub so the project still compiles on macOS/visionOS simulators.
  nonisolated final class CameraFrameProvider: NSObject, FrameProvider {
    var isRunning: Bool { false }
    weak var delegate: FrameProviderDelegate?

    func setupSession() async throws(FrameProviderError) {
      throw .noCamera
    }

    func start() {}
    func stop() {}
  }

#endif
