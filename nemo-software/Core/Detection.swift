//  Detection.swift
//  nemo-software
//
//  Value types that abstract Vision/CoreML results so tests and future detectors
//  can produce them without touching the Vision framework.
//

import CoreGraphics
import Foundation

/// One label/confidence pair from an object detector.
public struct DetectionLabel: Sendable {
  public let identifier: String
  public let confidence: Float

  public init(identifier: String, confidence: Float) {
    self.identifier = identifier
    self.confidence = confidence
  }
}

/// A single object detected in a frame.
public struct Detection: Identifiable {
  /// Normalized bounding box in image coordinates (origin bottom-left).
  public let boundingBox: CGRect

  /// Candidate labels, sorted by confidence descending when produced by Vision.
  public let labels: [DetectionLabel]

  /// Confidence of the strongest label.
  public var confidence: Float { labels.first?.confidence ?? 0 }

  /// Stable identity across frames (e.g. Vision observation UUID).
  public let id: UUID

  public init(boundingBox: CGRect, labels: [DetectionLabel], id: UUID = UUID()) {
    self.boundingBox = boundingBox
    self.labels = labels
    self.id = id
  }
}
