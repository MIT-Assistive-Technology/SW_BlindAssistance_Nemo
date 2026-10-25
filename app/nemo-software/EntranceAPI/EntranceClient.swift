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

/// Returns the bundled `resolve.example.json`. Use it to build app features before
/// the server is running, and in previews and tests.
nonisolated public final class StubEntranceClient: EntranceClient {
  private let bundle: Bundle

  public init(bundle: Bundle = .main) {
    self.bundle = bundle
  }

  public func resolve(address: String) async throws -> ResolveResult {
    guard let url = bundle.url(forResource: "resolve.example", withExtension: "json") else {
      throw URLError(.fileDoesNotExist)
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder.entrance.decode(ResolveResult.self, from: data)
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
