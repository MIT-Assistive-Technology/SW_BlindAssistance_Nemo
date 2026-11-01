//  DoorSighting.swift
//  nemo-software
//
//  What the camera tells navigation in the last stretch (the door finder). The building
//  check (`BuildingSighting`) corrects the compass from far away; this is the close-up
//  version: "something that marks the door is over there, this far off the way the
//  phone is pointing".
//
//  The offset is relative to the camera, not to north. The rider holds the phone up
//  facing forward, so "slightly right of the camera" is "slightly right of you", and
//  the compass, the weakest sensor this close to a building, isn't involved at all.
//
//  What a sighting is NOT: proof that this is the entrance. A LiDAR door is a door; a
//  "77" or an ENTRANCE sign is a clue. The phrases say so (SAFE-1).
//

import Foundation

/// Words on or beside a door that are worth steering to. A fixed list, so every spoken
/// phrase is one SAFE-1 has seen; nothing read by the camera is spoken free-form.
nonisolated public enum EntranceWord: String, CaseIterable, Hashable, Sendable {
  case entrance
  case push
  case pull
  case automaticDoor
}

/// Text that marks the door: the building's own number or name from the bundle, or an
/// entrance word.
nonisolated public enum DoorClue: Hashable, Sendable {
  /// A string from the bundle's `recognize.text` (house number or name), e.g. "77".
  case buildingText(String)
  case entranceSign(EntranceWord)
}

nonisolated public struct DoorSighting: Equatable, Sendable {
  public enum Kind: Hashable, Sendable {
    /// ARKit's LiDAR scene reconstruction classified a surface as a door.
    case door
    case clue(DoorClue)
  }

  public let kind: Kind
  /// Degrees from the camera's forward direction to the sighting, negative to the left.
  public let offsetDegrees: Double
  /// Horizontal distance, when it's known (LiDAR). Text reads have no depth.
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

  /// Offset of a point at normalized x (0 = left edge, 1 = right edge of the portrait
  /// image) for a pinhole camera with this horizontal field of view.
  public static func offsetDegrees(normalizedX: Double, fovDegrees: Double) -> Double {
    let halfWidth = tan(fovDegrees / 2 * .pi / 180)
    return atan((normalizedX - 0.5) * 2 * halfWidth) * 180 / .pi
  }
}
