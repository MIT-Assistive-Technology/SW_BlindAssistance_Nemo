//  BundleStoreTests.swift
//  nemo-softwareTests
//
//  FE-11: the bundle has to survive a relaunch and work with no network, so these tests
//  write to a real temporary directory and read it back with a brand new store, the way
//  a cold launch would.
//

import XCTest

@testable import nemo_software

final class BundleStoreTests: XCTestCase {

  private var directory: URL!
  private var store: BundleStore!
  private let address = "77 Massachusetts Ave, Cambridge, MA"

  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("BundleStoreTests-\(UUID().uuidString)", isDirectory: true)
    store = BundleStore(directory: directory)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    try super.tearDownWithError()
  }

  private func exampleBundle() async throws -> ResolveResult {
    try await StubEntranceClient().resolve(address: address)
  }

  // MARK: Round trip

  func testSaveThenReadBack() async throws {
    let bundle = try await exampleBundle()
    try store.save(bundle, for: address)

    let cached = try XCTUnwrap(store.cached(for: address))
    XCTAssertEqual(cached.address, address)
    XCTAssertEqual(cached.result.destinationId, bundle.destinationId)
    XCTAssertEqual(cached.result.candidates.count, bundle.candidates.count)
    XCTAssertEqual(cached.result.candidates.first?.band, "main")
    XCTAssertEqual(cached.result.streetSide?.doorSideOfRoad, "right")
    XCTAssertEqual(cached.result.streetSide?.centerline.count, 2)
    XCTAssertEqual(cached.result.landmarks?.first?.metersToDoor, 14)
    XCTAssertEqual(cached.result.attribution, ["© OpenStreetMap contributors"])
  }

  func testRawOSMTagsSurviveTheRoundTrip() async throws {
    // snake_case conversion must not touch the keys inside `tags`, or a door fact like
    // automatic_door would quietly disappear on the second read.
    let bundle = try await exampleBundle()
    try store.save(bundle, for: address)
    let tags = try XCTUnwrap(store.cached(for: address)?.result.candidates.first?.provenance
      .first?.tags)
    XCTAssertEqual(tags["entrance"], "main")
    XCTAssertEqual(tags["wheelchair"], "yes")
  }

  func testSpokenDoorFactsSurviveTheRoundTrip() async throws {
    let bundle = try await exampleBundle()
    try store.save(bundle, for: address)
    let speak = try XCTUnwrap(store.cached(for: address)?.result.candidates.first?.speak)
    XCTAssertEqual(speak.stepCount, 3)
    XCTAssertEqual(speak.automaticDoor, "button")
    XCTAssertEqual(speak.door, "hinged")
  }

  // MARK: Relaunch

  func testADifferentStoreOnTheSameDirectoryFindsIt() async throws {
    let bundle = try await exampleBundle()
    try store.save(bundle, for: address)

    // A new store is what a relaunched app gets.
    let afterRelaunch = BundleStore(directory: directory)
    XCTAssertEqual(afterRelaunch.result(for: address)?.destinationId, bundle.destinationId)
    XCTAssertEqual(afterRelaunch.allCached().count, 1)
  }

  func testAllCachedIsNewestFirst() async throws {
    let bundle = try await exampleBundle()
    let old = BundleStore(directory: directory, now: { Date(timeIntervalSince1970: 1_000) })
    let new = BundleStore(directory: directory, now: { Date(timeIntervalSince1970: 2_000) })
    try old.save(bundle, for: "1 First Street")
    try new.save(bundle, for: "2 Second Street")

    XCTAssertEqual(store.allCached().map { $0.address }, ["2 Second Street", "1 First Street"])
  }

  func testFetchedAtIsRecorded() async throws {
    let bundle = try await exampleBundle()
    let fixed = Date(timeIntervalSince1970: 1_700_000_000)
    let dated = BundleStore(directory: directory, now: { fixed })
    try dated.save(bundle, for: address)
    XCTAssertEqual(store.cached(for: address)?.fetchedAt, fixed)
  }

  // MARK: Addresses

  func testAddressesThatDifferOnlyInPunctuationShareOneEntry() async throws {
    let bundle = try await exampleBundle()
    try store.save(bundle, for: "77 Massachusetts Ave., Cambridge, MA")
    XCTAssertNotNil(store.cached(for: "77 massachusetts ave  cambridge ma"))
    XCTAssertNotNil(store.cached(for: " 77 Massachusetts Ave Cambridge MA "))
    XCTAssertEqual(store.allCached().count, 1)
  }

  func testDifferentAddressesAreSeparate() async throws {
    let bundle = try await exampleBundle()
    try store.save(bundle, for: "77 Massachusetts Ave")
    try store.save(bundle, for: "79 Massachusetts Ave")
    XCTAssertEqual(store.allCached().count, 2)
  }

  func testNormalizedAddress() {
    XCTAssertEqual(
      BundleStore.normalizedAddress("77 Massachusetts Ave., Cambridge, MA"),
      "77 massachusetts ave cambridge ma")
    XCTAssertEqual(BundleStore.normalizedAddress("  Rue Montéé  "), "rue montee")
  }

  func testMissingAddressReadsAsNil() {
    XCTAssertNil(store.cached(for: "nowhere at all"))
    XCTAssertNil(store.result(for: "nowhere at all"))
    XCTAssertEqual(store.allCached().count, 0)
  }

  // MARK: Removing

  func testRemove() async throws {
    let bundle = try await exampleBundle()
    try store.save(bundle, for: address)
    try store.remove(for: address)
    XCTAssertNil(store.cached(for: address))
    XCTAssertThrowsError(try store.remove(for: address)) { error in
      XCTAssertEqual(error as? BundleStore.StoreError, .notFound)
    }
  }
}
