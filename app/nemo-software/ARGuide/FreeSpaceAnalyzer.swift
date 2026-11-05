//  FreeSpaceAnalyzer.swift
//  nemo-software
//
//  Depth → free space (the "what's in front" half of the walk). Two paths to the same
//  `FreeSpace`:
//
//    - `analyze(_:floorPoints:config:)` — metric depth (LiDAR `sceneDepth`). Find the
//      ground, then flag anything sticking up more than ~15 cm inside the walking
//      lane within about 3 m, and anywhere the ground itself drops away (curbs,
//      steps down). The lane is a corridor about 1.2 m wide centred on each slice's
//      direction, so a slice answers "if I walk this way, is it clear?".
//
//    - `analyze(_:config:)` over a `DisparityFrame` — monocular depth on phones
//      without LiDAR (Depth Anything V2 Small). No metric scale, so blocked slices
//      report `meters: nil` and drops can't be seen at all.
//
//  Ground level comes from the depth map's own below-camera points, or from ARKit
//  mesh faces classified `.floor` when scene reconstruction is on — same mesh code
//  as `DoorMeshDetector`.
//
//  Pure and `nonisolated`: runs on ARGuide's AR queue and the perception queue, and
//  is unit tested on synthetic depth grids.
//

import ARKit
import Foundation
import simd

