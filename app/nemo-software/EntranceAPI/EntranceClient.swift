//  EntranceClient.swift
//  nemo-software
//
//  Talks to the entrance service. Send ONLY the destination address,
//  never the rider's location. The result is cached on the phone so guidance works
//  with no signal after drop-off.
//

import Foundation

/// `nonisolated` throughout: fetching and caching a bundle is network and disk work,
/// not UI work, so none of it belongs on the main actor (plan section 11).
nonisolated public protocol EntranceClient: AnyObject {
  /// Resolve a destination address into ranked door candidates.
  func resolve(address: String) async throws -> ResolveResult
}

/// What can go wrong talking to the service. The server's error envelope
/// (plan section 10) is kept intact so the UI can say something specific.
nonisolated public enum EntranceError: Error, Equatable {
  /// `{ "error": { "code", "message", "request_id" } }` from the service.
  case service(code: String, message: String, requestId: String?, httpStatus: Int)
  /// A non-JSON or unexpected response.
  case badResponse(httpStatus: Int)
  /// Nothing on the network and nothing in the cache for this address.
  case noCachedResult
}

/// Returns bundled sample data. Use it to build app features before the server is
/// running, and in previews and tests.
/// `site` is a pilot site id from `server/pilot_sites.json` (e.g. "mit-stata"): its real
/// bundle in `Resources/PilotBundles/`. Without one, `resolve.example.json`.
nonisolated public final class StubEntranceClient: EntranceClient {
  private let site: String?
  private let bundle: Bundle

  public init(site: String? = nil, bundle: Bundle = .main) {
    self.site = site
    self.bundle = bundle
  }

  public func resolve(address: String) async throws -> ResolveResult {
    guard let url = bundle.url(forResource: site ?? "resolve.example", withExtension: "json") else {
      throw URLError(.fileDoesNotExist)
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder.entrance.decode(ResolveResult.self, from: data)
  }
}

/// The app's client until the server is up: an address typed by the rider is matched
/// against `pilot_sites.json` (a copy of `server/pilot_sites.json`) and answered with that
/// site's real bundle. An address that isn't a pilot site fails as "not found" rather
/// than falling back to the fictional example, which would guide the rider to a door
/// that doesn't exist.
nonisolated public final class PilotSiteEntranceClient: EntranceClient {
  private let bundle: Bundle

  public init(bundle: Bundle = .main) {
    self.bundle = bundle
  }

  public func resolve(address: String) async throws -> ResolveResult {
    guard let site = try siteId(for: address) else {
      throw EntranceError.service(
        code: "GEOCODE_NOT_FOUND", message: "Not a pilot site", requestId: nil, httpStatus: 404)
    }
    return try await StubEntranceClient(site: site, bundle: bundle).resolve(address: address)
  }

  /// The pilot site id for an address, or nil. Both the street line and the town have
  /// to match: "77 Massachusetts Ave" exists in Boston and in Cambridge, and they are
  /// different buildings.
  public func siteId(for address: String) throws -> String? {
    struct Sites: Decodable {
      struct Site: Decodable {
        let id: String
        let address: String
      }
      let sites: [Site]
    }
    guard let url = bundle.url(forResource: "pilot_sites", withExtension: "json") else {
      throw URLError(.fileDoesNotExist)
    }
    let sites = try JSONDecoder().decode(Sites.self, from: Data(contentsOf: url)).sites
    guard let wanted = Self.key(address) else { return nil }
    return sites.first { Self.key($0.address) == wanted }?.id
  }

  /// "77 Massachusetts Avenue, Cambridge, MA" -> "77 massachusetts ave|cambridge".
  static func key(_ address: String) -> String? {
    let parts = address.lowercased().split(separator: ",")
    guard parts.count >= 2 else { return nil }
    let abbreviations = [
      "avenue": "ave", "street": "st", "place": "pl", "drive": "dr", "road": "rd",
    ]
    let words: (Substring) -> [String] = { part in
      part.split { !$0.isLetter && !$0.isNumber }.map { abbreviations[String($0)] ?? String($0) }
    }
    let street = words(parts[0])
    // "Cambridge MA 02138" and "Cambridge" both name the town by their first word.
    guard !street.isEmpty, let town = words(parts[1]).first else { return nil }
    return street.joined(separator: " ") + "|" + town
  }
}

/// Real client (FE-11).
///
/// There is no `202` and no polling: plan section 10 settled on `200` with
/// `status: "partial"` for a weak result, so the rider always gets something back.
/// Caching is `CachingEntranceClient`'s job, not this type's.
nonisolated public final class LiveEntranceClient: EntranceClient {
  private let baseURL: URL
  private let session: URLSession
  private let installKey: String

  public init(
    baseURL: URL,
    session: URLSession = .shared,
    installKey: String = InstallKey.shared.value
  ) {
    self.baseURL = baseURL
    self.session = session
    self.installKey = installKey
  }

  public func resolve(address: String) async throws -> ResolveResult {
    var request = URLRequest(url: baseURL.appendingPathComponent("v1/resolve"))
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    // A random per-install UUID, so rate limiting works without accounts. It is never
    // stored with a destination.
    request.setValue(installKey, forHTTPHeaderField: "X-Install-Key")
    request.httpBody = try JSONEncoder().encode(["address": address])

    let (data, response) = try await session.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else {
      throw Self.error(from: data, status: status)
    }
    do {
      return try JSONDecoder.entrance.decode(ResolveResult.self, from: data)
    } catch {
      throw EntranceError.badResponse(httpStatus: status)
    }
  }

  private static func error(from data: Data, status: Int) -> EntranceError {
    struct Envelope: Decodable {
      struct Payload: Decodable {
        let code: String
        let message: String
        let requestId: String?
      }
      let error: Payload
    }
    guard let envelope = try? JSONDecoder.entrance.decode(Envelope.self, from: data) else {
      return .badResponse(httpStatus: status)
    }
    return .service(
      code: envelope.error.code,
      message: envelope.error.message,
      requestId: envelope.error.requestId,
      httpStatus: status)
  }
}

/// A bundle plus where it came from. The rider is told when they're walking from a
/// saved copy, so "the app knew the door" is never confused with "the app checked".
nonisolated public struct ResolvedBundle: Sendable {
  public let result: ResolveResult
  public let fromCache: Bool
  /// When the copy on the phone was fetched; nil for a fresh result.
  public let fetchedAt: Date?
  /// False when the bundle couldn't be written to the phone. The rider is told, because
  /// it means the walk may need a signal — a failure they'd otherwise discover at the
  /// curb with no way to see why.
  public let savedForOffline: Bool
}

/// Wraps another client with the phone's cache (FE-11): a fresh result is saved, and a
/// network failure falls back to the stored bundle so the walk still works with no
/// signal. This is what the app should be built on, not a bare client.
nonisolated public final class CachingEntranceClient: EntranceClient {
  private let upstream: EntranceClient
  private let store: BundleStore

  public init(upstream: EntranceClient, store: BundleStore) {
    self.upstream = upstream
    self.store = store
  }

  public func resolve(address: String) async throws -> ResolveResult {
    try await resolveBundle(address: address).result
  }

  public func resolveBundle(address: String) async throws -> ResolvedBundle {
    do {
      let result = try await upstream.resolve(address: address)
      let saved = (try? store.save(result, for: address)) != nil
      return ResolvedBundle(
        result: result, fromCache: false, fetchedAt: nil, savedForOffline: saved)
    } catch {
      // No signal at the curb is the normal case, not an edge case.
      if let cached = store.cached(for: address) {
        return ResolvedBundle(
          result: cached.result, fromCache: true, fetchedAt: cached.fetchedAt,
          savedForOffline: true)
      }
      throw error
    }
  }

  /// Read the cache without touching the network: what the walk uses after drop-off.
  public func cached(for address: String) -> CachedBundle? {
    store.cached(for: address)
  }

  /// Offline load. Throws `EntranceError.noCachedResult` when this phone has never
  /// resolved that address.
  public func cachedResult(for address: String) throws -> ResolveResult {
    guard let cached = store.cached(for: address) else { throw EntranceError.noCachedResult }
    return cached.result
  }
}

/// A random UUID made on first launch, used as `X-Install-Key`. No accounts, nothing
/// that identifies the rider or their phone.
nonisolated public final class InstallKey {
  public static let shared = InstallKey()

  private static let defaultsKey = "nemo.installKey"
  public let value: String

  public init(defaults: UserDefaults = .standard) {
    if let existing = defaults.string(forKey: Self.defaultsKey) {
      value = existing
    } else {
      value = UUID().uuidString
      defaults.set(value, forKey: Self.defaultsKey)
    }
  }
}
