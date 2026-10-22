//  AudioSessionManager.swift
//  nemo-software
//
//  Owns the app's AVAudioSession. Category `.playback` / mode `.spokenAudio` so guidance
//  keeps playing with the screen locked (`audio` background mode is in Info.plist).
//  While speech plays, other audio (music, the rideshare app) is ducked and spoken audio
//  such as podcasts is paused; while only the beacon plays, we mix with it.
//

import AVFoundation
import Foundation
import os

/// Configures and activates the shared audio session, and reports interruptions and
/// route changes to FeedbackKit.
public final class AudioSessionManager {
  public static let shared = AudioSessionManager()

  /// Called on the main actor. `began == false` with `shouldResume == true` means
  /// output may restart (e.g. a phone call ended).
  public var onInterruption: ((_ began: Bool, _ shouldResume: Bool) -> Void)?
  /// Called on the main actor when headphones are connected or removed.
  public var onRouteChange: ((_ headphonesConnected: Bool) -> Void)?
  /// Called on the main actor after the media server restarted; audio graphs must be rebuilt.
  public var onMediaServicesReset: (() -> Void)?

  /// True while a phone call or another app holds the audio.
  public private(set) var isInterrupted = false

  private let session = AVAudioSession.sharedInstance()
  private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "nemo-software", category: "AudioSession")
  private var speechActive = false
  private var beaconActive = false
  private var appliedOptions: AVAudioSession.CategoryOptions?
  private var observers: [NSObjectProtocol] = []

  /// Outputs where the HRTF beacon conveys direction.
  private static let headphonePorts: Set<AVAudioSession.Port> = [
    .headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP,
  ]

  private init() {
    observe()
  }

  /// True when the current output is headphones or earbuds (spatial audio works).
  public var headphonesConnected: Bool {
    session.currentRoute.outputs.contains { Self.headphonePorts.contains($0.portType) }
  }

  /// Speech is about to play: duck others and interrupt spoken audio.
  public func beginSpeech() {
    speechActive = true
    apply()
  }

  /// All queued speech has finished.
  public func endSpeech() {
    speechActive = false
    apply()
  }

  /// The beacon engine is about to start.
  public func beaconWillStart() {
    beaconActive = true
    apply()
  }

  /// The beacon engine stopped.
  public func beaconDidStop() {
    beaconActive = false
    apply()
  }

  // MARK: - Private

  private func apply() {
    guard speechActive || beaconActive else {
      deactivate()
      return
    }
    // Ducking only takes effect on activation, so re-activate after changing options.
    let options: AVAudioSession.CategoryOptions =
      speechActive ? [.duckOthers, .interruptSpokenAudioAndMixWithOthers] : [.mixWithOthers]
    do {
      if appliedOptions != options {
        try session.setCategory(.playback, mode: .spokenAudio, options: options)
        appliedOptions = options
      }
      try session.setActive(true)
    } catch {
      log.error("Audio session activation failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func deactivate() {
    do {
      try session.setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      // Commonly "busy" while the synthesizer finishes its I/O; harmless.
      log.debug("Audio session deactivation deferred: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func observe() {
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) {
        [weak self] note in
        let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
        MainActor.assumeIsolated {
          self?.handleInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw)
        }
      })
    observers.append(
      center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) {
        [weak self] note in
        let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
        MainActor.assumeIsolated {
          self?.handleRouteChange(reasonRaw: reasonRaw)
        }
      })
    observers.append(
      center.addObserver(
        forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.handleMediaServicesReset()
        }
      })
  }

  private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt?) {
    guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
    switch type {
    case .began:
      isInterrupted = true
      log.info("Audio interrupted")
      onInterruption?(true, false)
    case .ended:
      isInterrupted = false
      let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0)
      let shouldResume = options.contains(.shouldResume)
      if shouldResume { apply() }
      log.info("Audio interruption ended, resume: \(shouldResume, privacy: .public)")
      onInterruption?(false, shouldResume)
    @unknown default:
      break
    }
  }

  private func handleRouteChange(reasonRaw: UInt?) {
    guard let reasonRaw, let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }
    switch reason {
    case .newDeviceAvailable, .oldDeviceUnavailable, .override, .routeConfigurationChange:
      let headphones = headphonesConnected
      log.info("Audio route changed, headphones: \(headphones, privacy: .public)")
      onRouteChange?(headphones)
    default:
      break
    }
  }

  private func handleMediaServicesReset() {
    log.notice("Media services were reset")
    appliedOptions = nil
    apply()
    onMediaServicesReset?()
  }
}
