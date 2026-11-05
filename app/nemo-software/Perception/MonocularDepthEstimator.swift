//  MonocularDepthEstimator.swift
//  nemo-software
//
//  Depth on phones without LiDAR: Depth Anything V2 **Small** as a Core ML model
//  (Apache-2.0 — the Base and Large checkpoints are non-commercial, per the plan's
//  license table). Apple's converted model is at
//  huggingface.co/apple/coreml-depth-anything-v2-small; drop it in the target as
//  `DepthAnythingV2Small.mlmodel`.
//
//  Its output is relative inverse depth — larger means closer, with no metric
//  scale — so it feeds `FreeSpaceAnalyzer`'s relative path, which reports blocked
//  slices without distances and can't see drops. Phones with LiDAR don't need it:
//  `ARGuide` reads `sceneDepth` instead.
//
//  With no model in the bundle the estimator is nil and nothing runs, matching the
//  pipeline's other optional pieces.
//

import CoreML
import CoreVideo
import Foundation
import ImageIO
import Vision

/// Anything that can turn a camera frame into a relative depth map, so the pipeline
/// can swap the real model for a fake in tests.
nonisolated public protocol DepthEstimator: AnyObject {
  /// Relative inverse depth for one frame (larger = closer, normalized 0...1), or
  /// nil when it can't run. Called on the perception queue; the buffer must not be
  /// kept past the call.
  func disparityMap(
    for pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation
  ) -> DisparityFrame?
}

nonisolated final class MonocularDepthEstimator: DepthEstimator, @unchecked Sendable {
  private let mlModel: VNCoreMLModel?

  /// Nil when the model isn't in the bundle — estimation simply doesn't run.
  init?(modelName: String = "DepthAnythingV2Small") {
    guard let url = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc"),
      let model = try? MLModel(contentsOf: url),
      let visionModel = try? VNCoreMLModel(for: model)
    else { return nil }
    mlModel = visionModel
  }

  /// Explicit model for tests and off-bundle wiring.
  init(model: VNCoreMLModel) {
    mlModel = model
  }

  func disparityMap(
    for pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation
  ) -> DisparityFrame? {
    guard let mlModel else { return nil }
    let request = VNCoreMLRequest(model: mlModel)
    request.imageCropAndScaleOption = .scaleFill
    let handler = VNImageRequestHandler(
      cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
    do {
      try handler.perform([request])
    } catch {
      print("[MonocularDepthEstimator] \(error.localizedDescription)")
      return nil
    }
    guard let observation = request.results?.first else { return nil }
    if let pixels = (observation as? VNPixelBufferObservation)?.pixelBuffer {
      return Self.read(pixelBuffer: pixels)
    }
    if let array = (observation as? VNCoreMLFeatureValueObservation)?.featureValue
      .multiArrayValue
    {
      return Self.read(multiArray: array)
    }
    return nil
  }

  /// Reads a single-channel output image (float16, float32 or 8-bit) and normalizes
  /// it to 0...1, so the analyzer doesn't care which flavour the model emits.
  private static func read(pixelBuffer: CVPixelBuffer) -> DisparityFrame? {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

    var values = [Float](repeating: 0, count: width * height)
    switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
    case kCVPixelFormatType_OneComponent32Float:
      for row in 0..<height {
        values.withUnsafeMutableBufferPointer { destination in
          destination.baseAddress!.advanced(by: row * width).update(
            from: base.advanced(by: row * bytesPerRow).assumingMemoryBound(to: Float.self),
            count: width)
        }
      }
    case kCVPixelFormatType_OneComponent16Half:
      for row in 0..<height {
        let src = base.advanced(by: row * bytesPerRow).assumingMemoryBound(
          to: Float16.self)
        for col in 0..<width { values[row * width + col] = Float(src[col]) }
      }
    case kCVPixelFormatType_OneComponent8:
      for row in 0..<height {
        let src = base.advanced(by: row * bytesPerRow).assumingMemoryBound(
          to: UInt8.self)
        for col in 0..<width { values[row * width + col] = Float(src[col]) / 255 }
      }
    default:
      return nil
    }
    return DisparityFrame(values: normalize(values), width: width, height: height)
  }

  private static func read(multiArray: MLMultiArray) -> DisparityFrame? {
    let shape = multiArray.shape.map { $0.intValue }
    let height = shape.count >= 2 ? shape[shape.count - 2] : 0
    let width = shape.count >= 1 ? shape[shape.count - 1] : 0
    guard width > 0, height > 0, multiArray.count == width * height else { return nil }
    var values = [Float](repeating: 0, count: multiArray.count)
    for i in 0..<multiArray.count {
      values[i] = multiArray[i].floatValue
    }
    return DisparityFrame(values: normalize(values), width: width, height: height)
  }

  private static func normalize(_ values: [Float]) -> [Float] {
    guard let lo = values.min(), let hi = values.max(), hi > lo else { return values }
    let span = hi - lo
    return values.map { ($0 - lo) / span }
  }
}
