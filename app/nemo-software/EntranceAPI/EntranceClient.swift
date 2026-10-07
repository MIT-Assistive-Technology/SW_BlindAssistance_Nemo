//  EntranceClient.swift
//  nemo-software
//
//  Talks to the entrance service. Send ONLY the destination address,
//  never the rider's location. The result is cached on the phone so guidance works
//  with no signal after drop-off.
//

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

/// Real client (FE-11).
public final class LiveEntranceClient: EntranceClient {
  private let baseURL: URL

  public init(baseURL: URL) {
    self.baseURL = baseURL
  }

  public func resolve(address: String) async throws -> ResolveResult {
    // TODO (FE-11):
    //   1. POST {baseURL}/v1/resolve with JSON body {"address": address}.
    //      Header X-Install-Key: a random UUID created on first launch (no accounts).
    //   2. 200 -> decode with JSONDecoder.entrance.
    //      202 -> wait `retry_after_s`, then GET /v1/destinations/{destination_id}.
    //   3. Save the result on the phone (SwiftData or a JSON file) keyed by address,
    //      so arrival needs no network.
    //   4. On a network failure, return the cached result if there is one.
    throw URLError(.unsupportedURL)
  }
}
