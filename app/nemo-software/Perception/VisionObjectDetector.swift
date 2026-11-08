//  VisionObjectDetector.swift
//  nemo-software
//
//  Concrete ObjectDetector backed by a bundled Core ML model. Two model flavours are
//  supported, because they arrive in different shapes:
//
//    - Image-input detectors (Create ML, converted YOLO with NMS). Vision runs them
//      and hands back `VNRecognizedObjectObservation`s.
//    - Tensor-input detectors like the bundled RF-DETR Nano (Apache-2.0, ADR 0007 —
//      Ultralytics YOLO is AGPL, so don't bundle it). Vision can't feed a tensor, so
//      the frame is resized into an NCHW float tensor by hand and the outputs are
//      `boxes` (cx,cy,w,h normalized), `scores` and `labels` (raw COCO category ids).
//
//  Expected labels: people, cars, bikes, poles and cones; COCO names map through
//  `HazardSighting.Kind(label:)`.
//
//  Drop a `HazardDetector.mlmodel` (or `.mlpackage`) into the target and Xcode
//  compiles it into the app bundle as `HazardDetector.mlmodelc`. With no model in the
//  bundle the detector stays off and returns empty arrays — the same contract the
//  skeleton had.
//

import CoreImage
import CoreML
import CoreVideo
import Foundation
import ImageIO
import Vision

