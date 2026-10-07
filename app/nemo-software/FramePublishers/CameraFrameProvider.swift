//  CameraFrameProvider.swift
//  nemo-software
//
//  Live camera capture using AVFoundation. The TODOs focus on the minimum needed
//  to stream frames to the perception pipeline.
//

import AVFoundation
import CoreVideo
import Foundation

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

  /// Plain AVFoundation camera, good for the first detection milestone.
  /// NOTE: once ARKit guidance lands (FE-12), ARKit owns the camera and the two
  /// can't run at the same time. Add an `ARFrameProvider` that forwards
  /// `ARFrame.capturedImage` through this same `FrameProvider` protocol.
  final class CameraFrameProvider: NSObject, FrameProvider {
    var isRunning: Bool { captureSession.isRunning }
    weak var delegate: FrameProviderDelegate?

    private let captureDevice: AVCaptureDevice?
    private let captureSession: AVCaptureSession
    private let videoOutput = AVCaptureVideoDataOutput()

    /// Queue used for all camera session work so the main thread stays responsive.
    private let cameraQueue = DispatchQueue(label: "nemo.camera", qos: .userInitiated)

    override init() {
      self.captureDevice = bestCaptureDevice()
      self.captureSession = AVCaptureSession()
      super.init()
    }

    // MARK: - FrameProvider

    func setupSession() {
      // TODO: Request camera permission and configure the capture session.
      // If `captureDevice` is nil (Simulator/CI), log it and return without crashing.
      //
      // Steps:
      //   1. Call AVCaptureDevice.requestAccess(for: .video) and only proceed if granted.
      //   2. captureSession.beginConfiguration().
      //   3. Add AVCaptureDeviceInput(device: captureDevice) as input.
      //   4. Add videoOutput. Set its alwaysDiscardsLateVideoFrames = true.
      //   5. Commit configuration.
      //   6. Set self as the videoOutput delegate on cameraQueue.
      //
      print("[CameraFrameProvider] setupSession() called – implement me")
    }

    func start() {
      guard !captureSession.isRunning else { return }
      cameraQueue.async { [weak self] in
        self?.captureSession.startRunning()
      }
    }

    func stop() {
      guard captureSession.isRunning else { return }
      cameraQueue.async { [weak self] in
        self?.captureSession.stopRunning()
      }
    }
  }

  // MARK: - Video frame delegate

  extension CameraFrameProvider: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
      _ output: AVCaptureOutput,
      didOutput sampleBuffer: CMSampleBuffer,
      from connection: AVCaptureConnection
    ) {
      // TODO: Extract the CVPixelBuffer from sampleBuffer.imageBuffer and pass
      // it to the delegate. Run on the main actor so SwiftUI updates stay safe.
      //
      // Pseudocode:
      //   guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
      //   DispatchQueue.main.async { [weak self] in
      //     self?.delegate?.processFrame(self, buffer: pixelBuffer)
      //   }
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
