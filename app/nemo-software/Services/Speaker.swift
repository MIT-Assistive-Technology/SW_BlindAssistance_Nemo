//  Speaker.swift
//  nemo-software
//
//  Text-to-speech. Uses the rider's VoiceOver voice and rate
//  (`prefersAssistiveTechnologySettings`). While VoiceOver is running and the app is in
//  the foreground, phrases go out as VoiceOver announcements so they queue with
//  VoiceOver instead of talking over it.
//
//  Guidance code should go through FeedbackKit / SpeechChannel, which take the text from
//  `Phrases`; don't pass free text here from guidance code.
//

import AVFoundation
import Foundation
import UIKit

/// Speaks short phrases and keeps the audio session ducking other audio while it talks.
public final class Speaker: NSObject {
  /// `.high` interrupts whatever is being said; `.normal` waits behind a `.high` phrase.
  public enum Priority {
    case normal
    case high
  }

  private let synthesizer = AVSpeechSynthesizer()
  private let audio: AudioSessionManager
  /// Utterances handed to the synthesizer that haven't finished or been cancelled.
  private var inFlight: Set<ObjectIdentifier> = []
  private var highPriorityInFlight: Set<ObjectIdentifier> = []

  public override init() {
    self.audio = .shared
    super.init()
    synthesizer.delegate = self
  }

  /// Speaks `text`. Kept for older call sites; same as `speak(text, priority: .normal)`.
  public func speak(_ text: String) {
    speak(text, priority: .normal)
  }

  /// Speaks `text` with the given priority.
  public func speak(_ text: String, priority: Priority) {
    if UIAccessibility.isVoiceOverRunning, UIApplication.shared.applicationState == .active {
      // Queue normal phrases behind VoiceOver; let high-priority ones interrupt it.
      let announcement = NSAttributedString(
        string: text,
        attributes: [.accessibilitySpeechQueueAnnouncement: priority == .normal]
      )
      UIAccessibility.post(notification: .announcement, argument: announcement)
      return
    }

    if synthesizer.isSpeaking {
      switch priority {
      case .high:
        synthesizer.stopSpeaking(at: .immediate)
      case .normal:
        // Don't cut off a warning; otherwise a stale phrase is replaced by the new one.
        if highPriorityInFlight.isEmpty { synthesizer.stopSpeaking(at: .immediate) }
      }
    }

    let utterance = AVSpeechUtterance(string: text)
    utterance.prefersAssistiveTechnologySettings = true
    let id = ObjectIdentifier(utterance)
    inFlight.insert(id)
    if priority == .high { highPriorityInFlight.insert(id) }
    audio.beginSpeech()
    synthesizer.speak(utterance)
  }

  /// Stops any speech in progress immediately.
  public func stop() {
    synthesizer.stopSpeaking(at: .immediate)
  }

  private func utteranceEnded(_ id: ObjectIdentifier) {
    inFlight.remove(id)
    highPriorityInFlight.remove(id)
    if inFlight.isEmpty { audio.endSpeech() }
  }
}

extension Speaker: AVSpeechSynthesizerDelegate {
  public nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
  ) {
    let id = ObjectIdentifier(utterance)
    Task { @MainActor [weak self] in self?.utteranceEnded(id) }
  }

  public nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
  ) {
    let id = ObjectIdentifier(utterance)
    Task { @MainActor [weak self] in self?.utteranceEnded(id) }
  }
}
