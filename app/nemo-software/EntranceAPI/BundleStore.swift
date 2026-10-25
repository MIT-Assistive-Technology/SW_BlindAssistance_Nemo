//  BundleStore.swift
//  nemo-software
//
//  FE-11: the phone's copy of the entrance bundles. One JSON file per destination in
//  Application Support, written when a bundle is resolved and read back on relaunch.
//
//  Why files and not SwiftData: a bundle is already JSON in the contract's shape, it is
//  read once per trip, and the walk has to work with no signal. A file that decodes with
//  `JSONDecoder.entrance` is the smallest thing that survives a relaunch.
//
//  Nothing about the rider goes in here: only the destination they chose.
//

import CryptoKit
import Foundation

/// A bundle as stored on the phone, with when it was fetched so the UI can say how
/// stale it is and the state machine can decide whether to refresh.
nonisolated public struct CachedBundle: Codable, Sendable {
  /// The address exactly as the rider entered it.
  public let address: String
  public let fetchedAt: Date
  public let result: ResolveResult

  public init(address: String, fetchedAt: Date, result: ResolveResult) {
    self.address = address
    self.fetchedAt = fetchedAt
    self.result = result
  }

  public var age: TimeInterval { Date().timeIntervalSince(fetchedAt) }
}

nonisolated public final class BundleStore {
  public enum StoreError: Error, Equatable {
    case notFound
  }

  /// Where the JSON files live.
  public let directory: URL

  private let fileManager: FileManager
  private let now: @Sendable () -> Date

  /// - Parameter directory: defaults to `Application Support/EntranceBundles`. Tests
  ///   pass a temporary directory.
  public init(
    directory: URL? = nil,
    fileManager: FileManager = .default,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.fileManager = fileManager
    self.now = now
    if let directory {
      self.directory = directory
    } else {
      let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      self.directory =
        (base ?? URL(fileURLWithPath: NSTemporaryDirectory()))
        .appendingPathComponent("EntranceBundles", isDirectory: true)
    }
  }

  // MARK: - Reading and writing

  @discardableResult
  public func save(_ result: ResolveResult, for address: String) throws -> CachedBundle {
    let cached = CachedBundle(address: address, fetchedAt: now(), result: result)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = try JSONEncoder.entrance.encode(cached)
    try data.write(to: fileURL(for: address), options: .atomic)
    return cached
  }

  public func cached(for address: String) -> CachedBundle? {
    guard let data = try? Data(contentsOf: fileURL(for: address)) else { return nil }
    return try? JSONDecoder.entrance.decode(CachedBundle.self, from: data)
  }

  public func result(for address: String) -> ResolveResult? {
    cached(for: address)?.result
  }

  /// Everything on the phone, newest first. Backs the "saved places" screen and lets a
  /// relaunch mid-trip pick up where it left off.
  public func allCached() -> [CachedBundle] {
    let files =
      (try? fileManager.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)) ?? []
    return files
      .filter { $0.pathExtension == "json" }
      .compactMap { try? Data(contentsOf: $0) }
      .compactMap { try? JSONDecoder.entrance.decode(CachedBundle.self, from: $0) }
      .sorted { $0.fetchedAt > $1.fetchedAt }
  }

  public func remove(for address: String) throws {
    let url = fileURL(for: address)
    guard fileManager.fileExists(atPath: url.path) else { throw StoreError.notFound }
    try fileManager.removeItem(at: url)
  }

  public func removeAll() throws {
    guard fileManager.fileExists(atPath: directory.path) else { return }
    try fileManager.removeItem(at: directory)
  }

  // MARK: - Keys

  public func fileURL(for address: String) -> URL {
    directory.appendingPathComponent("\(Self.cacheKey(for: address)).json")
  }

  /// "77 Massachusetts Ave., Cambridge MA" and "77 massachusetts ave cambridge ma" are
  /// the same destination, so punctuation, case and extra spaces are dropped before the
  /// key is hashed. Hashing keeps the filename safe for any address, in any script.
  public static func cacheKey(for address: String) -> String {
    let normalized = normalizedAddress(address)
    let digest = SHA256.hash(data: Data(normalized.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  public static func normalizedAddress(_ address: String) -> String {
    address
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}
