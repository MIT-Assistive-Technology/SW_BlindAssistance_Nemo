//  NumberRecognizer.swift
//  nemo-software
//
//  One pass over a camera frame for the building check: house numbers and
//  green street-name signs. A protocol so tests can inject canned reads.
//

import CoreVideo
import Foundation
import ImageIO

nonisolated public struct CameraTextRead: Sendable {
  public var numbers: [RecognizedNumber]
  public var streetSigns: [RecognizedStreetSign]

  public init(numbers: [RecognizedNumber] = [], streetSigns: [RecognizedStreetSign] = []) {
    self.numbers = numbers
    self.streetSigns = streetSigns
  }
}

nonisolated public protocol NumberRecognizer: AnyObject, Sendable {
  /// House numbers and street signs in this frame.
  /// Safe to call off the main thread. The pixel buffer must stay alive for the call.
  /// `expectedBundleTexts` are `recognize.text`, the entrance street, and the building
  /// name. When the list is empty, street signs are returned as read, for the debug screen.
  /// When it is set, a sign is kept only if it matches one of those strings.
  func read(
    _ pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    expectedBundleTexts: [String]
  ) -> CameraTextRead
}
