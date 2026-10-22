//  Phrases.swift
//  nemo-software
//
//  The ONLY place spoken English lives (SAFE-1). Wording follows docs/car-to-curb-plan.md
//  sections 3 and 16. Never use certainty words ("you've arrived", "that's your building",
//  "the entrance is", "you are at", "safe to cross"); PhrasesTests lints every case.
//

import Foundation

public enum Phrases {
  /// The phrase to speak for `event`, or nil when the event is non-verbal at this verbosity
  /// (the beacon or haptics carry it).
  public static func text(for event: FeedbackEvent, verbosity: Verbosity, units: Units) -> String? {
    let normal = verbosity == .normal
    switch event {
    case .direction(let offset):
      return normal ? sentence(direction(offset)) : sentence(shortDirection(offset))

    case .distance(let meters):
      return normal ? "About \(distance(meters, units))." : "\(distance(meters, units))."

    case .bearingLock:
      return normal ? "On course." : nil

    case .landmark(let kind, let side):
      let name = landmarkName(kind)
      switch side {
      case .left: return "\(name) on your left."
      case .right: return "\(name) on your right."
      case .unknown: return "\(name) ahead."
      }

    case .buildingConfirmed(let text):
      return normal
        ? "I can see '\(text)' ahead. That looks like your building."
        : "That looks like your building."

    case .doorDetected(let offset, let meters):
      let where_ = direction(offset).lowercased()
      return normal
        ? "Door, \(where_), about \(distance(meters, units))."
        : "Door, \(where_)."

    case .warning(let warning):
      return text(for: warning, normal: normal, units: units)

    case .exitCurbSide:
      return "Exit on the curb side."

    case .brief(let sameSide, let meters, let offset):
      let away = "about \(distance(meters, units)) \(briefDirection(offset))"
      switch sameSide {
      case true?:
        return normal
          ? "Your entrance should be on this side of the street, \(away)."
          : "This side of the street, \(away)."
      case false?:
        return normal
          ? "Your entrance should be across the street."
          : "Entrance across the street."
      case nil:
        return normal
          ? "I'm not sure which side of the street you're on. Check that you're on the sidewalk on the building side. Your entrance should be \(away)."
          : "Not sure which side of the street. Entrance \(away)."
      }

    case .offRoute:
      return normal ? "Off route. Turn until the tone centers." : "Off route."

    case .lost:
      return normal ? "I'm not sure where you are. Stop for a moment." : "Not sure where you are."

    case .arrival:
      return normal
        ? "The door should be right in front of you. Feel for the handle."
        : "Door should be in front of you."
    }
  }

  private static func text(for warning: FeedbackEvent.Warning, normal: Bool, units: Units) -> String {
    switch warning {
    case .crossStreet(let crossingMeters):
      let crossing = crossingMeters.map {
        "The nearest marked crossing is about \(distance($0, units)) away. "
      } ?? ""
      return normal
        ? "\(crossing)I'll stop guiding until you're across."
        : "\(crossing)Guidance stops until you're across."
    case .driveway:
      return "Driveway ahead. Listen for cars."
    case .notSure:
      return normal ? "I'm not sure of the direction. Stop for a moment." : "Not sure of the direction. Stop."
    case .trackingLost:
      return normal ? "Guidance paused. Take the phone out for a moment." : "Guidance paused."
    case .lowBattery:
      return normal ? "Battery is low. Guidance may pause." : "Battery low."
    case .lowLight:
      return "Camera check unavailable in low light."
    }
  }

  // MARK: - Pieces

  /// "110 feet" / "35 meters". Feet round to 5 below 50 and to 10 above; meters to 1 below
  /// 20 and to 5 above, so numbers don't sound more exact than GPS is.
  static func distance(_ meters: Double, _ units: Units) -> String {
    let m = max(0, meters)
    switch units {
    case .feet:
      let feet = m * 3.28084
      let step = feet < 50 ? 5.0 : 10.0
      let n = max(5, Int((feet / step).rounded() * step))
      return "\(n) feet"
    case .meters:
      let step = m < 20 ? 1.0 : 5.0
      let n = max(1, Int((m / step).rounded() * step))
      return n == 1 ? "1 meter" : "\(n) meters"
    }
  }

  static func direction(_ offset: Double) -> String {
    let a = abs(offset), side = offset < 0 ? "left" : "right"
    if a < 10 { return "Straight ahead" }
    if a < 45 { return "Slightly \(side)" }
    if a < 135 { return "Turn \(side)" }
    return "Turn around"
  }

  static func shortDirection(_ offset: Double) -> String {
    let a = abs(offset)
    if a < 10 { return "Ahead" }
    if a < 135 { return offset < 0 ? "Left" : "Right" }
    return "Behind"
  }

  static func briefDirection(_ offset: Double) -> String {
    let a = abs(offset), side = offset < 0 ? "left" : "right"
    if a < 15 { return "ahead" }
    if a < 60 { return "ahead and to your \(side)" }
    if a < 135 { return "to your \(side)" }
    return "behind you"
  }

  static func landmarkName(_ kind: String) -> String {
    let words = kind.replacingOccurrences(of: "_", with: " ").lowercased()
    switch words {
    case "handrail": return "Railing"
    case "waste basket": return "Trash can"
    case "": return "Landmark"
    default: return words.prefix(1).uppercased() + words.dropFirst()
    }
  }

  private static func sentence(_ s: String) -> String { s + "." }
}
