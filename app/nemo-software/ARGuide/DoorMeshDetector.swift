//  DoorMeshDetector.swift
//  nemo-software
//
//  Door finder, LiDAR half. On iPhones with LiDAR (Pro models), ARKit's scene
//  reconstruction labels each face of its mesh: wall, floor, window, door, and so on.
//  This finds the nearest cluster of "door" faces in front of the camera and reports
//  where it is relative to the way the phone points, and how far.
//
//  Runs on ARGuide's AR queue, a couple of times a second. It reads the mesh buffers in
//  place and keeps nothing: no ARFrame and no ARMeshAnchor outlives the call.
//

import ARKit
import Foundation
import simd

nonisolated struct DoorMeshHit: Equatable, Sendable {
  /// Degrees from the camera's forward direction, negative to the left.
  let offsetDegrees: Double
  /// Horizontal distance from the camera, in meters.
  let meters: Double
  /// How many door faces made up the cluster; more is surer.
  let faceCount: Int
}

nonisolated enum DoorMeshDetector {
  /// Doors further than this are ignored: the mesh is sparse out there, and by then GPS
  /// and the text reader are doing the steering.
  static let maxMeters: Float = 8
  /// Door faces within this of the nearest one are the same door.
  static let clusterMeters: Float = 0.8
  /// Fewer faces than this is a mislabelled scrap of wall.
  static let minFaces = 12
  /// Only what's roughly in front of the phone (±75°), not behind the rider.
  static let maxOffsetDegrees: Double = 75

  static var isSupported: Bool {
    ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification)
  }

  /// The nearest door in front of the camera, or nil.
  static func nearestDoor(anchors: [ARMeshAnchor], camera: simd_float4x4) -> DoorMeshHit? {
    let cameraPosition = SIMD3<Float>(camera.columns.3.x, camera.columns.3.y, camera.columns.3.z)
    // The back camera looks along its -Z axis; +X is to its right.
    let forward = SIMD2<Float>(-camera.columns.2.x, -camera.columns.2.z)
    let right = SIMD2<Float>(camera.columns.0.x, camera.columns.0.z)
    guard simd_length(forward) > 0.3 else { return nil }  // pointing at the ground

    var doorPoints: [SIMD3<Float>] = []
    for anchor in anchors {
      let anchorPosition = SIMD3<Float>(
        anchor.transform.columns.3.x, anchor.transform.columns.3.y, anchor.transform.columns.3.z)
      // Mesh anchors cover a few meters each; skip whole ones that are far away.
      guard simd_distance(anchorPosition, cameraPosition) < maxMeters + 3 else { continue }
      doorPoints.append(contentsOf: doorFaceCentres(of: anchor))
    }
    guard !doorPoints.isEmpty else { return nil }

    // Keep what's ahead and in range, nearest first.
    let candidates =
      doorPoints
      .map { point -> (point: SIMD3<Float>, flat: SIMD2<Float>, meters: Float) in
        let flat = SIMD2<Float>(point.x - cameraPosition.x, point.z - cameraPosition.z)
        return (point, flat, simd_length(flat))
      }
      .filter { $0.meters <= maxMeters && simd_dot($0.flat, forward) > 0 }
      .sorted { $0.meters < $1.meters }
    guard let nearest = candidates.first else { return nil }

    let cluster = candidates.filter { simd_distance($0.point, nearest.point) <= clusterMeters }
    guard cluster.count >= minFaces else { return nil }
    let centre = cluster.reduce(SIMD2<Float>(0, 0)) { $0 + $1.flat } / Float(cluster.count)

    let offset =
      Double(atan2(simd_dot(centre, simd_normalize(right)), simd_dot(centre, simd_normalize(forward))))
      * 180 / .pi
    guard abs(offset) <= maxOffsetDegrees else { return nil }
    return DoorMeshHit(
      offsetDegrees: offset, meters: Double(simd_length(centre)), faceCount: cluster.count)
  }

  /// World-space centres of the faces classified as `.door`.
  private static func doorFaceCentres(of anchor: ARMeshAnchor) -> [SIMD3<Float>] {
    let geometry = anchor.geometry
    guard let classification = geometry.classification else { return [] }
    let faces = geometry.faces
    let vertices = geometry.vertices
    guard faces.indexCountPerPrimitive == 3 else { return [] }

    let classBase = classification.buffer.contents().advanced(by: classification.offset)
    let faceBase = faces.buffer.contents()
    let vertexBase = vertices.buffer.contents().advanced(by: vertices.offset)
    let doorValue = UInt8(ARMeshClassification.door.rawValue)

    func vertex(_ index: Int) -> SIMD3<Float> {
      let p = vertexBase.advanced(by: vertices.stride * index)
        .assumingMemoryBound(to: (Float, Float, Float).self).pointee
      return SIMD3<Float>(p.0, p.1, p.2)
    }
    func vertexIndex(face: Int, corner: Int) -> Int {
      let at = faceBase.advanced(by: (face * 3 + corner) * faces.bytesPerIndex)
      return faces.bytesPerIndex == 2
        ? Int(at.assumingMemoryBound(to: UInt16.self).pointee)
        : Int(at.assumingMemoryBound(to: UInt32.self).pointee)
    }

    var centres: [SIMD3<Float>] = []
    for face in 0..<faces.count {
      let value = classBase.advanced(by: classification.stride * face)
        .assumingMemoryBound(to: UInt8.self).pointee
      guard value == doorValue else { continue }
      let local =
        (vertex(vertexIndex(face: face, corner: 0)) + vertex(vertexIndex(face: face, corner: 1))
          + vertex(vertexIndex(face: face, corner: 2))) / 3
      let world = anchor.transform * SIMD4<Float>(local.x, local.y, local.z, 1)
      centres.append(SIMD3<Float>(world.x, world.y, world.z))
    }
    return centres
  }
}
