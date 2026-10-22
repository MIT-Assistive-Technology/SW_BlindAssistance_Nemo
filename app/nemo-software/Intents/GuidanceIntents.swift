//  GuidanceIntents.swift
//  nemo-software
//
//  Siri, Shortcuts and Back Tap entry points (plan section 11):
//    - "Find my entrance": pick a saved place, or Siri asks "What address?" (phrases can't
//      hold a free-form address). Opens the app. During a trip it means "Where am I / Repeat"
//      and never stops guidance, so it is safe to map to Back Tap.
//    - "Where am I": repeats the guidance for the current position.
//    - "Stop guiding": ends the trip.
//
//  The intents only forward to `AppModel.shared` on the main actor.
//

import AppIntents
import Foundation

nonisolated struct StartGuidanceIntent: AppIntent {
  static let title: LocalizedStringResource = "Find my entrance"
  static let description = IntentDescription(
    "Loads the entrance for a saved place or an address, then starts guidance.")
  static let openAppWhenRun: Bool = true

  @Parameter(title: "Saved place")
  var place: SavedPlace?

  @Parameter(title: "Address")
  var address: String?

  init() {}

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let model = AppModel.shared
    // Back Tap during a trip: repeat / where am I.
    if place == nil, address == nil, model.hasTrip {
      model.primaryAction()
      return .result(dialog: "")
    }
    guard let destination = place?.address ?? address?.trimmingCharacters(in: .whitespaces),
      !destination.isEmpty
    else {
      throw $address.needsValueError("What address?")
    }
    let found = await model.startTrip(address: destination, name: place?.name)
    return .result(
      dialog: found
        ? "Entrance loaded. Tap I'm in the car when your ride starts."
        : "I couldn't find map data for that address.")
  }
}

nonisolated struct WhereAmIIntent: AppIntent {
  static let title: LocalizedStringResource = "Where am I"
  static let description = IntentDescription("Repeats the guidance for where you are now.")
  static let openAppWhenRun: Bool = false

  init() {}

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let model = AppModel.shared
    guard model.hasTrip else { return .result(dialog: "No trip is active.") }
    model.whereAmI()
    return .result(dialog: "")
  }
}

nonisolated struct StopGuidanceIntent: AppIntent {
  static let title: LocalizedStringResource = "Stop guiding"
  static let description = IntentDescription("Ends the current trip.")
  static let openAppWhenRun: Bool = false

  init() {}

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let model = AppModel.shared
    guard model.hasTrip else { return .result(dialog: "No trip is active.") }
    model.stopTrip()
    return .result(dialog: "Guidance stopped.")
  }
}

nonisolated struct NemoShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: StartGuidanceIntent(),
      phrases: [
        "Find my entrance with \(.applicationName)",
        "Find my entrance in \(.applicationName)",
        "Guide me to \(\.$place) with \(.applicationName)",
      ],
      shortTitle: "Find my entrance",
      systemImageName: "figure.walk"
    )
    AppShortcut(
      intent: WhereAmIIntent(),
      phrases: [
        "Where am I in \(.applicationName)",
        "Repeat \(.applicationName) guidance",
      ],
      shortTitle: "Where am I",
      systemImageName: "location"
    )
    AppShortcut(
      intent: StopGuidanceIntent(),
      phrases: [
        "Stop guiding with \(.applicationName)",
        "Stop \(.applicationName) guidance",
      ],
      shortTitle: "Stop guiding",
      systemImageName: "stop.circle"
    )
  }
}
