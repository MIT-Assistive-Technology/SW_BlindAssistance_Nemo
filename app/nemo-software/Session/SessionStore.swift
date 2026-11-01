//  SessionStore.swift
//  nemo-software
//
//  Where the trip state lives between launches (FE-10). A blind rider mid-walk whose
//  phone restarts has to be able to carry on, and the app has to be honest about what
//  it no longer knows — see `NavigationSession.resume(from:bundle:)`.
//
//  One small JSON file, written on every state change. Nothing about the rider beyond
//  the destination they chose and the breadcrumbs of the current walk, and it's deleted
//  as soon as the trip ends.
//

import Foundation

nonisolated public final class SessionStore {
  public let fileURL: URL
  private let fileManager: FileManager

  public init(directory: URL? = nil, fileManager: FileManager = .default) {
    self.fileManager = fileManager
    let base =
      directory
      ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    fileURL = base.appendingPathComponent("nemo-session.json")
  }

  public func save(_ snapshot: SessionSnapshot) {
    do {
      try fileManager.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let data = try JSONEncoder.entrance.encode(snapshot)
      try data.write(to: fileURL, options: .atomic)
    } catch {
      // Losing the ability to resume is bad but not worth taking the trip down for.
      print("[SessionStore] could not save: \(error.localizedDescription)")
    }
  }

  public func load() -> SessionSnapshot? {
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    return try? JSONDecoder.entrance.decode(SessionSnapshot.self, from: data)
  }

  public func clear() {
    try? fileManager.removeItem(at: fileURL)
  }
}
