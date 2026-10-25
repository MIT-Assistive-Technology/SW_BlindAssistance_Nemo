//  RecognizedNumber.swift
//  nemo-software
//
//  A building or street number read from a camera frame. Kept free of Vision
//  types so the pipeline and UI can use it without importing that framework.
//

import CoreGraphics
import Foundation

nonisolated public struct RecognizedNumber: Identifiable, Sendable {
  /// The text line Vision read, such as "77" or "12B".
  public let text: String

  /// The number token spoken to the rider. Same as `text` with spacing removed.
  public let value: String

  public let confidence: Float

  /// Normalized bounding box, origin at the bottom left, the same space Vision uses.
  public let boundingBox: CGRect

  public let id: UUID

  public init(
    text: String,
    value: String,
    confidence: Float,
    boundingBox: CGRect,
    id: UUID = UUID()
  ) {
    self.text = text
    self.value = value
    self.confidence = confidence
    self.boundingBox = boundingBox
    self.id = id
  }
}
