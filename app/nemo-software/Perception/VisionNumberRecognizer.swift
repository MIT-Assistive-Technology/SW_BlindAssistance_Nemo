//  VisionNumberRecognizer.swift
//  nemo-software
//
//  Apple Vision text recognition for the building check (CV-9).
//  One request reads house numbers and green street-name signs. Called on the
//  perception queue with the camera's own buffer. It must finish before returning
//  so the camera can reuse that buffer. Frames stay on the phone.
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

  func read(
    _ pixelBuffer: CVPixelBuffer,
    orientation: CGImagePropertyOrientation,
    expectedBundleTexts: [String]
  ) -> CameraTextRead {
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
      return CameraTextRead()
    }

    guard let observations = request.results else { return CameraTextRead() }

    var bestNumbers: [String: RecognizedNumber] = [:]
    var bestSigns: [String: RecognizedStreetSign] = [:]
    for observation in observations {
      guard
        let candidate = observation.topCandidates(3).first(where: {
          $0.confidence >= minimumConfidence
        })
      else { continue }

      if let value = HouseNumberParser.houseNumber(in: candidate.string) {
        let number = RecognizedNumber(
          text: candidate.string,
          value: value,
          confidence: candidate.confidence,
          boundingBox: observation.boundingBox,
          id: observation.uuid
        )
        if let existing = bestNumbers[value], existing.confidence >= number.confidence {
          continue
        }
        bestNumbers[value] = number
        continue
      }

      guard
        let street = StreetSignParser.streetName(in: candidate.string),
        SignColor.isGreenSign(
          in: pixelBuffer, normalizedBox: observation.boundingBox, orientation: orientation)
      else { continue }

      let matched = BundleTextMatcher.match(read: street, expected: expectedBundleTexts)
      if !expectedBundleTexts.isEmpty && matched == nil { continue }
      let sign = RecognizedStreetSign(
        text: matched ?? street,
        readText: street,
        matchedBundleText: matched,
        confidence: candidate.confidence,
        boundingBox: observation.boundingBox,
        id: observation.uuid
      )
      let key = matched ?? street
      if let existing = bestSigns[key], existing.confidence >= sign.confidence {
        continue
      }
      bestSigns[key] = sign
    }

    return CameraTextRead(
      numbers: bestNumbers.values.sorted { $0.confidence > $1.confidence },
      streetSigns: bestSigns.values.sorted { $0.confidence > $1.confidence }
    )
  }
}