nonisolated enum FreeSpaceAnalyzer {

  /// Tunables for the metric scan. Starting points, like `GuidanceThresholds` —
  /// measured against the golden-site recordings, not final.
  struct Config: Sendable {
    /// Only what's inside the lane this far ahead is a hazard now.
    var maxMeters: Float = 3
    /// Half the width of the walking corridor around each slice's direction.
    var laneHalfWidthMeters: Float = 0.6
    /// Above ground by more than this, a point is not ground.
    var obstacleAboveGroundMeters: Float = 0.15
    /// A blocked slice whose obstruction never rises higher than this is a step or a
    /// shallow rise, not a wall — "step up ahead" is the useful warning.
    var stepUpMaxHeightMeters: Float = 0.6
    /// Below ground by more than this, a point is a drop. Higher than the obstacle
    /// threshold so the curb itself doesn't read as a step down.
    var dropBelowGroundMeters: Float = 0.2
    /// Points higher than this above the camera are ignored: tree canopy, awnings,
    /// ceilings — things a pedestrian walks under, not into.
    var maxObstacleAboveCameraMeters: Float = 1.0
    /// A point closer than this is the rider's own hand or the phone's edge.
    var minDepthMeters: Float = 0.3
    /// Points used to find the ground level are at most this far away.
    var groundFitMaxMeters: Float = 6
    /// Fewer ground points than this, and ground can't be estimated from depth alone.
    var minGroundPoints = 30
    /// Fewer mesh floor faces than this near the camera, and the mesh seed is ignored.
    var minFloorPoints = 10
    /// A slice needs at least this many valid lane points to be called clear.
    var minSlicePoints = 8
    /// A drop needs this many below-ground points in a slice to count; single sparse
    /// readings below the floor are noise.
    var minDropPoints = 6
    /// Wedge centres, degrees from camera forward, negative left.
    var sliceCentresDegrees: [Double] = [-28, -14, 0, 14, 28]
    /// Read every Nth pixel in each axis; the depth map is small to start with.
    var sampleStride = 2
  }

  /// Metric scan. `floorPoints` are world-space centres of `.floor` mesh faces when
  /// scene reconstruction is on (reuse of `DoorMeshDetector.faceCentres`); pass an
  /// empty array otherwise and the ground is estimated from the depth map itself.
  static func analyze(
    _ frame: DepthFrame,
    floorPoints: [SIMD3<Float>] = [],
    config: Config = Config()
  ) -> FreeSpace {
    func unknown() -> FreeSpace {
      FreeSpace(
        slices: config.sliceCentresDegrees.map {
          FreeSpace.Slice(offsetDegrees: $0, status: .unknown)
        })
    }

    let count = frame.width * frame.height
    guard count > 0, frame.depths.count == count else { return unknown() }
    if let confidence = frame.confidence, confidence.count != count { return unknown() }

    // Camera basis in world space: -Z is forward, +X is right (same convention as
    // DoorMeshDetector.nearestDoor).
    let transform = frame.cameraTransform
    let cameraPosition = SIMD3<Float>(
      transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    let forward = SIMD2<Float>(-transform.columns.2.x, -transform.columns.2.z)
    guard simd_length(forward) > 0.3 else { return unknown() }  // pointing at the ground
    let forwardN = simd_normalize(forward)
    let rightN = simd_normalize(SIMD2<Float>(transform.columns.0.x, transform.columns.0.z))

    let fx = frame.intrinsics[0][0], fy = frame.intrinsics[1][1]
    let cx = frame.intrinsics[2][0], cy = frame.intrinsics[2][1]
    guard fx > 0, fy > 0 else { return unknown() }
    let stride = max(config.sampleStride, 1)
    let sliceCount = config.sliceCentresDegrees.count
    var groundHeights: [Float] = []
    // Lane points are collected first and classified after the ground level is known.
    var lanePoints: [(slice: Int, meters: Float, y: Float)] = []

    for v in Swift.stride(from: 0, to: frame.height, by: stride) {
      for u in Swift.stride(from: 0, to: frame.width, by: stride) {
        let i = v * frame.width + u
        if let confidence = frame.confidence, confidence[i] < 1 { continue }
        let depth = frame.depths[i]
        guard depth > config.minDepthMeters else { continue }

        // Pinhole: image u is camera +x (right), image v is camera -y (down),
        // depth is along camera -z. The intrinsics ARE the projection, so this
        // holds no matter how the sensor is oriented.
        let cameraPoint = SIMD3<Float>(
          (Float(u) - cx) * depth / fx,
          -(Float(v) - cy) * depth / fy,
          -depth)
        let world = transform * SIMD4<Float>(cameraPoint.x, cameraPoint.y, cameraPoint.z, 1)

        // Horizontal position relative to the camera, split along forward/right.
        let offset = SIMD2<Float>(world.x - cameraPosition.x, world.z - cameraPosition.z)
        let ahead = simd_dot(offset, forwardN)
        let sideways = simd_dot(offset, rightN)
        let horizontalMeters = simd_length(offset)

        // Below-camera points out to a few metres find the ground level.
        if world.y < cameraPosition.y - 0.3, horizontalMeters <= config.groundFitMaxMeters {
          groundHeights.append(world.y)
        }

        guard ahead > 0, horizontalMeters <= config.maxMeters else { continue }
        let azimuth = Double(atan2(sideways, ahead)) * 180 / .pi
        guard
          let slice = sliceIndex(
            azimuthDegrees: azimuth, centres: config.sliceCentresDegrees)
        else { continue }
        // The slice's own corridor: only points near its centre line count, so each
        // slice answers "if I walk this way".
        let offCentre =
          horizontalMeters * sin(
            Float(azimuth) * .pi / 180 - Float(config.sliceCentresDegrees[slice]) * .pi / 180)
        guard abs(offCentre) <= config.laneHalfWidthMeters else { continue }

        lanePoints.append((slice, horizontalMeters, world.y))
      }
    }

    guard
      let ground = groundReference(
        floorPoints: floorPoints, cameraPosition: cameraPosition,
        groundHeights: groundHeights, config: config)
    else { return unknown() }

    var validPerSlice = [Int](repeating: 0, count: sliceCount)
    var obstacleMeters = [Float?](repeating: nil, count: sliceCount)
    var obstacleTop = [Float](repeating: 0, count: sliceCount)
    var dropMeters = [Float?](repeating: nil, count: sliceCount)
    var dropCounts = [Int](repeating: 0, count: sliceCount)

    for point in lanePoints {
      validPerSlice[point.slice] += 1
      if point.y > cameraPosition.y + config.maxObstacleAboveCameraMeters { continue }
      if point.y < ground - config.dropBelowGroundMeters {
        dropCounts[point.slice] += 1
        if dropMeters[point.slice] == nil || point.meters < dropMeters[point.slice]! {
          dropMeters[point.slice] = point.meters
        }
      } else if point.y > ground + config.obstacleAboveGroundMeters {
        if obstacleMeters[point.slice] == nil || point.meters < obstacleMeters[point.slice]! {
          obstacleMeters[point.slice] = point.meters
        }
        if point.y > obstacleTop[point.slice] { obstacleTop[point.slice] = point.y }
      }
    }

    let slices: [FreeSpace.Slice] = config.sliceCentresDegrees.enumerated().map { i, centre in
      let status: FreeSpace.Status
      if let obstacle = obstacleMeters[i] {
        // A shallow rise is a step; anything taller is an obstacle in the way.
        status =
          obstacleTop[i] - ground <= config.stepUpMaxHeightMeters
          ? .stepUp(meters: Double(obstacle)) : .blocked(meters: Double(obstacle))
      } else if dropCounts[i] >= config.minDropPoints, let drop = dropMeters[i] {
        status = .drop(meters: Double(drop))
      } else if validPerSlice[i] >= config.minSlicePoints {
        status = .clear
      } else {
        status = .unknown
      }
      return FreeSpace.Slice(offsetDegrees: centre, status: status)
    }
    return FreeSpace(slices: slices)
  }

  /// The slice an azimuth belongs to, or nil outside the scanned span. Slices meet
  /// halfway between their centres.
  private static func sliceIndex(azimuthDegrees: Double, centres: [Double]) -> Int? {
    var best: (index: Int, gap: Double)?
    for (i, centre) in centres.enumerated() {
      let gap = abs(azimuthDegrees - centre)
      if gap < (best?.gap ?? .infinity) { best = (i, gap) }
    }
    guard let best, centres.count > 1 else { return best?.index }
    let span = abs(centres[1] - centres[0])
    return best.gap <= span / 2 + 7 ? best.index : nil
  }

  /// Ground level in world Y, or nil when neither source has enough points. The mesh's
  /// `.floor` faces win when there are enough near the camera; otherwise the median of
  /// the depth map's below-camera points, which lands on the same plane outdoors.
  private static func groundReference(
    floorPoints: [SIMD3<Float>], cameraPosition: SIMD3<Float>, groundHeights: [Float],
    config: Config
  ) -> Float? {
    let nearFloors = floorPoints.filter {
      simd_distance(SIMD2<Float>($0.x, $0.z), SIMD2<Float>(cameraPosition.x, cameraPosition.z))
        < config.groundFitMaxMeters
    }
    if nearFloors.count >= config.minFloorPoints {
      return median(nearFloors.map(\.y))
    }
    guard groundHeights.count >= config.minGroundPoints else { return nil }
    return median(groundHeights)
  }

  private static func median(_ values: [Float]) -> Float? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
  }
}

