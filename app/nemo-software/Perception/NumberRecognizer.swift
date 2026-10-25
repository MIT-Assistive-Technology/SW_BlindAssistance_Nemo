//  NumberRecognizer.swift
//  nemo-software
//
//  Reads building numbers from a camera frame. A protocol so tests can inject
//  canned reads and the live Vision implementation can be swapped later.
//

import CoreVideo
import Foundation
import ImageIO

nonisolated public protocol NumberRecognizer: AnyObject, Sendable {
  /// Numbers visible in this frame. Empty when nothing numeric was read.
  /// Safe to call off the main thread. The pixel buffer must stay alive for the call.
  func recognize(
    _ pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation
  ) -> [RecognizedNumber]
}
