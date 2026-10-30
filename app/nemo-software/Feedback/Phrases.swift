//  Phrases.swift
//  nemo-software
//
//  Every string the app says out loud, in one place (FE-6). Guidance code emits
//  FeedbackEvents; SpeechChannel turns them into these phrases. Nothing else builds
//  spoken text, so the certainty-word test (SAFE-1) can check all of it by walking
//  `Phrases.all`.
//
//  Rules for anything added here:
//    - No certainty words about a door the camera hasn't confirmed: "should be",
//      "map shows", "looks like" — never "you've arrived" or "that's your building".
//    - Short. The rider is crossing a sidewalk with a cane, not reading a paragraph.
//    - Distances in the rider's units, rounded; never a confidence number.
//

import Foundation

/// The rider's distance units (the full profile is FE-7).
nonisolated public enum Units: String, Sendable, CaseIterable {
  case feet
  case meters
}

/// What the app knows about the destination when it briefs the rider, flattened out of
/// the bundle so `Phrases` doesn't depend on the server contract's shape.
nonisolated public struct DestinationBrief: Equatable, Sendable {
  /// "main", "door" or "facade" — the three spoken bands (ADR 0014).
  public let band: String
  /// Street the entrance faces, e.g. "Massachusetts Avenue".
  public let entranceStreet: String?
  /// Compass side of that street the door is on, e.g. "east".
  public let streetSideDescription: String?
  public let housenumber: String?
  /// `speak.door`, e.g. "hinged".
  public let door: String?
  /// `speak.automatic_door`, e.g. "button".
  public let automaticDoor: String?
  /// `speak.step_count`.
  public let stepCount: Int?
  public let metersToDoor: Double?

  public init(
    band: String,
    entranceStreet: String? = nil,
    streetSideDescription: String? = nil,
    housenumber: String? = nil,
    door: String? = nil,
    automaticDoor: String? = nil,
    stepCount: Int? = nil,
    metersToDoor: Double? = nil
  ) {
    self.band = band
    self.entranceStreet = entranceStreet
    self.streetSideDescription = streetSideDescription
    self.housenumber = housenumber
    self.door = door
    self.automaticDoor = automaticDoor
    self.stepCount = stepCount
    self.metersToDoor = metersToDoor
  }
}

/// Everything the side-of-street announcement needs. Grouped so the phrase can name the
/// street as well as the answer: a rider who can't see needs something to match against
/// what the driver told them.
nonisolated public struct SideOfStreetContext: Equatable, Sendable {
  public var metersToDoor: Double?
  public var metersToCrossing: Double?
  public var entranceStreet: String?
  public var streetSideDescription: String?

  public init(
    metersToDoor: Double? = nil,
    metersToCrossing: Double? = nil,
    entranceStreet: String? = nil,
    streetSideDescription: String? = nil
  ) {
    self.metersToDoor = metersToDoor
    self.metersToCrossing = metersToCrossing
    self.entranceStreet = entranceStreet
    self.streetSideDescription = streetSideDescription
  }
}

/// Why a destination lookup failed, reduced to the cases worth saying out loud. The
/// event carries this rather than a message, so no spoken text escapes `Phrases`.
nonisolated public enum LookupFailure: String, Equatable, Sendable, CaseIterable {
  case addressNotFound
  case noCachedCopy
  case other

  public init(_ error: Error) {
    switch error as? EntranceError {
    case .service(let code, _, _, _) where code == "GEOCODE_NOT_FOUND": self = .addressNotFound
    case .noCachedResult: self = .noCachedCopy
    default: self = .other
    }
  }
}

