import XCTest

@testable import CarToCurbLogic

final class ContractTests: XCTestCase {
  func testDecodesResolveExample() throws {
    let r = try Fixtures.example()
    XCTAssertEqual(r.destinationId, "dst_example")
    XCTAssertEqual(r.status, "complete")
    XCTAssertEqual(r.building.osmId, "way/0000001")
    XCTAssertEqual(r.building.housenumber, "77")
    XCTAssertEqual(r.building.footprint.count, 5)
    XCTAssertEqual(r.candidates.map(\.id), ["c1", "c2", "c3"])
    XCTAssertEqual(r.candidates.map(\.band), ["main", "door", "facade"])
    let first = r.candidates[0]
    XCTAssertEqual(first.lat, 42.35921)
    XCTAssertEqual(first.speak?.automaticDoor, "button")
    XCTAssertEqual(first.speak?.stepCount, 3)
    XCTAssertEqual(first.provenance.first?.tags?["entrance"], "main")
    XCTAssertNil(r.candidates[1].speak)
    XCTAssertNil(r.candidates[2].provenance.first?.ref)
    XCTAssertFalse(r.pathChecks.crossesRoad)
    XCTAssertNil(r.pathChecks.nearestCrossing)
    XCTAssertTrue(r.pathChecks.footwayToEntrance)
    XCTAssertEqual(r.streetSide?.entranceStreet, "Example Avenue")
    XCTAssertEqual(r.streetSide?.doorSideOfRoad, "right")
    XCTAssertEqual(r.streetSide?.oneway, false)
    XCTAssertEqual(r.streetSide?.centerline.count, 2)
    XCTAssertEqual(r.recognize?.text, ["77", "Example Building"])
    XCTAssertEqual(r.landmarks?.count, 2)
    XCTAssertEqual(r.landmarks?.first?.metersToDoor, 14)
    XCTAssertEqual(r.landmarks?.last?.atDoor, true)
    XCTAssertNil(r.route)
    XCTAssertEqual(r.attribution, ["© OpenStreetMap contributors"])
    XCTAssertEqual(r.dataVersion.osm, "2026-10-01")
    XCTAssertEqual(r.dataVersion.model, "none")
  }

  func testDecodesBundleManifest() throws {
    let json = """
      [
        {"id": "mit-bldg-7", "address": "77 Massachusetts Ave, Cambridge, MA",
         "osm_id": "way/0000001", "data_version": {"osm": "2026-10-01", "model": "none"},
         "sha256": "abc123", "url": "/v1/bundles/mit-bldg-7"},
        {"id": "other", "address": null, "osm_id": "way/2", "sha256": "def", "url": "/v1/bundles/other"}
      ]
      """
    let entries = try JSONDecoder.entrance.decode([BundleManifestEntry].self, from: Data(json.utf8))
    XCTAssertEqual(entries.count, 2)
    XCTAssertEqual(entries[0].osmId, "way/0000001")
    XCTAssertEqual(entries[0].dataVersion?.osm, "2026-10-01")
    XCTAssertEqual(entries[0].url, "/v1/bundles/mit-bldg-7")
    XCTAssertNil(entries[1].address)
    XCTAssertNil(entries[1].dataVersion)
  }
}
