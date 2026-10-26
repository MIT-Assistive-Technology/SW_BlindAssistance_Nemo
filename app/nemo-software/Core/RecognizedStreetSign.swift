//  RecognizedStreetSign.swift
//  nemo-software
//
//  A street-name sign read from a camera frame. The text handed to navigation
//  must already be in the entrance bundle. Jing's `BuildingSighting` on
//  `jing-nav` is the consumer: its bearing comes from `normalizedX` plus the
//  phone's heading, via `Geo.photoRayBearing`, once that branch is merged.
//

import CoreGraphics
import Foundation

nonisolated public struct RecognizedStreetSign: Identifiable, Sendable {
  /// What navigation may repeat. The bundle's own spelling when it matched,
  /// otherwise the line Vision read (debug only, before a destination is loaded).
  public let text: String

  /// The line Vision read, before bundle matching.
  public let readText: String

  /// The bundle string this sign matched, if a destination list was provided.
  public let matchedBundleText: String?

  public let confidence: Float

  /// Normalized bounding box, origin at the bottom left, the same space Vision uses.
  public let boundingBox: CGRect

  /// Horizontal center, 0...1 from the left of the upright frame.
  public var normalizedX: Double { Double(boundingBox.midX) }

  public let id: UUID

  public init(
    text: String,
    readText: String,
    matchedBundleText: String?,
    confidence: Float,
    boundingBox: CGRect,
    id: UUID = UUID()
  ) {
    self.text = text
    self.readText = readText
    self.matchedBundleText = matchedBundleText
    self.confidence = confidence
    self.boundingBox = boundingBox
    self.id = id
  }
}
