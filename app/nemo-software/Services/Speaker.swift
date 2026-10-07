//  Speaker.swift
//  nemo-software
//
//  Simple text-to-speech wrapper. Call `speak(_:)` whenever the app wants to
//  tell the user something, and `stop()` when the stream is turned off.
//

import AVFoundation
import Foundation

#if os(iOS)

  /// Verbalizes short status messages to the user.
  public final class Speaker {
    private let synthesizer = AVSpeechSynthesizer()

    public init() {}

    /// Speak a phrase, interrupting anything currently spoken.
    ///
    /// In a real app you may want to avoid repeating the same phrase too often
    /// (a "chatter guard"). This is the natural place to add that.
    public func speak(_ text: String) {
      // TODO: Implement TTS.
      //
      // Pseudocode:
      //   let utterance = AVSpeechUtterance(string: text)
      //   utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
      //   synthesizer.stopSpeaking(at: .immediate)
      //   synthesizer.speak(utterance)
      print("[Speaker] would say: \(text)")
    }

    /// Stop any speech in progress.
    public func stop() {
      // TODO: Call synthesizer.stopSpeaking(at: .immediate).
    }
  }

#else

  /// Non-iOS stub.
  public final class Speaker {
    public init() {}
    public func speak(_ text: String) {
      print("[Speaker] would say: \(text)")
    }
    public func stop() {}
  }

#endif
