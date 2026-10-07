//  FrameProvider.swift
//  nemo-software
//
//  Abstracts the camera source so the rest of the app can run against the live
//  camera, a video file, or (later) Meta glasses without changing the pipeline.
//

import CoreVideo
import Foundation

public protocol FrameProviderDelegate: AnyObject {
  /// Called on the provider's private queue for every new frame.
  /// - buffer: BGRA pixel buffer of the live camera frame.
  func processFrame(_ provider: any FrameProvider, buffer: CVPixelBuffer)
}

public protocol FrameProvider: AnyObject {
  /// Whether the provider is currently streaming frames.
  var isRunning: Bool { get }

  var delegate: FrameProviderDelegate? { get set }

  /// Begin streaming.
  func start()

  /// End streaming.
  func stop()

  /// One-time setup (permissions, session plumbing). Call before `start()`.
  func setupSession()
}
