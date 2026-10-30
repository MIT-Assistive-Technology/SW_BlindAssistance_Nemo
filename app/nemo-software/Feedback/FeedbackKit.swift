//  FeedbackKit.swift
//  nemo-software
//
//  The only place that makes sound, speech or vibration. Guidance code emits
//  semantic events; FeedbackKit plays each one on the channels the rider switched on
//  in their profile. Never call AVSpeechSynthesizer or Core Haptics from guidance code.
//

import AVFoundation
import CoreHaptics
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
  /// Where the beacon should sound, relative to the way the rider faces, sent on every
  /// position or heading update while walking so the tone stays fixed in the world.
  /// nil means there is nothing safe to point at, and the beacon goes quiet. Not spoken.
  case beaconAim(offsetDegrees: Double?)
  /// GPS is too rough (worse than ~15 m) or too old to guide by (SAFE-9). Guidance
  /// holds and says so rather than steering from a guess.
  case positionUncertain
  /// ...and the position is good again.
  case guidanceResumed
  /// Back from off route: turn towards the door again.
  case reorienting
  /// No known safe path (SAFE-4). `roadCrossing` when the way to the door crosses a
  /// road and there's no marked crossing, so guidance waits for the rider (SAFE-3).
  case noSafePath(roadCrossing: Bool)
  /// The way to the door crosses a road (`crosses_road`) and the bundle has a marked
  /// crossing: the rider is guided there first.
  case roadToCross(metersToCrossing: Double?)
  /// At the marked crossing. The app never says when it's safe to cross.
  case atCrossing
  /// Within a few meters, but GPS is too rough to say the door is right there, or the
  /// map only knows the street-facing side.
  case arrivalUncertain
  /// The rider said they're across; guidance can start from the Walk screen.
  case readyToStartGuidance
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
    // FE-8: configure the audio session, and stop every channel when a call interrupts.
    AudioSessionManager.shared.onInterruption = { [weak self] began in
      if began { self?.stopAll() }
    }
    AudioSessionManager.shared.start()
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
  /// The last turn offset spoken, for the hysteresis in `steadied(_:)`.
  private var lastTurnOffset: Double?

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
    guard let phrase = Self.phrase(for: steadied(event), units: units) else { return }
    let moment = now()
    // Critical events are never suppressed, even if they were just said (Trish's rule
    // from FE-6). A `.lost` swallowed because the same words played three seconds ago
    // is the one repeat that actually matters.
    if !force, !Self.isCritical(event), phrase == lastPhrase, let last = lastSpokenAt,
      moment.timeIntervalSince(last) < repeatGuard
    {
      return
    }
    lastPhrase = phrase
    lastSpokenAt = moment
    // A rider's "repeat" is never dropped behind other speech either.
    speaker.speak(phrase, critical: force || Self.isCritical(event))
  }

  public func stop() {
    lastPhrase = nil
    lastSpokenAt = nil
    lastTurnOffset = nil
    speaker.stop()
  }

  /// Degrees past a turn-band edge (10°, 35°, 120°) before the spoken turn changes, so a
  /// rider holding the phone at 34–36° doesn't hear "slightly right", "to your right",
  /// "slightly right".
  public static let turnHysteresisDegrees: Double = 5
  private static let turnBandEdges: [Double] = [10, 35, 120]

  private func steadied(_ event: FeedbackEvent) -> FeedbackEvent {
    guard case .direction(let offset) = event else { return event }
    if let last = lastTurnOffset, (last < 0) == (offset < 0),
      Self.turnBandEdges.contains(where: { edge in
        min(abs(last), abs(offset)) < edge && edge <= max(abs(last), abs(offset))
          && abs(abs(offset) - edge) < Self.turnHysteresisDegrees
      })
    {
      return .direction(offsetDegrees: last)
    }
    lastTurnOffset = offset
    return event
  }

  /// Events the rider must hear even if the same words were just spoken.
  public static func isCritical(_ event: FeedbackEvent) -> Bool {
    switch event {
    // A change of plan is never silent (SAFE-10), so the lines that announce one
    // (reorienting, resumed, the lock) can't be dropped behind a warning either.
    case .warning, .lost, .arrival, .directionUncertain, .locationPermissionDenied,
      .positionUncertain, .noSafePath, .roadToCross, .atCrossing, .arrivalUncertain,
      .reorienting, .guidanceResumed, .bearingLock:
      return true
    default:
      return false
    }
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
    case .arrivalUncertain:
      return Phrases.arrivedNearDoor
    case .positionUncertain:
      return Phrases.positionUncertain
    case .guidanceResumed:
      return Phrases.guidanceResumed
    case .reorienting:
      return Phrases.reorienting
    case .noSafePath(let roadCrossing):
      return roadCrossing ? Phrases.noSafePathAcrossRoad : Phrases.noSafePath
    case .roadToCross(let metersToCrossing):
      return Phrases.roadToCross(metersToCrossing: metersToCrossing, units: units)
    case .atCrossing:
      return Phrases.atCrossing
    case .readyToStartGuidance:
      return Phrases.readyToStartGuidance
    case .beaconAim:
      // The tone carries this; speaking it on every update would drown everything else.
      return nil

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

// HapticsChannel — Core Haptics AHAP patterns (tick, lock, pulse, arrival, warning). Fallback channel for riders who don't use headphones
public final class HapticsChannel: FeedbackChannel {
    public let name = "haptics"
    
    /// Turn taps no closer together than this, or a stream of direction updates
    /// becomes one long buzz.
    public var directionInterval: TimeInterval = 1
    
    private let engine: HapticEngine?
    private var lastDirectionAt: Date?
    
    public convenience init() {
        self.init(engine: HapticsChannel.makeEngine())
    }
    
    /// Tests pass a fake engine; nil means no haptics (the pattern calls do nothing).
    init(engine: HapticEngine?) {
        self.engine = engine
    }
    
    private static func makeEngine() -> HapticEngine? { //Pre iphone-8 hardware can't do custom haptics
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        let engine: CHHapticEngine
        do {
            engine = try CHHapticEngine()
        } catch {
            print("[HapticsChannel] engine unavailable: \(error.localizedDescription)")
            return nil
        }
        // The engine is started before every pattern (`haptic`), so it can shut itself
        // down when idle, and recovers after stop(), a reset or an interruption.
        // Both handlers run on a framework queue, hence @Sendable and log only.
        engine.isAutoShutdownEnabled = true
        engine.stoppedHandler = { @Sendable reason in
            print("[HapticsChannel] engine stopped: \(reason.rawValue)")
        }
        engine.resetHandler = { @Sendable in
            print("[HapticsChannel] engine reset; restarts on the next pattern")
        }
        return engine
    }
    
    public func play(_ event: FeedbackEvent) {
        switch event{
        case .direction, .doorDetected:
            let now = Date()
            if let last = lastDirectionAt, now.timeIntervalSince(last) < directionInterval { return }
            lastDirectionAt = now
            haptic(intensity: 0.7, sharpness: 0.9)
        case .bearingLock:
            haptic(intensity: 1.0, sharpness: 1.0, repeats: 2)
        case .distance:
            haptic(intensity: 0.4, sharpness: 0.3)
        case .arrival:
            haptic(intensity: 1.0, sharpness: 0.6, repeats: 3, spacing: 0.18)
        case .warning, .lost:
            haptic(intensity: 1.0, sharpness: 0.1, repeats: 3, spacing: 0.15)
        case .arrivalUncertain:
            // Close, but not "you're there": softer and slower than the arrival pattern.
            haptic(intensity: 0.6, sharpness: 0.3, repeats: 2, spacing: 0.3)
        default:
            break
        }
    }
    

    private func haptic(intensity: Float, sharpness:Float, repeats: Int = 1, spacing: TimeInterval = 0.12){
        guard let engine else { return }
        do {
            try engine.startEngine()
        } catch {
            print("[HapticsChannel] engine failed to start: \(error.localizedDescription)")
            return
        }
        let events = (0..<repeats).map { i in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                ],
                relativeTime: Double(i) * spacing
            )
        }
        try? engine.playTaps(events)
    }
    
    public func stop() {
        engine?.stopEngine()
    }
}

/// What HapticsChannel needs from Core Haptics, so a test can count engine starts and
/// patterns without hardware.
protocol HapticEngine: AnyObject {
    func startEngine() throws
    func stopEngine()
    func playTaps(_ events: [CHHapticEvent]) throws
}

extension CHHapticEngine: HapticEngine {
    func startEngine() throws {
        try start()
    }
    
    func stopEngine() {
        stop()
    }
    
    func playTaps(_ events: [CHHapticEvent]) throws {
        // pattern = rhythm of taps; player = the thing that runs it
        let pattern = try CHHapticPattern(events: events, parameters: [])
        try makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
    }
}
