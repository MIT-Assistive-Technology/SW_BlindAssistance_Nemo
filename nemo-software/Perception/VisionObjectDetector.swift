//  VisionObjectDetector.swift
//  nemo-software
//
//  Concrete ObjectDetector backed by a CoreML model loaded through Vision.
//  Left as a TODO skeleton: wire in your own .mlmodel or use the default Vision
//  model for a quick first build.
//

import CoreVideo
import Foundation
import ImageIO
import Vision

#if canImport(UIKit)
  import UIKit
#endif

final class VisionObjectDetector: ObjectDetector {
  // TODO: Replace with the VNCoreMLModel created from your bundled .mlmodel.
  // Example:
  //   private let mlModel: VNCoreMLModel = try! VNCoreMLModel(for: yolo11n().model)
  //
  private let mlModel: VNCoreMLModel?

  init() {
    // TODO: Load the model here. If loading fails, set `mlModel` to nil and
    // the detector should return an empty array (or throw, if you prefer).
    self.mlModel = nil
    print("[VisionObjectDetector] init – remember to load a real CoreML model")
  }

  func detect(
    _ pixelBuffer: CVPixelBuffer,
    filter: @escaping (Detection) -> Bool,
    orientation: CGImagePropertyOrientation
  ) -> [Detection] {
    if mlModel == nil {
      // TODO: Return a sensible fallback (empty detections) and log the missing model.
      return []
    }

    // TODO: Build a VNCoreMLRequest, run it with a VNImageRequestHandler on the
    // pixel buffer, cast results to [VNRecognizedObjectObservation], convert to
    // `Detection` values, and apply the filter.
    //
    // Pseudocode:
    //   let request = VNCoreMLRequest(model: mlModel)
    //   request.imageCropAndScaleOption = .scaleFill
    //   let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
    //   try handler.perform([request])
    //   guard let results = request.results as? [VNRecognizedObjectObservation] else { return [] }
    //   return results.map { Detection(...) }.filter(filter)
    //
    return []
  }
}

// MARK: - Convenience helpers used by the converter

extension Detection {
  /// Creates a Detection from a Vision observation.
  init(from observation: VNRecognizedObjectObservation) {
    self.init(
      boundingBox: observation.boundingBox,
      labels: observation.labels.map {
        DetectionLabel(identifier: $0.identifier, confidence: $0.confidence)
      },
      id: observation.uuid
    )
  }
}
