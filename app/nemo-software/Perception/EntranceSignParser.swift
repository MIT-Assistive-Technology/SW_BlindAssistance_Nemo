//  EntranceSignParser.swift
//  nemo-software
//
//  Words on or beside a door that the door finder steers to: ENTRANCE, PUSH, PULL,
//  AUTOMATIC DOOR. A fixed list mapped to `EntranceWord`, so what the rider hears comes
//  from Phrases, never from the camera's raw text.
//
//  EXIT is left out on purpose: an exit-only door is the one door the rider must not
//  be steered to.
//

import CoreGraphics
import Foundation

nonisolated public enum EntranceSignParser {
  /// The entrance word in a line of text Vision read, or nil.
  public static func entranceWord(in text: String) -> EntranceWord? {
    let words = text.uppercased()
      .components(separatedBy: CharacterSet.letters.inverted)
      .filter { !$0.isEmpty }
    guard !words.isEmpty, words.count <= 4 else { return nil }
    if words.contains("EXIT") { return nil }
    if words.contains("AUTOMATIC") || words.contains("AUTO") {
      if words.contains("DOOR") || words.contains("DOORS") { return .automaticDoor }
    }
    if words.contains("ENTRANCE") || words.contains("ENTER") || words.contains("ENTRY") {
      return .entrance
    }
    // PUSH and PULL alone, not inside a sentence ("push button for assistance" still
    // counts: it's on the door).
    if words.first == "PUSH" { return .push }
    if words.first == "PULL" { return .pull }
    return nil
  }
}

nonisolated public struct RecognizedEntranceSign: Identifiable, Sendable {
  public let word: EntranceWord
  public let confidence: Float
  /// Normalized bounding box, origin at the bottom left, the same space Vision uses.
  public let boundingBox: CGRect
  public let id: UUID

  public init(word: EntranceWord, confidence: Float, boundingBox: CGRect, id: UUID = UUID()) {
    self.word = word
    self.confidence = confidence
    self.boundingBox = boundingBox
    self.id = id
  }
}
