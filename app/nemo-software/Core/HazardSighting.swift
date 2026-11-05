//  HazardSighting.swift
//  nemo-software
//
//  What perception tells navigation is in the way (Person B; the counterpart of
//  `DoorSighting`, which marks the goal). Two sources produce the same message:
//  the object detector names things (person, car, bike, pole, cone), and the
//  free-space scan reports "something" it can't name plus the ground dropping away.
//
//  The offset is relative to the camera, like `DoorSighting.offsetDegrees` — the
//  rider holds the phone facing forward, so camera-right is their right.
//
//  What a sighting is NOT: a promise that the path is safe. The cane still leads;
//  these are notices, not clearance (plan: supplement, never replace).
//

import Foundation

nonisolated public struct HazardSighting: Equatable, Sendable {
  /// The kinds worth interrupting a rider for. A fixed list, so every spoken hazard
  /// phrase is one SAFE-1 has seen; detector labels are mapped onto it, never spoken
  /// free-form.
  public enum Kind: String, CaseIterable, Hashable, Sendable {
    case person
    case vehicle
    case bike
    case pole
    case cone
    case bench
    /// Barriers, barricades, scaffolding — worksites in the lane.
    case construction
    /// Named apart from other animals: a strange dog distracts a guide dog.
    case dog
    case animal
    /// A wall, fence or building face in the lane.
    case wall
    /// Depth saw something in the walking lane but the detector didn't name it.
    case object
    /// The ground drops away: a curb or a step down. From depth, not the detector.
    case stepDown
    /// The ground rises: a step or a shallow rise. From depth, not the detector.
    case stepUp

    /// Maps a detector's label onto the fixed list. Common object-detection labels
    /// (COCO names) and likely custom names (pole, cone) are covered; anything else
    /// is nil, meaning "seen but not worth a spoken hazard".
    public init?(label: String) {
      switch label.lowercased() {
      case "person": self = .person
      case "car", "truck", "bus", "van": self = .vehicle
      case "bicycle", "motorcycle", "bike", "scooter": self = .bike
      case "pole", "bollard", "parking meter", "signpost": self = .pole
      case "cone", "traffic cone", "trafficcone": self = .cone
      case "bench": self = .bench
      case "barrier", "barricade", "sawhorse", "scaffolding", "construction":
        self = .construction
      case "dog": self = .dog
      case "cat", "bird", "squirrel", "pigeon", "animal", "pet": self = .animal
      case "wall", "fence", "foundation", "building": self = .wall
      default:
        // Compound custom labels ("traffic cone on sidewalk" and friends).
        let name = label.lowercased()
        if name.contains("cone") { self = .cone } else if name.contains("dog") {
          self = .dog
        } else { return nil }
      }
    }
  }

  public let kind: Kind
  /// Degrees from the camera's forward direction, negative to the left.
  public let offsetDegrees: Double
  /// Horizontal distance, when depth knows it. Detector-only sightings have none.
  public let meters: Double?
  /// 0...1.
  public let confidence: Double
  public let timestamp: Date

  public init(
    kind: Kind, offsetDegrees: Double, meters: Double? = nil, confidence: Double = 1,
    timestamp: Date = Date()
  ) {
    self.kind = kind
    self.offsetDegrees = offsetDegrees
    self.meters = meters
    self.confidence = confidence
    self.timestamp = timestamp
  }
}
