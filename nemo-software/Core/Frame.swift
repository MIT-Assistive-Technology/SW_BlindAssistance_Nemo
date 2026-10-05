//  Frame.swift
//  nemo-software
//
//  Domain representation of one camera frame plus the spatial context in which
//  it was captured. This is the currency passed through the perception pipeline.
//

import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

/// A single frame of video plus everything we know about the world at that instant.
public struct Frame {
  /// The captured pixel buffer.
  public let pixelBuffer: CVPixelBuffer

  /// Capture orientation of the image data.
  public let orientation: CGImagePropertyOrientation

  /// Where the device was when this frame was captured.
  public let location: LocationSnapshot?

  public init(
    pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    location: LocationSnapshot? = nil
  ) {
    self.pixelBuffer = pixelBuffer
    self.orientation = orientation
    self.location = location
  }
}
