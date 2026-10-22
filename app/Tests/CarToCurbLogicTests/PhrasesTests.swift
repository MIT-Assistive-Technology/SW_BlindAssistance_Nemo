import XCTest

@testable import CarToCurbLogic

final class PhrasesTests: XCTestCase {
  /// SAFE-1: words that claim certainty the system doesn't have.
  static let banned = [
    "you've arrived", "you have arrived", "that's your building", "that is your building",
    "the entrance is", "you are at", "safe to cross", "it's safe", "definitely", "exactly",
  ]

  /// Exhaustive on purpose: adding a FeedbackEvent case breaks the build here until the
  /// sample list below covers it.
  static func caseName(_ e: FeedbackEvent) -> String {
    switch e {
    case .direction: return "direction"
    case .distance: return "distance"
    case .bearingLock: return "bearingLock"
    case .landmark: return "landmark"
    case .buildingConfirmed: return "buildingConfirmed"
    case .doorDetected: return "doorDetected"
    case .warning(let w):
      switch w {
      case .crossStreet: return "warning.crossStreet"
      case .driveway: return "warning.driveway"
      case .notSure: return "warning.notSure"
      case .trackingLost: return "warning.trackingLost"
      case .lowBattery: return "warning.lowBattery"
      case .lowLight: return "warning.lowLight"
      }
    case .exitCurbSide: return "exitCurbSide"
    case .brief: return "brief"
    case .offRoute: return "offRoute"
    case .lost: return "lost"
    case .arrival: return "arrival"
    }
  }

  static let allCaseNames: Set<String> = [
    "direction", "distance", "bearingLock", "landmark", "buildingConfirmed", "doorDetected",
    "warning.crossStreet", "warning.driveway", "warning.notSure", "warning.trackingLost",
    "warning.lowBattery", "warning.lowLight", "exitCurbSide", "brief", "offRoute", "lost",
    "arrival",
  ]

  static var samples: [FeedbackEvent] {
    let offsets: [Double] = [-179, -90, -30, -5, 0, 5, 30, 90, 179]
    let meters: [Double] = [0, 0.5, 3, 9.1, 18.3, 33.5, 120]
    var events: [FeedbackEvent] = [.bearingLock, .exitCurbSide, .offRoute, .lost, .arrival]
    events += offsets.map { .direction(offsetDegrees: $0) }
    events += meters.map { .distance(meters: $0) }
    for kind in ["bench", "handrail", "bus_stop", "waste_basket", ""] {
      for side in [Side.left, .right, .unknown] {
        events.append(.landmark(kind: kind, side: side))
      }
    }
    events += ["77", "Example Building"].map { .buildingConfirmed(text: $0) }
    for o in offsets {
      for m in meters { events.append(.doorDetected(offsetDegrees: o, meters: m)) }
    }
    events += [
      .warning(.crossStreet(crossingMeters: nil)), .warning(.crossStreet(crossingMeters: 30)),
      .warning(.driveway), .warning(.notSure), .warning(.trackingLost), .warning(.lowBattery),
      .warning(.lowLight),
    ]
    for same in [true, false, nil] as [Bool?] {
      for o in offsets {
        for m in meters { events.append(.brief(sameSide: same, meters: m, offsetDegrees: o)) }
      }
    }
    return events
  }

  func testSamplesCoverEveryCase() {
    XCTAssertEqual(Set(Self.samples.map(Self.caseName)), Self.allCaseNames)
  }

  func testNoCertaintyWords() {
    var checked = 0
    for event in Self.samples {
      for verbosity in Verbosity.allCases {
        for units in Units.allCases {
          guard let text = Phrases.text(for: event, verbosity: verbosity, units: units) else {
            continue
          }
          checked += 1
          XCTAssertFalse(text.isEmpty, "\(event)")
          let lowered = text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
          for word in Self.banned {
            XCTAssertFalse(lowered.contains(word), "\"\(text)\" contains \"\(word)\"")
          }
        }
      }
    }
    XCTAssertGreaterThan(checked, 500)
  }

  func testEverySpokenCaseHasNormalText() {
    // Only the bearing lock may be silent (haptics carry it), and only at minimal.
    for event in Self.samples {
      XCTAssertNotNil(Phrases.text(for: event, verbosity: .normal, units: .feet), "\(event)")
    }
    XCTAssertNil(Phrases.text(for: .bearingLock, verbosity: .minimal, units: .feet))
  }

  func testPlanWording() {
    func say(_ e: FeedbackEvent, _ v: Verbosity = .normal, _ u: Units = .feet) -> String? {
      Phrases.text(for: e, verbosity: v, units: u)
    }
    XCTAssertEqual(say(.exitCurbSide), "Exit on the curb side.")
    XCTAssertEqual(
      say(.brief(sameSide: true, meters: 33.5, offsetDegrees: 30)),
      "Your entrance should be on this side of the street, about 110 feet ahead and to your right.")
    XCTAssertEqual(
      say(.buildingConfirmed(text: "77")), "I can see '77' ahead. That looks like your building.")
    XCTAssertEqual(say(.buildingConfirmed(text: "77"), .minimal), "That looks like your building.")
    XCTAssertEqual(
      say(.arrival), "The door should be right in front of you. Feel for the handle.")
    XCTAssertEqual(say(.warning(.notSure)), "I'm not sure of the direction. Stop for a moment.")
    XCTAssertEqual(say(.offRoute), "Off route. Turn until the tone centers.")
    XCTAssertEqual(say(.warning(.driveway)), "Driveway ahead. Listen for cars.")
    XCTAssertEqual(say(.landmark(kind: "bench", side: .left)), "Bench on your left.")
    XCTAssertEqual(
      say(.doorDetected(offsetDegrees: 10, meters: 3)), "Door, slightly right, about 10 feet.")
    XCTAssertEqual(say(.distance(meters: 18.3)), "About 60 feet.")
    XCTAssertEqual(say(.distance(meters: 18.3), .normal, .meters), "About 18 meters.")
    XCTAssertTrue(
      say(.brief(sameSide: nil, meters: 30, offsetDegrees: 0))!
        .hasPrefix("I'm not sure which side of the street you're on."))
    XCTAssertEqual(
      say(.warning(.crossStreet(crossingMeters: 30.5))),
      "The nearest marked crossing is about 100 feet away. I'll stop guiding until you're across.")
  }
}
