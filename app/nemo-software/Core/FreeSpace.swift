//  FreeSpace.swift
//  nemo-software
//
//  What's in front of the rider, reduced to a handful of wedges. The free-space scan
//  (depth, on LiDAR phones; a monocular model elsewhere) fills this in a couple of
//  times a second while the walk runs. Navigation uses it two ways: the steering
//  picker picks the clear slice closest to the route, and each blocked or dropping
//  slice becomes a `HazardSighting` the session can announce.
//
//  The slices are camera-relative, like `DoorSighting.offsetDegrees`: negative is
//  left of where the phone points, not of north.
//
//  `nonisolated`: pure value types, produced on the AR and perception queues.
//

import Foundation
import simd

/// A wedge of the view ahead. Ordered left to right so index 0 is the leftmost slice.
nonisolated public struct FreeSpace: Equatable, Sendable {
  public enum Status: Equatable, Sendable {
    /// Ground, walkable, as far as the scan can see.
    case clear
    /// Something sticks up out of the ground inside this slice. `meters` is the
    /// nearest point of it, when metric depth is available.
    case blocked(meters: Double?)
    /// The ground drops away inside this slice: a curb, a step down, a hole.
    case drop(meters: Double?)
    /// The ground rises inside this slice: a step or a shallow rise. Reported apart
    /// from `blocked` because "step up ahead" is the useful warning.
    case stepUp(meters: Double?)
    /// Not enough depth readings to say anything about this slice. Unknown is not
    /// clear: the steering picker must not pick it on purpose.
    case unknown
  }

  public struct Slice: Equatable, Sendable {
    /// Centre of the wedge, degrees from the camera's forward direction, negative left.
    public var offsetDegrees: Double
    public var status: Status

    public init(offsetDegrees: Double, status: Status) {
      self.offsetDegrees = offsetDegrees
      self.status = status
    }
  }

  public var slices: [Slice]
  public var timestamp: Date

  public init(slices: [Slice], timestamp: Date = Date()) {
    self.slices = slices
    self.timestamp = timestamp
  }

  /// Slices the scan can see and found nothing in. Steering chooses from these.
  public var clearSlices: [Slice] {
    slices.filter { $0.status == .clear }
  }

  /// The slice covering a camera-relative offset, used to fuse an object detection's
  /// direction with the depth scan's distance. Nil when the offset is outside the
  /// scanned field of view.
  public func slice(containingOffsetDegrees degrees: Double) -> Slice? {
    slices.min { abs($0.offsetDegrees - degrees) < abs($1.offsetDegrees - degrees) }
      .flatMap { nearest in
        guard let span = sliceSpanDegrees,
          abs(nearest.offsetDegrees - degrees) <= span / 2 else { return nil }
        return nearest
      }
  }

  private var sliceSpanDegrees: Double? {
    guard slices.count > 1 else { return nil }
    return abs(slices[1].offsetDegrees - slices[0].offsetDegrees)
  }
}

/// A metric depth map in the camera's frame, ready to be turned into a `FreeSpace`.
/// On LiDAR phones this is `ARFrame.sceneDepth` copied out before the frame is released.
nonisolated public struct DepthFrame: Sendable {
  /// Row-major depth in meters along the camera's forward axis (z-depth, not radial
  /// distance). Values ≤ 0 mean no reading.
  public var depths: [Float]
  public var width: Int
  public var height: Int
  /// Camera intrinsics scaled to the depth map's resolution (not the photo's).
  public var intrinsics: simd_float3x3
  /// Camera-to-world transform at capture time (ARKit's `camera.transform`).
  public var cameraTransform: simd_float4x4
  /// Per-pixel confidence (ARKit's `ARConfidenceLevel`: 0, 1, 2). Readings below 1
  /// are dropped. Nil means "trust everything".
  public var confidence: [UInt8]?

  public init(
    depths: [Float], width: Int, height: Int, intrinsics: simd_float3x3,
    cameraTransform: simd_float4x4, confidence: [UInt8]? = nil
  ) {
    self.depths = depths
    self.width = width
    self.height = height
    self.intrinsics = intrinsics
    self.cameraTransform = cameraTransform
    self.confidence = confidence
  }
}

/// Relative inverse depth from a monocular model (Depth Anything V2 Small): larger is
/// closer, but there is no metric scale, so a `FreeSpace` built from it reports
/// distances as unknown.
nonisolated public struct DisparityFrame: Sendable {
  /// Row-major, normalized to 0...1 by the estimator.
  public var values: [Float]
  public var width: Int
  public var height: Int

  public init(values: [Float], width: Int, height: Int) {
    self.values = values
    self.width = width
    self.height = height
  }
}
