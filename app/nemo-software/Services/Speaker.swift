//  Speaker.swift
//  nemo-software
//
//  Text to speech. Guidance code never calls this directly: it emits FeedbackEvents and
//  `SpeechChannel` picks the words (see Feedback/Phrases.swift).
//

import AVFoundation
import Foundation

/// Anything that can say a phrase. Lets tests record what would have been spoken, and
/// leaves room for a queue that sits behind VoiceOver later.
public protocol SpeechOutput: AnyObject {
  func speak(_ text: String)
  func stop()
}

#if os(iOS)

  /// Verbalizes short status messages to the user.
  public final class Speaker: NSObject, SpeechOutput {
    private let synthesizer = AVSpeechSynthesizer()

    public override init() {
      super.init()
      synthesizer.delegate = self
    }

    /// Speak a phrase, interrupting anything currently spoken.
    ///
    /// The chatter guard ("don't repeat the same phrase within a few seconds") lives in
    /// `SpeechChannel`, so every channel shares one policy.
    public func speak(_ text: String) {
      guard !text.isEmpty else { return }
      // Other audio is ducked until the phrase ends; AudioSessionManager owns the session.
      AudioSessionManager.shared.setSpeaking(true)
      let utterance = AVSpeechUtterance(string: text)
      // Use the voice and rate the rider already set up for VoiceOver, instead of
      // forcing en-US. This is the whole reason the app sounds familiar to them.
      utterance.prefersAssistiveTechnologySettings = true
      synthesizer.stopSpeaking(at: .immediate)
      synthesizer.speak(utterance)
    }

    /// Stop any speech in progress (magic tap / Back Tap "stop").
    public func stop() {
      synthesizer.stopSpeaking(at: .immediate)
    }

    /// A cancel is usually followed at once by the next phrase, so check on the next turn
    /// of the main queue whether anything is still being spoken.
    private func speechMayHaveEnded() {
      DispatchQueue.main.async { [self] in
        if !synthesizer.isSpeaking { AudioSessionManager.shared.setSpeaking(false) }
      }
    }
  }

  extension Speaker: AVSpeechSynthesizerDelegate {
    nonisolated public func speechSynthesizer(
      _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
      Task { @MainActor in self.speechMayHaveEnded() }
    }

    nonisolated public func speechSynthesizer(
      _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
    ) {
      Task { @MainActor in self.speechMayHaveEnded() }
    }
  }

#else

  /// Non-iOS stub.
  public final class Speaker: SpeechOutput {
    public init() {}
    public func speak(_ text: String) {
      print("[Speaker] would say: \(text)")
    }
    public func stop() {}
  }

#endif
