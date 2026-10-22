//  SpeechChannel.swift
//  nemo-software
//
//  Spoken feedback. Every word comes from `Phrases.text(for:verbosity:units:)`, the one
//  reviewed phrase table, so the certainty-word test covers everything the app says.
//

import Foundation

/// Speaks feedback events through `Speaker`, with a chatter guard.
public final class SpeechChannel {
  private let speaker: Speaker
  /// Phrase -> when it was last spoken.
  private var lastSpoken: [String: Date] = [:]

  /// The same phrase is not repeated within this many seconds.
  public static let repeatWindow: TimeInterval = 4

  public init(speaker: Speaker = Speaker()) {
    self.speaker = speaker
  }

  /// Speaks the phrase for `event`, if `Phrases` has one and it wasn't just said.
  /// - Parameters:
  ///   - critical: interrupts current speech instead of queueing behind it.
  ///   - force: ignore the chatter guard (rider asked to repeat).
  /// - Returns: true if something was spoken.
  @discardableResult
  public func play(
    _ event: FeedbackEvent, verbosity: Verbosity, units: Units, critical: Bool, force: Bool = false
  ) -> Bool {
    guard let text = Phrases.text(for: event, verbosity: verbosity, units: units), !text.isEmpty else {
      return false
    }
    let now = Date()
    lastSpoken = lastSpoken.filter { now.timeIntervalSince($0.value) < Self.repeatWindow }
    if !force, lastSpoken[text] != nil { return false }
    lastSpoken[text] = now
    speaker.speak(text, priority: critical ? .high : .normal)
    return true
  }

  /// Stops speech immediately.
  public func stop() {
    speaker.stop()
  }
}
