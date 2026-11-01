//  EntranceClientTests.swift
//  nemo-softwareTests
//
//  FE-11: the contract decodes, the live client sends what plan section 10 says, and a
//  network failure at the curb falls back to the copy on the phone.
//

import XCTest

@testable import nemo_software

final class EntranceClientTests: XCTestCase {

  private let address = "77 Massachusetts Ave, Cambridge, MA"

  // MARK: The contract

  func testBundledExampleDecodes() async throws {
    let result = try await StubEntranceClient().resolve(address: address)
    XCTAssertEqual(result.destinationId, "dst_example")
    XCTAssertEqual(result.status, "complete")
    XCTAssertEqual(result.building.housenumber, "77")
    XCTAssertEqual(result.candidates.map { $0.band }, ["main", "door", "facade"])
    XCTAssertEqual(result.target?.id, "c1")
    XCTAssertEqual(result.pathChecks.crossesRoad, false)
    XCTAssertNil(result.pathChecks.nearestCrossing)
    XCTAssertEqual(result.recognize?.text, ["77", "Example Building"])
    XCTAssertEqual(result.landmarks?.count, 2)
    XCTAssertNil(result.route)
    XCTAssertEqual(result.dataVersion.osm, "2026-10-01")
  }

  func testTagKeysAreNotSnakeCaseConverted() throws {
    // `convertFromSnakeCase` renames properties, not the keys of a [String: String], so
    // real OSM tags such as automatic_door come through untouched. If this ever fails,
    // door facts would silently vanish from the brief.
    let json = Data(
      """
      { "source": "osm_tag", "ref": "node/1",
        "tags": { "automatic_door": "button", "step_count": "3" } }
      """.utf8)
    let provenance = try JSONDecoder.entrance.decode(Provenance.self, from: json)
    XCTAssertEqual(provenance.source, "osm_tag")
    XCTAssertEqual(provenance.tags?["automatic_door"], "button")
    XCTAssertEqual(provenance.tags?["step_count"], "3")
  }

  func testDerivedDistancesAndBearings() async throws {
    let result = try await StubEntranceClient().resolve(address: address)
    // Standing 0.0005° (about 55 m) north of the door.
    let meters = try XCTUnwrap(result.metersToTarget(fromLat: 42.35971, fromLon: -71.09298))
    XCTAssertEqual(meters, 55.6, accuracy: 1.0)
    let bearing = try XCTUnwrap(result.bearingToTarget(fromLat: 42.35971, fromLon: -71.09298))
    XCTAssertEqual(bearing, 180, accuracy: 0.1)
    // The example has no marked crossing.
    XCTAssertNil(result.metersToNearestCrossing(fromLat: 42.35971, fromLon: -71.09298))
  }

  func testDestinationBriefFromTheBundle() async throws {
    let result = try await StubEntranceClient().resolve(address: address)
    let brief = result.destinationBrief(metersToDoor: 33.5)
    XCTAssertEqual(brief.band, "main")
    XCTAssertEqual(brief.entranceStreet, "Example Avenue")
    XCTAssertEqual(brief.streetSideDescription, "west")
    XCTAssertEqual(brief.housenumber, "77")
    XCTAssertEqual(brief.stepCount, 3)
    XCTAssertEqual(brief.automaticDoor, "button")
  }

  // MARK: Caching (FE-11)

  func testFreshResultIsSavedForLater() async throws {
    let store = temporaryStore()
    let client = CachingEntranceClient(upstream: StubEntranceClient(), store: store)
    _ = try await client.resolve(address: address)
    XCTAssertNotNil(store.cached(for: address))
  }

  func testNetworkFailureFallsBackToThePhone() async throws {
    let store = temporaryStore()
    // One good fetch before the ride...
    let fresh = try await CachingEntranceClient(upstream: StubEntranceClient(), store: store)
      .resolveBundle(address: address)
    XCTAssertFalse(fresh.fromCache)
    // ...then no signal at the curb.
    let offline = CachingEntranceClient(upstream: FailingClient(), store: store)
    let resolved = try await offline.resolveBundle(address: address)
    XCTAssertEqual(resolved.result.destinationId, "dst_example")
    // The app has to know it is walking from a saved copy, and how old it is.
    XCTAssertTrue(resolved.fromCache)
    XCTAssertNotNil(resolved.fetchedAt)
  }

  func testNetworkFailureWithAnEmptyCacheThrows() async {
    let offline = CachingEntranceClient(upstream: FailingClient(), store: temporaryStore())
    do {
      _ = try await offline.resolve(address: address)
      XCTFail("expected a failure")
    } catch {
      XCTAssertEqual(error as? URLError, URLError(.notConnectedToInternet))
    }
  }