nonisolated public enum Phrases {

  // MARK: - Distances and directions

  /// Rounded distance, e.g. "about 110 feet". Round numbers only: the underlying GPS
  /// is 5–15 m off near buildings, so "34 metres" would be false precision.
  public static func distance(meters: Double, units: Units = .feet) -> String {
    switch units {
    case .feet:
      let feet = meters * 3.280_84
      let rounded = feet < 20 ? (feet / 5).rounded() * 5 : (feet / 10).rounded() * 10
      return "about \(Int(max(rounded, 5))) feet"
    case .meters:
      let rounded = meters < 10 ? meters.rounded() : (meters / 5).rounded() * 5
      return "about \(Int(max(rounded, 1))) metres"
    }
  }

  /// Spoken compass point for a bearing: words, not "NE", because VoiceOver voices
  /// read letter pairs badly.
  public static func compassPoint(_ degrees: Double) -> String {
    let points = [
      "north", "north east", "east", "south east", "south", "south west", "west",
      "north west",
    ]
    let index = Int((Geo.normalize(degrees) / 45).rounded()) % points.count
    return points[index]
  }

  /// Which way to turn for a signed offset, negative to the left.
  public static func turn(offsetDegrees: Double) -> String {
    let magnitude = abs(offsetDegrees)
    if magnitude < 10 { return "straight ahead" }
    let side = offsetDegrees < 0 ? "left" : "right"
    if magnitude < 35 { return "slightly \(side)" }
    if magnitude < 120 { return "to your \(side)" }
    return "behind you, to your \(side)"
  }

  // MARK: - Heading readout (FE-3)

  public static func heading(degrees: Double, accuracyDegrees: Double) -> String {
    let rounded = Int(Geo.normalize(degrees).rounded()) % 360
    let point = compassPoint(degrees)
    if accuracyDegrees > HeadingReadout.calibrationThresholdDegrees {
      return "Facing \(point), \(rounded) degrees. Compass accuracy is low."
    }
    return "Facing \(point), \(rounded) degrees."
  }

  public static let compassCalibration =
    "Compass accuracy is low. Hold the phone away from metal and move it in a figure eight."

  public static let headingUnavailable = "This device has no compass, so I can't give you a heading."

  // MARK: - Permissions

  public static let locationPermissionDenied =
    "Location is off for this app. Open Settings, then Location, and choose While Using the App."

  public static let locationUnavailable =
    "I can't get a location right now. I'll keep trying."

  // MARK: - Arrival and side of street (FE-13)

  /// Said at the drop-off, before the side of street is worked out. The rider may have
  /// been dropped in a travel lane, so the app never says "step onto the sidewalk".
  public static let exitCurbSide = "Exit on the curb side."

  /// A stop the phone noticed but can't vouch for: to GPS a red light looks exactly
  /// like a drop-off. The advice is conditional and the rider decides, because telling
  /// someone to get out while the car is still in traffic would be dangerous.
  ///
  /// The distance to the entrance is the one fact that actually helps answer the
  /// question — "40 feet" is the drop-off, "500 feet" is probably a light — and a rider
  /// who can't look out of the window has no other way to judge it.
  public static func possibleDropOff(metersToDoor: Double?, units: Units = .feet) -> String {
    let howFar = metersToDoor.map { ", \(distance(meters: $0, units: units)) from your entrance" }
    return
      "It looks like the car has stopped\(howFar ?? ""). If this is your drop-off, exit on the curb side, then tell me when you're out of the car."
  }

  public static func sameSideOfStreet(metersToDoor: Double?, units: Units = .feet) -> String {
    guard let metersToDoor else {
      return "Your entrance should be on this side of the street."
    }
    return
      "Your entrance should be on this side of the street, \(distance(meters: metersToDoor, units: units)) away."
  }

  /// "I'll stop guiding until you're across" can't be the last word: a rider who can't
  /// see has to be left with something to do. With a crossing in the bundle, say how
  /// far it is; without one, say plainly that there isn't one rather than going quiet.
  public static func acrossStreet(metersToCrossing: Double?, units: Units = .feet) -> String {
    guard let metersToCrossing else {
      return
        "Your entrance is across the street. I don't know of a marked crossing nearby, so follow the sidewalk to a crossing you trust. I'll stop guiding until you're across."
    }
    return
      "Your entrance is across the street. The nearest marked crossing is \(distance(meters: metersToCrossing, units: units)) away. I'll stop guiding until you're across."
  }

  /// Asked whenever the side of street can't be decided: one-way street, a turn before
  /// the stop, no tracked ride, and the rest of plan section 6's unknown cases.
  ///
  /// "The building side to your right" is phrased so it can be answered by cane and ear
  /// rather than by looking. Naming the street and compass side first gives the rider
  /// something to match against what the driver said.
  public static let askSideOfStreet =
    "I'm not sure which side of the street you're on. Are you on the sidewalk, with the building side to your right?"

  public static func askSideOfStreet(
    entranceStreet: String?, streetSideDescription: String?
  ) -> String {
    guard let entranceStreet else { return askSideOfStreet }
    let side = streetSideDescription.map { "the \($0) side of " } ?? ""
    return "Your entrance is on \(side)\(entranceStreet). \(askSideOfStreet)"
  }

  // MARK: - The walk (FE-10)

  /// Plan section 3, step 4. "Stand still" matters: the first fix and the compass need
  /// a moment, and a rider who starts walking immediately gets a worse anchor.
  public static let startingGuidance = "Starting. Stand still for a moment."

  public static let guidanceStopped = "Guidance stopped."

  /// The door is across the road, so guidance waits. The beacon must never point across
  /// a roadway (plan section 6).
  public static let waitingToCrossStreet =
    "I'll start guiding once you tell me you're across the street."

  /// Said when the rider is pointed the right way. There is no spatial beacon yet
  /// (FE-4), so the words have to carry it on their own — nothing here refers to a tone
  /// the app can't play.
  public static func bearingLock(metersToDoor: Double?, units: Units = .feet) -> String {
    guard let metersToDoor else { return "That's the direction. Walk straight ahead." }
    return
      "That's the direction. The door should be \(distance(meters: metersToDoor, units: units)) straight ahead."
  }

  /// The first-steps check failed: the walking direction doesn't match the expected
  /// one, so the app says so before it gives any more guidance (plan section 5).
  public static let directionUncertain = "I'm not sure of the direction. Stop for a moment."

  /// Off route. Again, no tone exists yet, so the instruction is spoken.
  public static let offRoute =
    "Off route. Stop, then turn slowly until I tell you that's the direction."

  /// Entering the last few meters. The door facts come from the bundle, which is the
  /// most useful thing the app knows at this point.
  public static func finalApproach(
    metersToDoor: Double?, brief: DestinationBrief, units: Units = .feet
  ) -> String {
    let howFar =
      metersToDoor.map { "The door should be \(distance(meters: $0, units: units)) ahead." }
      ?? "You're close to the door."
    guard let facts = doorFacts(brief) else { return howFar }
    return "\(howFar) \(facts)"
  }

  /// At the door. Never "you've arrived": only the rider's hand on the handle confirms
  /// a door (SAFE-1).
  public static let arrivedAtDoor =
    "The door should be right in front of you. Feel for the handle."

  // MARK: - The camera building check (CV-9)

  /// The camera read the building's number or name where the map said it would be.
  /// "That looks like your building", never "that's your building" (plan section 7).
  /// `text` is a string that came from the bundle's `recognize.text`, so nothing
  /// free-form is spoken.
  public static func buildingConfirmed(text: String, offsetDegrees: Double?) -> String {
    let direction = offsetDegrees.map { " \(turn(offsetDegrees: $0))" } ?? ""
    return "I can see \(text) ahead\(direction). That looks like your building."
  }

  /// The number was read, but not in the direction the building should be in — the
  /// same number on a different building, or a sign across the road. It is said out
  /// loud rather than ignored, because the rider may otherwise wonder why nothing
  /// happened.
  public static func buildingUncertain(text: String) -> String {
    "I see \(text), but it may not be your building."
  }

  public static func cameraCheckUnavailable(_ problem: CameraCheckProblem) -> String {
    switch problem {
    case .lowLight: return "Camera check unavailable in low light."
    case .unavailable: return "Camera check unavailable."
    }
  }

  // MARK: - Loading a destination (FE-11)

  /// Every action a rider takes has to make a sound, or there's no way to tell the app
  /// heard it. Looking up an address can take seconds.
  public static let lookingUpEntrance = "Looking up the entrance."

  /// A failed lookup must be spoken, not just left on screen.
  public static func lookupFailed(_ failure: LookupFailure) -> String {
    switch failure {
    case .addressNotFound:
      return "I couldn't find that address."
    case .noCachedCopy:
      return "I don't have the entrance details for that address on this phone yet."
    case .other:
      return "I couldn't get the entrance details for that address."
    }
  }

  public static func lookupFailed(_ error: Error) -> String {
    lookupFailed(LookupFailure(error))
  }

  public static let noDestinationLoaded =
    "I don't have a destination yet. Load the entrance details first."

  public static let bundleNotSavedForOffline =
    "I couldn't save this on your phone, so guidance may not work without a signal."

  // MARK: - Destination brief (FE-11 data, spoken at setup)

  public static func destinationBrief(_ brief: DestinationBrief, units: Units = .feet) -> String {
    var sentences: [String] = []

    let distanceClause = brief.metersToDoor.map { ", \(distance(meters: $0, units: units)) ahead" } ?? ""
    let forClause = brief.housenumber.map { " for number \($0)" } ?? ""
    switch brief.band {
    case "main":
      sentences.append("Map shows the main entrance\(forClause)\(distanceClause).")
    case "door":
      sentences.append(
        "Map shows a door\(forClause)\(distanceClause). It may not be the main entrance.")
    default:
      sentences.append("No door on the map. I'll guide you to the street-facing side.")
    }

    if let street = brief.entranceStreet {
      let side = brief.streetSideDescription.map { " on the \($0) side" } ?? ""
      sentences.append("It faces \(street)\(side).")
    }
    if let facts = doorFacts(brief) {
      sentences.append(facts)
    }
    return sentences.joined(separator: " ")
  }

  /// "It has 3 steps and a push-button door." Every part is optional: OSM rarely has them.
  static func doorFacts(_ brief: DestinationBrief) -> String? {
    var parts: [String] = []
    if let steps = brief.stepCount, steps > 0 {
      parts.append(steps == 1 ? "1 step" : "\(steps) steps")
    }
    switch brief.automaticDoor {
    case "button": parts.append("a push-button door")
    case "motion", "sensor": parts.append("an automatic door")
    case .some: parts.append("an automatic door")
    case nil:
      if brief.door == "hinged" { parts.append("a hinged door") }
      if brief.door == "revolving" { parts.append("a revolving door") }
      if brief.door == "sliding" { parts.append("a sliding door") }
    }
    guard !parts.isEmpty else { return nil }
    if parts.count == 1 { return "It has \(parts[0])." }
    return "It has \(parts.dropLast().joined(separator: ", ")) and \(parts.last!)."
  }

  public static let rideTrackingStarted =
    "Tracking the ride. I'll tell you which way to get out when the car stops."

  public static let rideTrackingStopped = "Ride tracking off."

  // MARK: - SAFE-1

  /// One rendering of every phrase above, for the certainty-word test. Add new phrases
  /// here too, or SAFE-1 can't see them.
  public static var all: [String] {
    [
      distance(meters: 33.5, units: .feet),
      distance(meters: 33.5, units: .meters),
      compassPoint(45),
      turn(offsetDegrees: 5),
      turn(offsetDegrees: -20),
      turn(offsetDegrees: 60),
      turn(offsetDegrees: 150),
      heading(degrees: 45, accuracyDegrees: 10),
      heading(degrees: 45, accuracyDegrees: 35),
      compassCalibration,
      headingUnavailable,
      locationPermissionDenied,
      locationUnavailable,
      exitCurbSide,
      possibleDropOff(metersToDoor: nil),
      possibleDropOff(metersToDoor: 12),
      sameSideOfStreet(metersToDoor: 33.5),
      sameSideOfStreet(metersToDoor: nil),
      acrossStreet(metersToCrossing: 30),
      acrossStreet(metersToCrossing: nil),
      askSideOfStreet,
      askSideOfStreet(entranceStreet: "Example Avenue", streetSideDescription: "west"),
      lookingUpEntrance,
      noDestinationLoaded,
      bundleNotSavedForOffline,
      destinationBrief(
        DestinationBrief(
          band: "main", entranceStreet: "Massachusetts Avenue", streetSideDescription: "east",
          housenumber: "77", door: "hinged", automaticDoor: "button", stepCount: 3,
          metersToDoor: 33.5)),
      destinationBrief(DestinationBrief(band: "door", metersToDoor: 33.5)),
      destinationBrief(DestinationBrief(band: "facade")),
      rideTrackingStarted,
      rideTrackingStopped,
      startingGuidance,
      guidanceStopped,
      waitingToCrossStreet,
      bearingLock(metersToDoor: 33.5),
      bearingLock(metersToDoor: nil),
      directionUncertain,
      offRoute,
      finalApproach(
        metersToDoor: 9,
        brief: DestinationBrief(band: "main", automaticDoor: "button", stepCount: 3)),
      finalApproach(metersToDoor: nil, brief: DestinationBrief(band: "facade")),
      arrivedAtDoor,
      buildingConfirmed(text: "77", offsetDegrees: 20),
      buildingConfirmed(text: "77", offsetDegrees: nil),
      buildingUncertain(text: "77"),
    ] + LookupFailure.allCases.map(lookupFailed)
      + CameraCheckProblem.allCases.map(cameraCheckUnavailable)
  }

  /// Words that promise more than the app can know (SAFE-1). A door is only confirmed
  /// by the rider's own hand on the handle.
  public static let bannedCertaintyPhrases = [
    "you've arrived",
    "you have arrived",
    "that's your building",
    "this is your building",
    "that's your door",
    "this is your door",
    "you are at the door",
    "you're at the door",
    "definitely",
    "guaranteed",
    "exactly",
  ]
}
