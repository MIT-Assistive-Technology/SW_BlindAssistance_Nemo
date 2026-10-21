//  FrameProvider.swift
//  nemo-software
//
//  Abstracts the camera source so the rest of the app can run against the live
//  camera, a video file, or (later) ARKit / Meta glasses without changing the pipeline.
//
//  `nonisolated`: the project's default actor isolation is MainActor, but frames are
//  produced and consumed on background queues.
//

import CoreVideo
import Foundation

/// Why a provider can't stream. Shown and spoken on the camera screen.
nonisolated public enum FrameProviderError: Error, Equatable, Sendable {
  /// No camera on this device (Simulator, CI).
  case noCamera
  /// The rider turned camera access off.
  case permissionDenied
  /// The capture session couldn't be configured.
  case configurationFailed(String)
}

nonisolated public protocol FrameProviderDelegate: AnyObject {
  /// Called on the provider's private queue for every new frame. Return quickly: hand the
  /// buffer to your own queue or drop it. Don't keep the buffer after you're done with it,
  /// or the camera runs out of buffers.
  /// - buffer: pixel buffer of the live camera frame, 420YpCbCr (the same format as ARKit's
  ///   `capturedImage`), in landscape. Vision needs `.right` for a portrait iPhone.
  func processFrame(_ provider: any FrameProvider, buffer: CVPixelBuffer)
}

nonisolated public protocol FrameProvider: AnyObject {
  /// Whether the provider is currently streaming frames.
  var isRunning: Bool { get }

  var delegate: FrameProviderDelegate? { get set }

  /// Begin streaming. Call after `setupSession()` succeeds.
  func start()

  /// End streaming.
  func stop()

  /// One-time setup (permissions, session plumbing). Call before `start()`.
  /// Safe to call more than once.
  func setupSession() async throws(FrameProviderError)
}