nonisolated final class VisionObjectDetector: ObjectDetector {
  /// How the bundled model takes its input, decided once at init.
  private enum Backend {
    /// Vision object-detection request for image-input models.
    case vision(VNCoreMLModel)
    /// Raw `MLModel.prediction` for tensor-input models (RF-DETR).
    case tensor(MLModel)
  }

  private let backend: Backend?

  /// Loads the bundled hazard model, or stays off when there isn't one.
  convenience init(modelName: String = "HazardDetector") {
    self.init(model: Self.loadModel(named: modelName))
  }

  /// Explicit model, for tests and for wiring a model that isn't in the bundle.
  init(model: MLModel?) {
    backend = model.flatMap(Self.makeBackend)
    if backend == nil {
      print("[VisionObjectDetector] no bundled model; detection is off")
    }
  }

  private static func loadModel(named name: String) -> MLModel? {
    // Xcode compiles both .mlmodel sources and .mlpackage into .mlmodelc; the
    // .mlpackage fallback covers a build that copies it through unchanged.
    for ext in ["mlmodelc", "mlpackage"] {
      guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
        continue
      }
      if let model = try? MLModel(contentsOf: url) { return model }
    }
    return nil
  }

  private static func makeBackend(_ model: MLModel) -> Backend {
    let wantsImage = model.modelDescription.inputDescriptionsByName.values.contains {
      $0.type == .image
    }
    if wantsImage, let visionModel = try? VNCoreMLModel(for: model) {
      return .vision(visionModel)
    }
    return .tensor(model)
  }

  func detect(
    _ pixelBuffer: CVPixelBuffer,
    filter: @escaping (Detection) -> Bool,
    orientation: CGImagePropertyOrientation
  ) -> [Detection] {
    switch backend {
    case .vision(let visionModel):
      return detectWithVision(visionModel, pixelBuffer, orientation: orientation)
        .filter(filter)
    case .tensor(let model):
      return detectWithTensor(model, pixelBuffer, orientation: orientation)
        .filter(filter)
    case .none:
      return []
    }
  }

  // MARK: - Vision object detectors (image input)

  private func detectWithVision(
    _ visionModel: VNCoreMLModel,
    _ pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation
  ) -> [Detection] {
    let request = VNCoreMLRequest(model: visionModel)
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
    return results.map { Detection(from: $0) }
  }

  // MARK: - RF-DETR-style detectors (tensor input)

  /// A shared CIContext for the resize; `CIContext` is safe to use concurrently.
  private let ciContext = CIContext()

  /// Preprocess the frame into the model's NCHW float tensor (raw 0–255 RGB — the
  /// bundled RF-DETR has its ImageNet normalization baked into the graph), run the
  /// model, and decode `boxes`/`scores`/`labels` into Detections. Runs on the
  /// caller's queue (the pipeline's serial perception queue).
  private func detectWithTensor(
    _ model: MLModel,
    _ pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation
  ) -> [Detection] {
    guard let (inputName, height, width) = Self.tensorInputShape(model) else {
      return []
    }
    guard
      let tensor = tensor(
        from: pixelBuffer, orientation: orientation, width: width, height: height)
    else { return [] }

    let output: MLFeatureProvider
    do {
      output = try model.prediction(
        from: MLDictionaryFeatureProvider(dictionary: [
          inputName: MLFeatureValue(multiArray: tensor)
        ]))
    } catch {
      print("[VisionObjectDetector] \(error.localizedDescription)")
      return []
    }

    guard let boxes = output.featureValue(for: "boxes")?.multiArrayValue,
      let scores = output.featureValue(for: "scores")?.multiArrayValue,
      let labels = output.featureValue(for: "labels")?.multiArrayValue
    else { return [] }

    let count = scores.shape.count > 1 ? scores.shape[1].intValue : scores.count
    return (0..<count).compactMap { i in
      let score = scores[[0, i as NSNumber]].floatValue
      let box = (0..<4).map { boxes[[0, i as NSNumber, $0 as NSNumber]].floatValue }
      let labelId = labels[[0, i as NSNumber]].intValue
      return Detection(
        boundingBox: Self.normalizedRect(cxcywh: box),
        labels: [DetectionLabel(identifier: Self.cocoName(labelId), confidence: score)])
    }
  }

  /// First multiArray input as (name, height, width) from an NCHW-shaped tensor.
  private static func tensorInputShape(_ model: MLModel) -> (String, Int, Int)? {
    for (name, feature) in model.modelDescription.inputDescriptionsByName {
      guard feature.type == .multiArray,
        let shape = feature.multiArrayConstraint?.shape, shape.count == 4
      else { continue }
      return (name, shape[2].intValue, shape[3].intValue)
    }
    return nil
  }

  /// Resize the frame to the model's input size, honouring `orientation` the same
  /// way Vision would, and pack it NCHW float32 with raw 0–255 channel values.
  private func tensor(
    from pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    width: Int,
    height: Int
  ) -> MLMultiArray? {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
    let scale = CGAffineTransform(
      scaleX: CGFloat(width) / image.extent.width,
      y: CGFloat(height) / image.extent.height)
    ciContext.render(
      image.transformed(by: scale), toBitmap: &bytes, rowBytes: width * 4,
      bounds: CGRect(x: 0, y: 0, width: width, height: height),
      format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))

    guard
      let array = try? MLMultiArray(
        shape: [1, 3, height as NSNumber, width as NSNumber], dataType: .float32)
    else { return nil }
    let hw = width * height
    array.dataPointer.withMemoryRebound(to: Float32.self, capacity: 3 * hw) { dst in
      for channel in 0..<3 {
        var p = dst + channel * hw
        for i in 0..<hw {
          p.pointee = Float32(bytes[i * 4 + channel])
          p += 1
        }
      }
    }
    return array
  }

  /// cx,cy,w,h (top-left origin, like the model's image space) → the normalized
  /// bottom-left rect the rest of the app expects from Vision observations.
  private static func normalizedRect(cxcywh box: [Float]) -> CGRect {
    let x0 = min(max(CGFloat(box[0] - box[2] / 2), 0), 1)
    let x1 = min(max(CGFloat(box[0] + box[2] / 2), 0), 1)
    let y0 = min(max(1 - CGFloat(box[1] + box[3] / 2), 0), 1)
    let y1 = min(max(1 - CGFloat(box[1] - box[3] / 2), 0), 1)
    return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
  }

  /// Raw COCO category ids → names. RF-DETR's label space has gaps (12, 26, 29…),
  /// so an index table would silently mislabel — the map is explicit instead.
  private static func cocoName(_ id: Int) -> String {
    cocoLabels[id] ?? "object"
  }

  private static let cocoLabels: [Int: String] = [
    1: "person", 2: "bicycle", 3: "car", 4: "motorcycle", 5: "airplane",
    6: "bus", 7: "train", 8: "truck", 9: "boat", 10: "traffic light",
    11: "fire hydrant", 13: "stop sign", 14: "parking meter", 15: "bench",
    16: "bird", 17: "cat", 18: "dog", 19: "horse", 20: "sheep",
    21: "cow", 22: "elephant", 23: "bear", 24: "zebra", 25: "giraffe",
    27: "backpack", 28: "umbrella", 31: "handbag", 32: "tie", 33: "suitcase",
    34: "frisbee", 35: "skis", 36: "snowboard", 37: "sports ball", 38: "kite",
    39: "baseball bat", 40: "baseball glove", 41: "skateboard", 42: "surfboard",
    43: "tennis racket", 44: "bottle", 46: "wine glass", 47: "cup", 48: "fork",
    49: "knife", 50: "spoon", 51: "bowl", 52: "banana", 53: "apple",
    54: "sandwich", 55: "orange", 56: "broccoli", 57: "carrot", 58: "hot dog",
    59: "pizza", 60: "donut", 61: "cake", 62: "chair", 63: "couch",
    64: "potted plant", 65: "bed", 67: "dining table", 70: "toilet",
    72: "tv", 73: "laptop", 74: "mouse", 75: "remote", 76: "keyboard",
    77: "cell phone", 78: "microwave", 79: "oven", 80: "toaster", 81: "sink",
    82: "refrigerator", 84: "book", 85: "clock", 86: "vase", 87: "scissors",
    88: "teddy bear", 89: "hair drier", 90: "toothbrush",
  ]
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