// MARK: - Monocular relative depth (phones without LiDAR)

nonisolated extension FreeSpaceAnalyzer {
  struct RelativeConfig: Sendable {
    /// Nominal horizontal field of view of the depth map's image, for slice mapping.
    var fieldOfViewDegrees: Double = 60
    /// Bottom fraction of the image treated as near ground, the disparity reference.
    var groundBandFraction: Float = 0.15
    /// A pixel counts as an obstacle when its disparity is this far above the ground
    /// reference (whichever is larger of the absolute and relative margins). Depth
    /// Anything's output is normalized inverse depth, so a fixed gap means "closer".
    var obstacleMargin: Float = 0.08
    var obstacleRelativeMargin: Float = 0.25
    /// A slice needs this many above-threshold pixels to be called blocked.
    var minObstaclePixels = 8
    /// And at least this many valid pixels overall to say anything at all.
    var minSlicePoints = 40
    var sampleStride = 2
    var sliceCentresDegrees: [Double] = [-28, -14, 0, 14, 28]
  }

  /// Relative scan. Larger disparity means closer, but with no scale there is no
  /// "how far" — blocked slices come back `meters: nil`, and drops can't be seen.
  static func analyze(_ frame: DisparityFrame, config: RelativeConfig = RelativeConfig())
    -> FreeSpace
  {
    let centres = config.sliceCentresDegrees
    func unknown() -> FreeSpace {
      FreeSpace(
        slices: centres.map { FreeSpace.Slice(offsetDegrees: $0, status: .unknown) })
    }
    let count = frame.width * frame.height
    guard count > 0, frame.values.count == count else { return unknown() }

    // The near-ground reference: median disparity of the bottom band across the whole
    // frame, so one slice's wall doesn't raise its own baseline.
    let bandStart = Int(Float(frame.height) * (1 - config.groundBandFraction))
    var band: [Float] = []
    for v in Swift.stride(from: bandStart, to: frame.height, by: config.sampleStride) {
      for u in Swift.stride(from: 0, to: frame.width, by: config.sampleStride) {
        band.append(frame.values[v * frame.width + u])
      }
    }
    guard let ground = median(band) else { return unknown() }
    let threshold = ground + max(config.obstacleMargin, ground * config.obstacleRelativeMargin)

    var valid = [Int](repeating: 0, count: centres.count)
    var obstacles = [Int](repeating: 0, count: centres.count)
    var bandHigh = [Int](repeating: 0, count: centres.count)
    var bandCounts = [Int](repeating: 0, count: centres.count)

    for v in Swift.stride(from: 0, to: frame.height, by: config.sampleStride) {
      let inBand = v >= bandStart
      for u in Swift.stride(from: 0, to: frame.width, by: config.sampleStride) {
        let x = (Double(u) + 0.5) / Double(frame.width)
        let azimuth = (x - 0.5) * config.fieldOfViewDegrees
        guard let slice = sliceIndex(azimuthDegrees: azimuth, centres: centres) else {
          continue
        }
        let value = frame.values[v * frame.width + u]
        valid[slice] += 1
        if inBand {
          bandCounts[slice] += 1
          if value > threshold { bandHigh[slice] += 1 }
        } else if value > threshold {
          obstacles[slice] += 1
        }
      }
    }

    let slices: [FreeSpace.Slice] = centres.enumerated().map { i, centre in
      let status: FreeSpace.Status
      // Most of this slice's near-ground band is closer than ground: a wall fills
      // the view. Otherwise, a run of closer-than-ground pixels above the band.
      if bandCounts[i] > 0, Float(bandHigh[i]) > Float(bandCounts[i]) * 0.5 {
        status = .blocked(meters: nil)
      } else if obstacles[i] >= config.minObstaclePixels {
        status = .blocked(meters: nil)
      } else if valid[i] >= config.minSlicePoints {
        status = .clear
      } else {
        status = .unknown
      }
      return FreeSpace.Slice(offsetDegrees: centre, status: status)
    }
    return FreeSpace(slices: slices)
  }
}

