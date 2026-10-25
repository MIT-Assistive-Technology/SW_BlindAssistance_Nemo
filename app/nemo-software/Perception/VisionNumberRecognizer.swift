//  VisionNumberRecognizer.swift
//  nemo-software
//
//  Apple Vision text recognition for the building-number check (CV-9).
//  Called on the perception queue with the camera's own buffer. It must finish
//  before returning so the camera can reuse that buffer. Frames stay on the phone.
//
//  Tuned for a number plaque at roughly 10–20 m on a 1080p frame: accurate
//  recognition, language correction off (it rewrites digits), and a lower
//  minimum text height than Vision's default so a small "77" still counts.
//

import CoreVideo
import Foundation
import ImageIO
import Vision

nonisolated final class VisionNumberRecognizer: NumberRecognizer, @unchecked Sendable {
  /// Drop reads Vision itself is unsure about. Text scores run lower than object detection.
  private let minimumConfidence: Float = 0.3

  /// Fraction of the image height. Default is 1/32; lower finds smaller, farther digits.
  private let minimumTextHeight: Float = 0.012

  func recognize(
    _ pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation
  ) -> [RecognizedNumber] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["en-US"]
    request.automaticallyDetectsLanguage = false
    request.minimumTextHeight = minimumTextHeight

    let handler = VNImageRequestHandler(
      cvPixelBuffer: pixelBuffer,
      orientation: orientation,
      options: [:]
    )
    do {
      try handler.perform([request])
    } catch {
      print("[VisionNumberRecognizer] \(error.localizedDescription)")
      return []
    }

    guard let observations = request.results else { return [] }

    var bestByValue: [String: RecognizedNumber] = [:]
    for observation in observations {
      guard
        let candidate = observation.topCandidates(3).first(where: {
          $0.confidence >= minimumConfidence
        }),
        let value = HouseNumberParser.houseNumber(in: candidate.string)
      else { continue }

      let number = RecognizedNumber(
        text: candidate.string,
        value: value,
        confidence: candidate.confidence,
        boundingBox: observation.boundingBox,
        id: observation.uuid
      )
      if let existing = bestByValue[value], existing.confidence >= number.confidence {
        continue
      }
      bestByValue[value] = number
    }

    return bestByValue.values.sorted { $0.confidence > $1.confidence }
  }
}
