//  BundleStore.swift
//  nemo-software
//
//  Entrance bundles saved on the phone, so guidance works with no signal at the curb.
//  Files live in Application Support/Bundles (excluded from iCloud backup): one
//  `<id>.json` per bundle, exactly the bytes the server sent, plus `index.json`.
//  Lookups are offline-first: by bundle id or by destination address.
//

import Foundation

final class BundleStore {
  struct Entry: Codable, Identifiable, Equatable {
    let id: String
    var address: String?
    /// Server sha256 of the bytes (nil for a bundle saved from /v1/resolve or the stub).
    var sha256: String?
    var etag: String?
    var savedAt: Date
  }

  private(set) var entries: [Entry]
  private let directory: URL

  init(directory: URL? = nil) {
    let fileManager = FileManager.default
    var dir =
      directory
      ?? (try? fileManager.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      )?.appendingPathComponent("Bundles", isDirectory: true)
      ?? fileManager.temporaryDirectory.appendingPathComponent("Bundles", isDirectory: true)
    try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? dir.setResourceValues(values)
    self.directory = dir
    let index = dir.appendingPathComponent("index.json")
    self.entries = (try? Data(contentsOf: index)).flatMap {
      try? JSONDecoder().decode([Entry].self, from: $0)
    } ?? []
  }

  // MARK: - Lookup

  func entry(id: String) -> Entry? {
    entries.first { $0.id == id }
  }

  func bundle(id: String) -> ResolveResult? {
    guard let data = try? Data(contentsOf: fileURL(id: id)) else { return nil }
    return try? JSONDecoder.entrance.decode(ResolveResult.self, from: data)
  }

  /// Offline match on the typed or saved address. The house number must match exactly;
  /// the rest may be a prefix ("77 Massachusetts Ave" matches "77 Massachusetts Ave, Cambridge, MA").
  func bundle(matchingAddress address: String) -> ResolveResult? {
    let query = Self.normalize(address)
    guard !query.isEmpty else { return nil }
    let match = entries.first { entry in
      guard let stored = entry.address.map({ Self.normalize($0) }), !stored.isEmpty else { return false }
      guard stored.split(separator: " ").first == query.split(separator: " ").first else {
        return false
      }
      return stored == query || stored.hasPrefix(query + " ") || query.hasPrefix(stored + " ")
    }
    return match.flatMap { bundle(id: $0.id) }
  }

  // MARK: - Saving

  /// Saves the server's bytes after checking they decode as a bundle.
  @discardableResult
  func save(
    _ data: Data, id: String, address: String?, sha256: String? = nil, etag: String? = nil
  ) throws -> ResolveResult {
    let result = try JSONDecoder.entrance.decode(ResolveResult.self, from: data)
    try data.write(to: fileURL(id: id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    let entry = Entry(
      id: id, address: address ?? self.entry(id: id)?.address, sha256: sha256, etag: etag,
      savedAt: Date())
    entries.removeAll { $0.id == id }
    entries.append(entry)
    try writeIndex()
    return result
  }

  /// Deletes every saved bundle.
  func removeAll() throws {
    for entry in entries { try? FileManager.default.removeItem(at: fileURL(id: entry.id)) }
    entries = []
    try writeIndex()
  }

  // MARK: - Private

  private func fileURL(id: String) -> URL {
    // Bundle ids are slugs; strip anything that could leave the directory.
    let safe = id.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    return directory.appendingPathComponent(safe.isEmpty ? "bundle" : safe).appendingPathExtension("json")
  }

  private func writeIndex() throws {
    let data = try JSONEncoder().encode(entries)
    try data.write(to: directory.appendingPathComponent("index.json"), options: .atomic)
  }

  /// Lowercased words, punctuation dropped, common street words shortened.
  static func normalize(_ address: String) -> String {
    let short = [
      "avenue": "ave", "street": "st", "road": "rd", "boulevard": "blvd", "drive": "dr",
      "place": "pl", "court": "ct", "lane": "ln", "square": "sq", "parkway": "pkwy",
    ]
    let words = address.lowercased()
      .map { $0.isLetter || $0.isNumber ? $0 : " " }
      .split(separator: " ")
      .map { short[String($0)] ?? String($0) }
    return words.joined(separator: " ")
  }
}
