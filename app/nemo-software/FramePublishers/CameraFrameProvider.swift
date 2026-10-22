//  CameraFrameProvider.swift
//  nemo-software
//
//  Live camera capture using AVFoundation, used by the debug camera screen.
//  During guidance ARKit owns the camera (the two can't run together) and
//  `ARFrameProvider` forwards `ARFrame.capturedImage` through this same protocol.
//

import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import os

#if canImport(UIKit)
  import UIKit
#endif

#if os(iOS)

  /// Picks the best available back camera, or nil (Simulator, CI, no permission).
  func bestCaptureDevice() -> AVCaptureDevice? {
    let deviceTypes: [AVCaptureDevice.DeviceType] = [
      .builtInTripleCamera,
      .builtInDualWideCamera,
      .builtInDualCamera,
      .builtInWideAngleCamera,
    ]
    let discoverySession = AVCaptureDevice.DiscoverySession(
      deviceTypes: deviceTypes, mediaType: .video, position: .back)
    return discoverySession.devices.first
  }

  final class CameraFrameProvider: NSObject, FrameProvider {
    var isRunning: Bool { captureSession.isRunning }
    weak var delegate: FrameProviderDelegate?

    private let captureDevice: AVCaptureDevice?
    /// Used on `cameraQueue` (start/stop) and on main (configuration); AVCaptureSession is
    /// safe to use from both.
    private nonisolated(unsafe) let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var isConfigured = false

    /// Queue used for all camera session work so the main thread stays responsive.
    private let cameraQueue = DispatchQueue(label: "nemo.camera", qos: .userInitiated)
    /// True while the delegate is still handling the previous frame; newer frames are dropped.
    private let busy = OSAllocatedUnfairLock(initialState: false)

    override init() {
      self.captureDevice = bestCaptureDevice()
      super.init()
    }

    // MARK: - FrameProvider

    func setupSession() {
      guard !isConfigured else { return }
      guard let device = captureDevice else {
        print("[CameraFrameProvider] No camera (Simulator or CI); skipping setup.")
        return
      }
      isConfigured = true
      Task { @MainActor [weak self] in
        guard await AVCaptureDevice.requestAccess(for: .video) else {
          print("[CameraFrameProvider] Camera permission denied.")
          return
        }
        self?.configure(device)
      }
    }

    func start() {
      let session = captureSession
      cameraQueue.async {
        if !session.isRunning { session.startRunning() }
      }
    }

    func stop() {
      let session = captureSession
      cameraQueue.async {
        if session.isRunning { session.stopRunning() }
      }
    }

    private func configure(_ device: AVCaptureDevice) {
      captureSession.beginConfiguration()
      defer { captureSession.commitConfiguration() }
      guard let input = try? AVCaptureDeviceInput(device: device),
        captureSession.canAddInput(input), captureSession.canAddOutput(videoOutput)
      else {
        print("[CameraFrameProvider] Could not configure the capture session.")
        return
      }
      captureSession.addInput(input)
      videoOutput.alwaysDiscardsLateVideoFrames = true
      videoOutput.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
      ]
      captureSession.addOutput(videoOutput)
      videoOutput.setSampleBufferDelegate(self, queue: cameraQueue)
    }
  }

  // MARK: - Video frame delegate (camera queue)

  extension CameraFrameProvider: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
      _ output: AVCaptureOutput,
      didOutput sampleBuffer: CMSampleBuffer,
      from connection: AVCaptureConnection
    ) {
      guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
      let accept = busy.withLock { isBusy -> Bool in
        if isBusy { return false }
        isBusy = true
        return true
      }
      guard accept else { return }
      // The current delegate (PerceptionPipeline) is main-actor isolated.
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.delegate?.processFrame(self, buffer: pixelBuffer)
        self.busy.withLock { $0 = false }
      }
    }
  }

#else

  /// Non-iOS stub so the project still compiles on macOS/visionOS simulators.
  final class CameraFrameProvider: NSObject, FrameProvider {
    var isRunning: Bool { false }
    weak var delegate: FrameProviderDelegate?

    func setupSession() {
      print("[CameraFrameProvider] Camera capture is only implemented for iOS.")
    }

    func start() {}
    func stop() {}
  }

#endif