// MARK: - ARKit plumbing

nonisolated extension DepthFrame {
  /// Copies the depth (and confidence) maps out of a frame's `sceneDepth` before the
  /// ARFrame is released. Camera intrinsics are scaled from the photo resolution down
  /// to the depth map's, and the camera transform is captured at the same instant.
  init?(depthData: ARDepthData, camera: ARCamera) {
    let depthMap = depthData.depthMap
    guard CVPixelBufferGetPixelFormatType(depthMap) == kCVPixelFormatType_DepthFloat32 else {
      return nil
    }
    CVPixelBufferLockBaseAddress(depthMap, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

    let width = CVPixelBufferGetWidth(depthMap)
    let height = CVPixelBufferGetHeight(depthMap)
    guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

    var depths = [Float](repeating: 0, count: width * height)
    depths.withUnsafeMutableBufferPointer { destination in
      for row in 0..<height {
        destination.baseAddress!.advanced(by: row * width).update(
          from: base.advanced(by: row * bytesPerRow).assumingMemoryBound(to: Float.self),
          count: width)
      }
    }

    var confidence: [UInt8]?
    if let confidenceMap = depthData.confidenceMap {
      CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
      if let confBase = CVPixelBufferGetBaseAddress(confidenceMap),
        CVPixelBufferGetWidth(confidenceMap) == width,
        CVPixelBufferGetHeight(confidenceMap) == height
      {
        let confBytesPerRow = CVPixelBufferGetBytesPerRow(confidenceMap)
        var values = [UInt8](repeating: 0, count: width * height)
        values.withUnsafeMutableBufferPointer { destination in
          for row in 0..<height {
            destination.baseAddress!.advanced(by: row * width).update(
              from: confBase.advanced(by: row * confBytesPerRow).assumingMemoryBound(
                to: UInt8.self),
              count: width)
          }
        }
        confidence = values
      }
      CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
    }

    // Intrinsics are given for the full-resolution photo; the depth map is smaller.
    let photo = camera.imageResolution
    var intrinsics = camera.intrinsics
    intrinsics[0][0] *= Float(width) / Float(photo.width)
    intrinsics[2][0] *= Float(width) / Float(photo.width)
    intrinsics[1][1] *= Float(height) / Float(photo.height)
    intrinsics[2][1] *= Float(height) / Float(photo.height)

    self.init(
      depths: depths, width: width, height: height, intrinsics: intrinsics,
      cameraTransform: camera.transform, confidence: confidence)
  }
}
