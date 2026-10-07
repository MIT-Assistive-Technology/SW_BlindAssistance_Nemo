//  EntranceModels.swift
//  nemo-software
//
//  Codable mirror of an entrance bundle. In the MVP these are precomputed for the pilot
//  sites; the live `POST /v1/resolve` (stretch goal) returns the same shape.
//  Source of truth: `contract/resolve.example.json` and
//  docs/car-to-curb-plan.md section 10. Change the contract first, then this file,
//  then `server/app/models.py`. The contract tests keep all three in sync.
//
//  Decode with `JSONDecoder.entrance` (snake_case keys -> camelCase properties).
//

import Foundation

public struct ResolveResult: Codable, Sendable {
  public let destinationId: String
  /// "complete", or "partial" when the result is weak (fetch again later).
  public let status: String
  public let building: Building
  /// Best first. The phone guides to `candidates[0]` and keeps the rest as backups.
  public let candidates: [Candidate]
  public let pathChecks: PathChecks
  public let streetSide: StreetSide?
  public let recognize: Recognize?
  public let landmarks: [Landmark]?
  /// Valhalla walking route as [lon, lat] waypoints; nil for straight-line guidance.
  public let route: [[Double]]?
  public let attribution: [String]
  public let dataVersion: DataVersion
}

public struct Building: Codable, Sendable {
  public let osmId: String
  public let name: String?
  public let housenumber: String?
  /// Outline as [lon, lat] pairs.
  public let footprint: [[Double]]
}

public struct Candidate: Codable, Sendable, Identifiable {
  public let id: String
  public let lat: Double
  public let lon: Double
  /// 0...0.95 from the server. Only the phone's camera can confirm a door.
  public let confidence: Double
  /// What the rider hears: "main" ("Map shows the main entrance"), "door" ("Map shows a
  /// door") or "facade" ("No door on the map. Guiding you to the street-facing side.").
  public let band: String
  public let label: String
  public let speak: Speak?
  public let provenance: [Provenance]
}

/// Door details worth saying aloud. Every field is optional because OSM rarely has them.
public struct Speak: Codable, Sendable {
  public let door: String?
  public let automaticDoor: String?
  public let stepCount: Int?
}

public struct Provenance: Codable, Sendable {
  /// "osm_tag", "mapillary_cv", "crowd" or "geometry_fallback".
  public let source: String
  public let ref: String?
  public let tags: [String: String]?
}

public struct PathChecks: Codable, Sendable {
  public let crossesRoad: Bool
  /// [lon, lat] of the nearest `footway=crossing`, when the path crosses a road.
  public let nearestCrossing: [Double]?
  public let footwayToEntrance: Bool
}

/// Inputs for side-of-street detection when the car stops (FE-13).
public struct StreetSide: Codable, Sendable {
  public let entranceStreet: String
  public let roadWay: String
  /// Road centerline as [lon, lat] pairs.
  public let centerline: [[Double]]
  /// "left" or "right", relative to the centerline's direction (first → last point).
  public let doorSideOfRoad: String
  public let oneway: Bool
}

/// Text the camera building check should look for (CV-9).
public struct Recognize: Codable, Sendable {
  public let text: [String]
}

public struct Landmark: Codable, Sendable {
  public let kind: String
  public let lat: Double
  public let lon: Double
  public let side: String
  public let metersToDoor: Double
  public let atDoor: Bool
  public let source: String
  public let speak: String
}

public struct DataVersion: Codable, Sendable {
  public let osm: String
  public let model: String
}

extension JSONDecoder {
  /// Decoder configured for the entrance service's snake_case JSON.
  public static var entrance: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }
}
