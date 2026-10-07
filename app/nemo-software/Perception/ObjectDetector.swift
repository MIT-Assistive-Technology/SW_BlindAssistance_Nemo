//  ObjectDetector.swift
//  nemo-software
//
//  Protocol for any object detector. Using a protocol lets tests inject a fake
//  detector and lets the app swap models without touching the pipeline.
//

import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

public protocol ObjectDetector: AnyObject {
  /// Run detection on a single frame.
  /// - Parameters:
  ///   - pixelBuffer: the raw image data
  ///   - filter: predicate that decides whether a detection is relevant
  ///   - orientation: image orientation to pass to Vision
  /// - Returns: detections that survived the filter
  func detect(
    _ pixelBuffer: CVPixelBuffer,
    filter: @escaping (Detection) -> Bool,
    orientation: CGImagePropertyOrientation
  ) -> [Detection]
}
