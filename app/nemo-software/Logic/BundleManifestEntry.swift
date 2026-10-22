//  BundleManifestEntry.swift
//  nemo-software
//
//  One row of `GET /v1/bundles` (server/README.md). Decode with `JSONDecoder.entrance`.
//  `url` is relative to the service base URL, e.g. "/v1/bundles/mit-bldg-7".
//

import Foundation

public struct BundleManifestEntry: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  /// nil when the pilot site list has no address for this bundle.
  public let address: String?
  public let osmId: String
  public let dataVersion: DataVersion?
  /// Also the bundle's ETag.
  public let sha256: String
  public let url: String
}

extension DataVersion: Equatable {
  public static func == (a: DataVersion, b: DataVersion) -> Bool {
    a.osm == b.osm && a.model == b.model
  }
}
