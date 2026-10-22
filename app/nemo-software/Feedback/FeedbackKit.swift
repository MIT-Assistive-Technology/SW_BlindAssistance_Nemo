//  FeedbackKit.swift
//  nemo-software
//
//  The only place that makes sound, speech or vibration. Guidance code emits
//  semantic `FeedbackEvent`s (defined in Logic/); FeedbackKit plays each one on the
//  channels the rider switched on in their `FeedbackProfile`.
//  Never call AVSpeechSynthesizer, AVAudioEngine or Core Haptics from guidance code.
//

import Foundation
import os

/// Routes feedback events to speech, the spatial beacon and haptics.
///
/// - Critical events (warnings, lost, arrival, exit on the curb side) go out on at
///   least 2 channels when 2 are available, even if the profile switched one off.
/// - The beacon is steered directly through `beacon` (`setTarget`, `setListenerHeading`).
public final class FeedbackKit {
  /// Spoken phrases (text only from `Phrases`).
  public let speech: SpeechChannel
  /// Spatial HRTF beacon. Steer it with `beacon.setTarget(...)` and `beacon.setListenerHeading(_:)`.
  public let beacon: BeaconChannel
  /// Core Haptics patterns.
  public let haptics: HapticsChannel

  private let audio: AudioSessionManager
  private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "nemo-software", category: "FeedbackKit")
  private var isPaused = false

  /// How long the beacon stays ducked after a warning, in seconds.
  private static let warningDuckSeconds: TimeInterval = 4

  public init(
    speech: SpeechChannel = SpeechChannel(),
    beacon: BeaconChannel = BeaconChannel(),
    haptics: HapticsChannel = HapticsChannel(),
    audio: AudioSessionManager = .shared
  ) {
    self.speech = speech
    self.beacon = beacon
    self.haptics = haptics
    self.audio = audio

    audio.onInterruption = { [weak self] began, shouldResume in
      self?.handleInterruption(began: began, shouldResume: shouldResume)
    }
    audio.onRouteChange = { [weak self] _ in
      self?.beacon.routeChanged()
    }
    audio.onMediaServicesReset = { [weak self] in
      self?.beacon.rebuildAfterMediaReset()
    }
  }

  /// Applies a changed profile right away (beacon on/off and volume). Call from Settings.
  public func update(profile: FeedbackProfile) {
    beacon.setVolume(Float(profile.beaconVolume))
    if !profile.beaconOn { beacon.stop() }
  }

  /// Plays one event on the channels the profile enables.
  /// - Parameter force: skip the speech chatter guard (use for "Repeat / Where am I").
  public func emit(_ event: FeedbackEvent, profile: FeedbackProfile, force: Bool = false) {
    update(profile: profile)
    let critical = Self.isCritical(event)
    // While paused only safety-critical events get through.
    if isPaused && !critical { return }

    if case .warning = event { beacon.duck(for: Self.warningDuckSeconds) }
    if case .arrival = event { beacon.stop() }

    // When the beacon is playing it already carries direction; don't also speak it.
    let beaconCarriesDirection = profile.beaconOn && beacon.isRunning
    let speakIt = !(Self.isDirectionCue(event) && beaconCarriesDirection)

    var delivered = 0
    if profile.voiceOn, speakIt,
      speech.play(event, verbosity: profile.verbosity, units: profile.units, critical: critical, force: force)
    {
      delivered += 1
    }
    if profile.hapticsOn, haptics.play(event) { delivered += 1 }

    guard critical, delivered < 2 else { return }
    // Critical: top up to 2 channels with whatever the profile left off.
    if !profile.voiceOn,
      speech.play(event, verbosity: profile.verbosity, units: profile.units, critical: true, force: force)
    {
      delivered += 1
    }
    if delivered < 2, !profile.hapticsOn, haptics.play(event) { delivered += 1 }
    if delivered < 2 {
      log.notice("Critical event reached \(delivered, privacy: .public) channel(s)")
    }
  }

  /// Silences everything immediately (Stop button, "Stop guiding").
  public func stopAll() {
    speech.stop()
    beacon.stop()
    haptics.stop()
  }

  /// Pauses guidance output (magic tap). Critical events still play.
  public func pause() {
    isPaused = true
    speech.stop()
    beacon.pause()
    haptics.stop()
  }

  /// Resumes after `pause()`.
  public func resume() {
    isPaused = false
    beacon.resume()
  }

  // MARK: - Private

  private func handleInterruption(began: Bool, shouldResume: Bool) {
    if began {
      speech.stop()
      beacon.interruptionBegan()
    } else if shouldResume, !isPaused {
      beacon.interruptionEnded()
    }
  }

  private static func isCritical(_ event: FeedbackEvent) -> Bool {
    switch event {
    case .warning, .lost, .arrival, .exitCurbSide: return true
    default: return false
    }
  }

  private static func isDirectionCue(_ event: FeedbackEvent) -> Bool {
    if case .direction = event { return true }
    return false
  }
}