  func testCachedResultThrowsWhenNothingIsStored() {
    let client = CachingEntranceClient(upstream: FailingClient(), store: temporaryStore())
    XCTAssertThrowsError(try client.cachedResult(for: address)) { error in
      XCTAssertEqual(error as? EntranceError, .noCachedResult)
    }
  }

  // MARK: The live client (FE-11, stretch server)

  func testLiveClientPostsTheAddressAndInstallKey() async throws {
    let json = try bundledExampleJSON()
    StubURLProtocol.handler = { request in
      XCTAssertEqual(request.httpMethod, "POST")
      XCTAssertEqual(request.url?.path, "/v1/resolve")
      XCTAssertEqual(request.value(forHTTPHeaderField: "X-Install-Key"), "test-key")
      XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
      let body = StubURLProtocol.body(of: request)
      XCTAssertEqual(
        try? JSONDecoder().decode([String: String].self, from: body ?? Data()),
        ["address": "77 Massachusetts Ave, Cambridge, MA"])
      return (200, json)
    }
    let client = LiveEntranceClient(
      baseURL: URL(string: "https://example.invalid")!, session: stubSession(),
      installKey: "test-key")
    let result = try await client.resolve(address: address)
    XCTAssertEqual(result.destinationId, "dst_example")
  }

  func testLiveClientSurfacesTheErrorEnvelope() async throws {
    StubURLProtocol.handler = { _ in
      (
        404,
        Data(
          """
          { "error": { "code": "GEOCODE_NOT_FOUND", "message": "Address not found",
            "request_id": "req_1" } }
          """.utf8)
      )
    }
    let client = LiveEntranceClient(
      baseURL: URL(string: "https://example.invalid")!, session: stubSession(),
      installKey: "test-key")
    do {
      _ = try await client.resolve(address: "nowhere")
      XCTFail("expected a failure")
    } catch {
      XCTAssertEqual(
        error as? EntranceError,
        .service(
          code: "GEOCODE_NOT_FOUND", message: "Address not found", requestId: "req_1",
          httpStatus: 404))
      // The wording lives in Phrases, so SAFE-1 can see every spoken string.
      XCTAssertEqual(Phrases.lookupFailed(error), "I couldn't find that address.")
    }
  }

  func testLiveClientRejectsJunkBodies() async throws {
    StubURLProtocol.handler = { _ in (200, Data("not json".utf8)) }
    let client = LiveEntranceClient(
      baseURL: URL(string: "https://example.invalid")!, session: stubSession(),
      installKey: "test-key")
    do {
      _ = try await client.resolve(address: address)
      XCTFail("expected a failure")
    } catch {
      XCTAssertEqual(error as? EntranceError, .badResponse(httpStatus: 200))
    }
  }

  // MARK: Install key

  func testInstallKeyIsCreatedOnceAndReused() throws {
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "nemo.tests.\(UUID().uuidString)"))
    let first = InstallKey(defaults: defaults).value
    let second = InstallKey(defaults: defaults).value
    XCTAssertEqual(first, second)
    XCTAssertNotNil(UUID(uuidString: first))
  }

  // MARK: Helpers

  private func temporaryStore() -> BundleStore {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("EntranceClientTests-\(UUID().uuidString)", isDirectory: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return BundleStore(directory: directory)
  }

  private func bundledExampleJSON() throws -> Data {
    let url = try XCTUnwrap(
      Bundle.main.url(forResource: "resolve.example", withExtension: "json"))
    return try Data(contentsOf: url)
  }

  private func stubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    addTeardownBlock { StubURLProtocol.handler = nil }
    return URLSession(configuration: configuration)
  }
}

/// An upstream client with no signal.
private final class FailingClient: EntranceClient {
  func resolve(address: String) async throws -> ResolveResult {
    throw URLError(.notConnectedToInternet)
  }
}

/// Answers requests from a closure, so the live client is tested without a server.
nonisolated final class StubURLProtocol: URLProtocol {
  nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?

  /// URLSession hands the protocol a request whose body may be a stream.
  static func body(of request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let size = 1024
    var buffer = [UInt8](repeating: 0, count: size)
    while stream.hasBytesAvailable {
      let read = stream.read(&buffer, maxLength: size)
      if read <= 0 { break }
      data.append(buffer, count: read)
    }
    return data
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let handler = Self.handler, let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
      return
    }
    let (status, data) = handler(request)
    let response = HTTPURLResponse(
      url: url, statusCode: status, httpVersion: "HTTP/1.1",
      headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
