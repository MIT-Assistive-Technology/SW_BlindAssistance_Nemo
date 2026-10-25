//  FeedbackKit.swift
//  nemo-software
//
//  The only place that makes sound, speech or vibration. Guidance code emits
//  semantic events; FeedbackKit plays each one on the channels the rider switched on
//  in their profile. Never call AVSpeechSynthesizer or Core Haptics from guidance code.
//

import Foundation

/// What happened, not how to present it. `nonisolated`, so guidance running off the
/// main actor can emit events; the channels that play them are main-actor bound.
nonisolated public enum FeedbackEvent: Sendable {
  case direction(offsetDegrees: Double)
  case distance(meters: Double)
  case bearingLock(metersToDoor: Double?)
  case landmark(phrase: String)
  /// The camera read the building where the map said it would be (CV-9). `text` came
  /// from the bundle's `recognize.text`, so nothing free-form is spoken.
  case buildingConfirmed(text: String, offsetDegrees: Double?)
  /// Read, but not where the building should be: the same number elsewhere.
  case buildingUncertain(text: String)
  /// The camera check couldn't run, and says so rather than failing silently.
  case cameraCheckUnavailable(CameraCheckProblem)
  case doorDetected(offsetDegrees: Double, meters: Double)
  case warning(String)
  case lost
  case arrival
  // No free-text case on purpose: every spoken phrase is written in Phrases so the
  // certainty-word test (SAFE-1) can check all of them.

  /// Live compass reading for the heading screen (FE-3).
  case heading(degrees: Double, accuracyDegrees: Double)
  /// The compass is too rough to steer by; ask for a figure eight (FE-3).
  case compassCalibration
  /// The device has no compass at all.
  case headingUnavailable
  /// Location permission is denied or restricted. Spoken, not just shown.
  case locationPermissionDenied

  /// "I'm in the car" tracking started / stopped (FE-13).
  case rideTracking(started: Bool)
  /// Said the moment the car stops, before the side of street is known (FE-13).
  case exitCurbSide
  /// The phone thinks the car has stopped but won't act on it alone: ask the rider
  /// whether this is the drop-off, with the distance to the entrance so the question
  /// can be answered (FE-13).
  case possibleDropOff(metersToDoor: Double?)
  /// The side-of-street result, with the walk left to the door when it's known (FE-13).
  case sideOfStreet(SideOfStreetAnswer, SideOfStreetContext)
  /// The side couldn't be decided, so the rider is asked (FE-13).
  case askSideOfStreet(SideOfStreetContext)
  /// What the map says about the destination, spoken at setup (bundle from FE-11).
  case destinationBrief(DestinationBrief)

  /// A destination lookup started: the rider tapped something, so make a sound (FE-11).
  case lookingUpDestination
  /// ...and failed. Spoken, never left on screen for someone to notice.
  case destinationLookupFailed(LookupFailure)
  /// An action needs a destination and there isn't one yet.
  case noDestinationLoaded
  /// The bundle couldn't be written to the phone, so the walk may need a signal.
  case bundleNotSavedForOffline

  // MARK: The walk (FE-10)

  /// Guidance is starting: stand still while the anchor settles.
  case startingGuidance
  /// Guidance ended, by the rider or by the trip finishing. It never ends silently.
  case guidanceStopped
  /// The door is across the road, so guidance waits for the rider to cross.
  case waitingToCrossStreet
  /// The first-steps check failed: say so before giving any more guidance.
  case directionUncertain
  /// The last few meters, with the door facts from the bundle.
  case finalApproach(metersToDoor: Double?, DestinationBrief)
}

/// One output: speech, spatial beacon, haptics, earcons, Apple Watch.
public protocol FeedbackChannel: AnyObject {
  var name: String { get }
  func play(_ event: FeedbackEvent)
  /// `force` means the rider asked for this again ("repeat", "where am I"), so any
  /// anti-repeat rule must get out of the way.
  func play(_ event: FeedbackEvent, force: Bool)
  func stop()
}

extension FeedbackChannel {
  public func play(_ event: FeedbackEvent, force: Bool) { play(event) }
}

public final class FeedbackKit {
  private var channels: [FeedbackChannel]

  public init(channels: [FeedbackChannel]) {
    self.channels = channels
  }

  /// - Parameter force: set when the rider explicitly asked to hear it again. Without
  ///   it a "repeat" tap can land inside the chatter guard and do nothing at all, which
  ///   to someone who can't see the screen is indistinguishable from a broken app.
  public func emit(_ event: FeedbackEvent, force: Bool = false) {
    // TODO (FE-6/FE-7): route by the rider's FeedbackProfile (which channels are on,
    // per-event overrides, verbosity). Critical events (.warning, .lost, .arrival) go
    // to at least 2 channels by default.
    channels.forEach { $0.play(event, force: force) }
  }

  /// Stop everything immediately (magic tap / Back Tap "stop").
  public func stopAll() {
    channels.forEach { $0.stop() }
  }
}

