//  SignColor.swift
//  nemo-software
//
//  US street-name blades are green with light lettering. A line that merely
//  looks like "Main St" on a storefront is not treated as a street sign.
//

import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

nonisolated enum SignColor {
  /// True when enough of the box behind the text is street-sign green.
  static func isGreenSign(
    in buffer: CVPixelBuffer,
    normalizedBox: CGRect,
    orientation: CGImagePropertyOrientation
  ) -> Bool {
    let box = expanded(normalizedBox)
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    guard width > 0, height > 0 else { return false }

    let readOnly = CVPixelBufferLockFlags.readOnly
    guard CVPixelBufferLockBaseAddress(buffer, readOnly) == kCVReturnSuccess else { return false }
    defer { CVPixelBufferUnlockBaseAddress(buffer, readOnly) }

    var green = 0
    var sampled = 0
    for stepX in 0..<4 {
      for stepY in 0..<4 {
        let nx = box.minX + box.width * (CGFloat(stepX) + 0.5) / 4
        let ny = box.minY + box.height * (CGFloat(stepY) + 0.5) / 4
        guard let pixel = rawPixel(nx: nx, ny: ny, width: width, height: height, orientation: orientation),
          let sample = sample(buffer, x: pixel.x, y: pixel.y)
        else { continue }
        sampled += 1
        if sample.isStreetGreen { green += 1 }
      }
    }
    guard sampled >= 8 else { return false }
    return green * 2 >= sampled
  }

  private static func expanded(_ box: CGRect) -> CGRect {
    let grown = box.insetBy(dx: -box.width * 0.25, dy: -box.height * 0.8)
    return grown.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
  }

  /// Vision's box is upright, origin bottom-left. The buffer is the camera's raw pixels.
  private static func rawPixel(
    nx: CGFloat,
    ny: CGFloat,
    width: Int,
    height: Int,
    orientation: CGImagePropertyOrientation
  ) -> (x: Int, y: Int)? {
    let rawX: Int
    let rawY: Int
    switch orientation {
    case .right:
      // Rotating the buffer 90° clockwise stands it up. Upright x runs up the buffer.
      rawX = Int((1 - ny) * CGFloat(width))
      rawY = height - 1 - Int(nx * CGFloat(height))
    case .up:
      rawX = Int(nx * CGFloat(width))
      rawY = Int((1 - ny) * CGFloat(height))
    default:
      return nil
    }
    guard rawX >= 0, rawY >= 0, rawX < width, rawY < height else { return nil }
    return (rawX, rawY)
  }

  private static func sample(
    _ buffer: CVPixelBuffer,
    x: Int,
    y: Int
  ) -> Sample? {
    let format = CVPixelBufferGetPixelFormatType(buffer)
    if format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
      || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    {
      return sampleNV12(buffer, x: x, y: y)
    }
    if format == kCVPixelFormatType_32BGRA {
      return sampleBGRA(buffer, x: x, y: y)
    }
    return nil
  }

  private static func sampleNV12(_ buffer: CVPixelBuffer, x: Int, y: Int) -> Sample? {
    guard CVPixelBufferGetPlaneCount(buffer) >= 2,
      let yBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
      let uvBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)
    else { return nil }
    let yStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
    let uvStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
    let luma = UnsafeRawPointer(yBase).load(fromByteOffset: y * yStride + x, as: UInt8.self)
    let uvOffset = (y / 2) * uvStride + (x / 2) * 2
    let cb = UnsafeRawPointer(uvBase).load(fromByteOffset: uvOffset, as: UInt8.self)
    let cr = UnsafeRawPointer(uvBase).load(fromByteOffset: uvOffset + 1, as: UInt8.self)
    return Sample(y: Int(luma), cb: Int(cb), cr: Int(cr))
  }

  private static func sampleBGRA(_ buffer: CVPixelBuffer, x: Int, y: Int) -> Sample? {
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    let offset = y * stride + x * 4
    let b = Int(UnsafeRawPointer(base).load(fromByteOffset: offset, as: UInt8.self))
    let g = Int(UnsafeRawPointer(base).load(fromByteOffset: offset + 1, as: UInt8.self))
    let r = Int(UnsafeRawPointer(base).load(fromByteOffset: offset + 2, as: UInt8.self))
    let luma = (r * 299 + g * 587 + b * 114) / 1000
    let cb = 128 + ((b - luma) * 564) / 1000
    let cr = 128 + ((r - luma) * 713) / 1000
    return Sample(y: luma, cb: cb, cr: cr)
  }

  private struct Sample {
    let y: Int
    let cb: Int
    let cr: Int

    /// MUTCD green is dark, low on red (Cr), and not a neutral white or beige sign.
    var isStreetGreen: Bool {
      cr < 115 && cb > 70 && cb < 150 && y > 25 && y < 210
    }
  }
}
