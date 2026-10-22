//  EntranceClient.swift
//  nemo-software
//
//  Talks to the entrance service. Sends ONLY the destination address, never the rider's
//  location, camera frames or any install id. Results are saved in `BundleStore` so
//  guidance works with no signal after drop-off.
//
//  The base URL comes from Settings (UserDefaults "entranceBaseURL"); empty means the stub.
//

import CryptoKit
import Foundation

public protocol EntranceClient: AnyObject {
  /// Resolve a destination address into ranked door candidates.
  func resolve(address: String) async throws -> ResolveResult
}

/// Returns the bundled `resolve.example.json`. Use it to build app features before
/// the server is running, and in previews and tests.
public final class StubEntranceClient: EntranceClient {
  public init() {}

  public func resolve(address: String) async throws -> ResolveResult {
    guard let url = Bundle.main.url(forResource: "resolve.example", withExtension: "json") else {
      throw URLError(.fileDoesNotExist)
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder.entrance.decode(ResolveResult.self, from: data)
  }
}

/// The pilot entrance service. Downloads every precomputed bundle at setup
/// (`GET /v1/bundles`, then `GET /v1/bundles/{id}` with `If-None-Match`), and answers
/// lookups from the phone first.
final class LiveEntranceClient: EntranceClient {
  static let baseURLKey = "entranceBaseURL"

  private let baseURL: URL
  private let store: BundleStore
  private let urlSession: URLSession

  init(baseURL: URL, store: BundleStore, urlSession: URLSession = .shared) {
    self.baseURL = baseURL
    self.store = store
    self.urlSession = urlSession
  }

  /// The base URL saved in Settings, or nil (use the stub) when empty or not http(s).
  static func savedBaseURL(_ defaults: UserDefaults = .standard) -> URL? {
    let text = (defaults.string(forKey: baseURLKey) ?? "").trimmingCharacters(in: .whitespaces)
    guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
      scheme == "https" || scheme == "http", url.host != nil
    else { return nil }
    return url
  }

  /// Downloads the manifest and every new or changed bundle. Returns how many were saved.
  /// A bundle whose bytes don't match the manifest's sha256 is skipped, not saved.
  @discardableResult
  func refreshBundles() async throws -> Int {
    let (data, response) = try await urlSession.data(for: request(path: "v1/bundles"))
    try Self.requireOK(response)
    let manifest = try JSONDecoder.entrance.decode([BundleManifestEntry].self, from: data)

    var saved = 0
    for item in manifest {
      let known = store.entry(id: item.id)
      if known?.sha256 == item.sha256 { continue }

      var get = request(path: "v1/bundles/\(item.id)")
      if let etag = known?.etag { get.setValue(etag, forHTTPHeaderField: "If-None-Match") }
      guard let download = try? await urlSession.data(for: get),
        let http = download.1 as? HTTPURLResponse, http.statusCode == 200
      else { continue }  // 304 or a failed download: keep what we have
      let body = download.0
      guard Self.sha256Hex(body) == item.sha256 else { continue }
      if (try? store.save(
        body, id: item.id, address: item.address, sha256: item.sha256,
        etag: http.value(forHTTPHeaderField: "ETag"))) != nil
      {
        saved += 1
      }
    }
    return saved
  }

  func resolve(address: String) async throws -> ResolveResult {
    if let cached = store.bundle(matchingAddress: address) { return cached }

    var post = request(path: "v1/resolve")
    post.httpMethod = "POST"
    post.setValue("application/json", forHTTPHeaderField: "Content-Type")
    post.httpBody = try JSONEncoder().encode(["address": address])
    let (data, response) = try await urlSession.data(for: post)
    try Self.requireOK(response)
    let result = try JSONDecoder.entrance.decode(ResolveResult.self, from: data)
    try? store.save(data, id: result.destinationId, address: address)
    return result
  }

  // MARK: - Private

  private func request(path: String) -> URLRequest {
    var request = URLRequest(url: baseURL.appendingPathComponent(path))
    // ETags are handled here, not by the URL cache.
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.timeoutInterval = 15
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return request
  }

  private static func requireOK(_ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    switch http.statusCode {
    case 200: return
    case 404: throw URLError(.fileDoesNotExist)
    default: throw URLError(.badServerResponse)
    }
  }

  private static func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