/// Speech channel built on the existing `Speaker`.
public final class SpeechChannel: FeedbackChannel {
  public let name = "speech"
  /// Don't repeat the same phrase inside this window (the chatter guard, FE-6).
  public var repeatGuard: TimeInterval = 4

  private let speaker: any SpeechOutput
  private let units: Units
  private let now: () -> Date
  private var lastPhrase: String?
  private var lastSpokenAt: Date?

  public init(
    speaker: any SpeechOutput,
    units: Units = .feet,
    now: @escaping () -> Date = Date.init
  ) {
    self.speaker = speaker
    self.units = units
    self.now = now
  }

  public func play(_ event: FeedbackEvent) {
    play(event, force: false)
  }

  public func play(_ event: FeedbackEvent, force: Bool) {
    guard let phrase = Self.phrase(for: event, units: units) else { return }
    let moment = now()
    if !force, phrase == lastPhrase, let last = lastSpokenAt,
      moment.timeIntervalSince(last) < repeatGuard
    {
      return
    }
    lastPhrase = phrase
    lastSpokenAt = moment
    speaker.speak(phrase)
  }

  public func stop() {
    lastPhrase = nil
    lastSpokenAt = nil
    speaker.stop()
  }

  /// Event -> phrase. Pure and public so the mapping is unit tested without audio.
  /// Returns nil for events this channel has no words for yet.
  public static func phrase(for event: FeedbackEvent, units: Units = .feet) -> String? {
    switch event {
    case .heading(let degrees, let accuracy):
      return Phrases.heading(degrees: degrees, accuracyDegrees: accuracy)
    case .compassCalibration:
      return Phrases.compassCalibration
    case .headingUnavailable:
      return Phrases.headingUnavailable
    case .locationPermissionDenied:
      return Phrases.locationPermissionDenied
    case .rideTracking(let started):
      return started ? Phrases.rideTrackingStarted : Phrases.rideTrackingStopped
    case .exitCurbSide:
      return Phrases.exitCurbSide
    case .possibleDropOff(let metersToDoor):
      return Phrases.possibleDropOff(metersToDoor: metersToDoor, units: units)
    case .sideOfStreet(let answer, let context):
      switch answer {
      case .sameSide:
        return Phrases.sameSideOfStreet(metersToDoor: context.metersToDoor, units: units)
      case .acrossStreet:
        return Phrases.acrossStreet(metersToCrossing: context.metersToCrossing, units: units)
      case .unknown:
        // Never guess a side. Ask, and name the street so the question is answerable.
        return Phrases.askSideOfStreet(
          entranceStreet: context.entranceStreet,
          streetSideDescription: context.streetSideDescription)
      }
    case .askSideOfStreet(let context):
      return Phrases.askSideOfStreet(
        entranceStreet: context.entranceStreet,
        streetSideDescription: context.streetSideDescription)
    case .destinationBrief(let brief):
      return Phrases.destinationBrief(brief, units: units)
    case .lookingUpDestination:
      return Phrases.lookingUpEntrance
    case .destinationLookupFailed(let failure):
      return Phrases.lookupFailed(failure)
    case .noDestinationLoaded:
      return Phrases.noDestinationLoaded
    case .bundleNotSavedForOffline:
      return Phrases.bundleNotSavedForOffline
    case .distance(let meters):
      return Phrases.distance(meters: meters, units: units).capitalizedFirst
    case .direction(let offset):
      return Phrases.turn(offsetDegrees: offset).capitalizedFirst

    case .startingGuidance:
      return Phrases.startingGuidance
    case .guidanceStopped:
      return Phrases.guidanceStopped
    case .waitingToCrossStreet:
      return Phrases.waitingToCrossStreet
    case .bearingLock(let metersToDoor):
      return Phrases.bearingLock(metersToDoor: metersToDoor, units: units)
    case .directionUncertain:
      return Phrases.directionUncertain
    case .lost:
      return Phrases.offRoute
    case .finalApproach(let metersToDoor, let brief):
      return Phrases.finalApproach(metersToDoor: metersToDoor, brief: brief, units: units)
    case .arrival:
      return Phrases.arrivedAtDoor

    case .buildingConfirmed(let text, let offsetDegrees):
      return Phrases.buildingConfirmed(text: text, offsetDegrees: offsetDegrees)
    case .buildingUncertain(let text):
      return Phrases.buildingUncertain(text: text)
    case .cameraCheckUnavailable(let problem):
      return Phrases.cameraCheckUnavailable(problem)

    // TODO (FE-6): these need reviewed phrases once the landmark and door-detector work
    // lands, written here and listed in Phrases.all so SAFE-1 checks them. `.warning`
    // carries free text and should be replaced by specific cases.
    case .landmark, .doorDetected, .warning:
      return nil
    }
  }
}

extension String {
  fileprivate var capitalizedFirst: String {
    guard let first else { return self }
    return first.uppercased() + dropFirst()
  }
}

// TODO (FE-4): BeaconChannel — AVAudioEngine + AVAudioEnvironmentNode (HRTF) tone at the door.
// TODO (FE-5): HapticsChannel — Core Haptics AHAP patterns (tick, lock, pulse, arrival, warning).
