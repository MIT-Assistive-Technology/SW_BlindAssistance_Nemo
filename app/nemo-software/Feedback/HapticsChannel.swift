//  HapticsChannel.swift
//  nemo-software
//
//  Core Haptics feedback. Patterns live in Resources/Haptics/*.ahap (tick, lock,
//  distancePulse, arrival, warning). Core Haptics doesn't play in the background, so
//  this channel reports "not delivered" there and FeedbackKit uses another channel.
//

import CoreHaptics
import Foundation
import UIKit
import os

/// The vibration patterns the app uses. The raw value is the .ahap file name.
public enum HapticPattern: String, CaseIterable, Sendable {
  case tick
  case lock
  case distancePulse
  case arrival
  case warning
}

/// Plays AHAP patterns for feedback events. A no-op on devices without haptics.
public final class HapticsChannel {
  /// False on hardware without a Taptic Engine.
  public let isSupported: Bool

  private var engine: CHHapticEngine?
  private var patterns: [HapticPattern: CHHapticPattern] = [:]
  private var player: CHHapticPatternPlayer?
  private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "nemo-software", category: "Haptics")

  public init() {
    isSupported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    guard isSupported else { return }
    loadPatterns()
    makeEngine()
  }

  /// True when a pattern can play right now (supported hardware, app in the foreground).
  public var isAvailable: Bool {
    isSupported && UIApplication.shared.applicationState == .active
  }

  /// Plays the pattern for `event`, if it has one.
  /// - Returns: true if a pattern started.
  @discardableResult
  public func play(_ event: FeedbackEvent) -> Bool {
    guard let pattern = Self.pattern(for: event) else { return false }
    return play(pattern)
  }

  /// Plays one pattern, replacing any pattern still playing.
  @discardableResult
  public func play(_ pattern: HapticPattern) -> Bool {
    guard isAvailable, let hapticPattern = patterns[pattern] else { return false }
    do {
      if engine == nil { makeEngine() }
      guard let engine else { return false }
      try engine.start()
      try player?.stop(atTime: CHHapticTimeImmediate)
      let newPlayer = try engine.makePlayer(with: hapticPattern)
      try newPlayer.start(atTime: CHHapticTimeImmediate)
      player = newPlayer
      return true
    } catch {
      log.error("Haptic \(pattern.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
      return false
    }
  }

  /// Stops any pattern in progress.
  public func stop() {
    try? player?.stop(atTime: CHHapticTimeImmediate)
    player = nil
  }

  // MARK: - Private

  private static func pattern(for event: FeedbackEvent) -> HapticPattern? {
    switch event {
    case .direction, .landmark: return .tick
    case .bearingLock, .buildingConfirmed, .doorDetected: return .lock
    case .distance: return .distancePulse
    case .warning, .lost, .offRoute, .exitCurbSide: return .warning
    case .arrival: return .arrival
    case .brief: return nil
    }
  }

  private func makeEngine() {
    do {
      let engine = try CHHapticEngine()
      engine.playsHapticsOnly = true
      engine.isAutoShutdownEnabled = true
      // Handlers run on a system queue; hop to the main actor.
      engine.stoppedHandler = { @Sendable [weak self] reason in
        Task { @MainActor in self?.engineStopped(reason) }
      }
      engine.resetHandler = { @Sendable [weak self] in
        Task { @MainActor in self?.engineReset() }
      }
      self.engine = engine
    } catch {
      log.error("Haptic engine unavailable: \(error.localizedDescription, privacy: .public)")
      engine = nil
    }
  }

  private func engineStopped(_ reason: CHHapticEngine.StoppedReason) {
    // The next play() calls start() again; nothing to keep.
    player = nil
    log.debug("Haptic engine stopped: \(reason.rawValue, privacy: .public)")
  }

  private func engineReset() {
    // The haptic server restarted; players are invalid. Restart lazily on the next play().
    player = nil
    do {
      try engine?.start()
    } catch {
      engine = nil
    }
  }

  private func loadPatterns() {
    for pattern in HapticPattern.allCases {
      if let url = Bundle.main.url(forResource: pattern.rawValue, withExtension: "ahap"),
        let loaded = try? CHHapticPattern(contentsOf: url)
      {
        patterns[pattern] = loaded
      } else if let fallback = try? Self.fallbackPattern(pattern) {
        log.notice("Missing \(pattern.rawValue, privacy: .public).ahap; using built-in pattern")
        patterns[pattern] = fallback
      }
    }
  }

  /// A simple transient used when an .ahap file is missing from the bundle.
  private static func fallbackPattern(_ pattern: HapticPattern) throws -> CHHapticPattern {
    let intensity: Float
    switch pattern {
    case .tick: intensity = 0.5
    case .distancePulse: intensity = 0.6
    case .lock, .arrival, .warning: intensity = 1.0
    }
    let event = CHHapticEvent(
      eventType: .hapticTransient,
      parameters: [
        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7),
      ],
      relativeTime: 0
    )
    return try CHHapticPattern(events: [event], parameters: [])
  }
}
