//  VisionObjectDetector.swift
//  nemo-software
//
//  Concrete ObjectDetector backed by a Core ML model loaded through Vision. The
//  model must be Apache-2.0 (ADR 0007 — Ultralytics YOLO is AGPL, so don't bundle
//  it): RF-DETR Nano/Small, or a Create ML model trained on the hazard classes.
//  Expected labels: people, cars, bikes, poles and cones; COCO names map through
//  `HazardSighting.Kind(label:)`.
//
//  Drop a `HazardDetector.mlmodel` into the target and it compiles into the app
//  bundle as `HazardDetector.mlmodelc`. With no model in the bundle the detector
//  stays off and returns empty arrays — the same contract the skeleton had.
//

import CoreVideo
import Foundation
import ImageIO
import Vision

nonisolated final class VisionObjectDetector: ObjectDetector {
  private let mlModel: VNCoreMLModel?

  /// Loads the bundled hazard model, or stays off when there isn't one.
  convenience init(modelName: String = "HazardDetector") {
    self.init(model: Self.loadModel(named: modelName))
  }

  /// Explicit model, for tests and for wiring a model that isn't in the bundle.
  init(model: VNCoreMLModel?) {
    mlModel = model
    if model == nil {
      print("[VisionObjectDetector] no bundled model; detection is off")
    }
  }

  private static func loadModel(named name: String) -> VNCoreMLModel? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc"),
      let model = try? MLModel(contentsOf: url),
      let visionModel = try? VNCoreMLModel(for: model)
    else { return nil }
    return visionModel
  }

  func detect(
    _ pixelBuffer: CVPixelBuffer,
    filter: @escaping (Detection) -> Bool,
    orientation: CGImagePropertyOrientation
  ) -> [Detection] {
    guard let mlModel else { return [] }

    let request = VNCoreMLRequest(model: mlModel)
    // The model sees the whole frame squashed to its input size; bounding boxes come
    // back in the same normalized space Vision uses everywhere else.
    request.imageCropAndScaleOption = .scaleFill

    let handler = VNImageRequestHandler(
      cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
    do {
      try handler.perform([request])
    } catch {
      print("[VisionObjectDetector] \(error.localizedDescription)")
      return []
    }

    guard let results = request.results as? [VNRecognizedObjectObservation] else {
      return []
    }
    return results.map { Detection(from: $0) }.filter(filter)
  }
}

// MARK: - Convenience helpers used by the converter

nonisolated extension Detection {
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
