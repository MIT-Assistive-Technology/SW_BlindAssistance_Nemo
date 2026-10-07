//  FeedbackKit.swift
//  nemo-software
//
//  The only place that makes sound, speech or vibration. Guidance code emits
//  semantic events; FeedbackKit plays each one on the channels the rider switched on
//  in their profile. Never call AVSpeechSynthesizer or Core Haptics from guidance code.
//

import Foundation

/// What happened, not how to present it.
public enum FeedbackEvent: Sendable {
  case direction(offsetDegrees: Double)
  case distance(meters: Double)
  case bearingLock
  case landmark(phrase: String)
  case buildingConfirmed(text: String)
  case doorDetected(offsetDegrees: Double, meters: Double)
  case warning(String)
  case lost
  case arrival
  // No free-text case on purpose: every spoken phrase is written in SpeechChannel so the
  // certainty-word test (SAFE-1) can check all of them.
}

/// One output: speech, spatial beacon, haptics, earcons, Apple Watch.
public protocol FeedbackChannel: AnyObject {
  var name: String { get }
  func play(_ event: FeedbackEvent)
  func stop()
}

public final class FeedbackKit {
  private var channels: [FeedbackChannel]

  public init(channels: [FeedbackChannel]) {
    self.channels = channels
  }

  public func emit(_ event: FeedbackEvent) {
    // TODO (FE-6/FE-7): route by the rider's FeedbackProfile (which channels are on,
    // per-event overrides, verbosity). Critical events (.warning, .lost, .arrival) go
    // to at least 2 channels by default.
    channels.forEach { $0.play(event) }
  }

  /// Stop everything immediately (magic tap / Back Tap "stop").
  public func stopAll() {
    channels.forEach { $0.stop() }
  }
}

/// Speech channel built on the existing `Speaker`.
public final class SpeechChannel: FeedbackChannel {
  public let name = "speech"
  private let speaker: Speaker

  public init(speaker: Speaker) {
    self.speaker = speaker
  }

  public func play(_ event: FeedbackEvent) {
    // TODO (FE-6): turn events into short phrases per verbosity, e.g.
    //   .distance(18)          -> "60 feet" (respect the rider's units)
    //   .landmark("bench …")   -> "Bench on your left"
    //   .doorDetected(+10, 3)  -> "Door, slightly right, 10 feet"
    //   .buildingConfirmed     -> "That looks like your building"
    //   .arrival               -> "The door should be right in front of you. Feel for the handle."
    // Never use certainty words ("That's your building", "You've arrived") (SAFE-1).
    _ = event
  }

  public func stop() { speaker.stop() }
}

// TODO (FE-4): BeaconChannel — AVAudioEngine + AVAudioEnvironmentNode (HRTF) tone at the door.
// TODO (FE-5): HapticsChannel — Core Haptics AHAP patterns (tick, lock, pulse, arrival, warning).
