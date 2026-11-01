//  PilotBundleClientTests.swift
//  nemo-softwareTests
//
//  The app's real lookup: pilot bundles shipped in the app, never the made-up example.
//

import XCTest

@testable import nemo_software

final class PilotBundleClientTests: XCTestCase {
  private let client = PilotBundleClient()

  func testShipsThePilotSites() {
    XCTAssertGreaterThanOrEqual(client.sites.count, 10)
  }

  func testStreetAddressFindsBuilding7() async throws {
    for query in ["77 Massachusetts Ave", "77 Mass Ave", "77 Massachusetts Avenue, Cambridge"] {
      let result = try await client.resolve(address: query)
      XCTAssertEqual(result.building.osmId, "way/32517230", query)
    }
  }

  func testNameFindsTheStudentCenter() async throws {
    let byName = try await client.resolve(address: "Student Center")
    let byAddress = try await client.resolve(address: "84 Mass Ave")
    XCTAssertEqual(byName.building.osmId, "way/24494019")
    XCTAssertEqual(byAddress.building.osmId, "way/24494019")
  }

  func testUnknownAddressIsNotFoundNotTheExample() async {
    do {
      _ = try await client.resolve(address: "1 Nowhere Street")
      XCTFail("expected not found")
    } catch {
      XCTAssertEqual(
        error as? EntranceError,
        .service(
          code: "NOT_FOUND", message: "Not a pilot site: 1 Nowhere Street", requestId: nil,
          httpStatus: 404))
    }
  }

  func testSameNumberOnAnotherStreetDoesNotMatch() {
    XCTAssertNil(PilotBundleClient.match("77 Vassar St", in: client.sites))
  }
}
