//  SavedPlace.swift
//  nemo-software
//
//  A destination the rider chose to save. It is an App Intents entity so Siri and
//  Shortcuts can offer it ("Find my entrance" -> pick a saved place).
//  Saved places are opt-in, stored on the phone only (Application Support, excluded from
//  iCloud backup), and can all be deleted.
//
//  `nonisolated` keeps these types off the target's default main actor: App Intents
//  calls them from its own threads.
//

import AppIntents
import Foundation

nonisolated struct SavedPlace: AppEntity, Codable, Hashable, Identifiable {
  var id: String
  var name: String
  var address: String

  init(id: String = UUID().uuidString, name: String, address: String) {
    self.id = id
    self.name = name
    self.address = address
  }

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Saved place"
  static let defaultQuery = SavedPlaceQuery()

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)", subtitle: "\(address)")
  }
}

nonisolated struct SavedPlaceQuery: EntityStringQuery {
  init() {}

  func entities(for identifiers: [String]) async throws -> [SavedPlace] {
    SavedPlacesFile.load().filter { identifiers.contains($0.id) }
  }

  func entities(matching string: String) async throws -> [SavedPlace] {
    let query = string.lowercased()
    return SavedPlacesFile.load().filter {
      $0.name.lowercased().contains(query) || $0.address.lowercased().contains(query)
    }
  }

  func suggestedEntities() async throws -> [SavedPlace] {
    SavedPlacesFile.load()
  }
}

/// The saved-places file. Small JSON, read and written whole.
nonisolated enum SavedPlacesFile {
  static var url: URL? {
    guard
      let base = try? FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    else { return nil }
    return base.appendingPathComponent("saved-places.json")
  }

  static func load() -> [SavedPlace] {
    guard let url, let data = try? Data(contentsOf: url) else { return [] }
    return (try? JSONDecoder().decode([SavedPlace].self, from: data)) ?? []
  }

  static func save(_ places: [SavedPlace]) {
    guard var url, let data = try? JSONEncoder().encode(places) else { return }
    try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? url.setResourceValues(values)
  }
}
