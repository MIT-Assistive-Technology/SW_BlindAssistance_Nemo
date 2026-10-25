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
  public final class Speaker: SpeechOutput {
    private let synthesizer = AVSpeechSynthesizer()
    private var audioSessionConfigured = false

    public init() {}

    /// Speak a phrase, interrupting anything currently spoken.
    ///
    /// The chatter guard ("don't repeat the same phrase within a few seconds") lives in
    /// `SpeechChannel`, so every channel shares one policy.
    public func speak(_ text: String) {
      guard !text.isEmpty else { return }
      configureAudioSessionIfNeeded()
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

    /// Spoken audio that ducks music and mixes with the Uber app, and keeps working with
    /// the screen locked (the `audio` background mode is in app/Info.plist).
    /// TODO (FE-8): interruption and route-change handling, and the beacon's mixing rules.
    private func configureAudioSessionIfNeeded() {
      guard !audioSessionConfigured else { return }
      audioSessionConfigured = true
      let session = AVAudioSession.sharedInstance()
      do {
        try session.setCategory(
          .playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
        try session.setActive(true)
      } catch {
        // Speech is a convenience here; losing the session must not take the app down.
        print("[Speaker] audio session setup failed: \(error.localizedDescription)")
      }
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
