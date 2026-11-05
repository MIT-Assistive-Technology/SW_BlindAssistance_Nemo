//  FreeSpaceAnalyzerTests.swift
//  nemo-softwareTests
//
//  The free-space scan on synthetic depth grids: flat ground, a wall in the lane,
//  and a step down. Each test builds the depth a real scene would produce — a pixel
//  gets whatever depth puts its world point where the scene wants it — so the
//  analyzer sees exactly what LiDAR would show it.
//
//  The test camera sits at the origin facing -z with identity transform, so world
//  space is camera space: a point's image row picks its depth through
//  `y = -(v - cy) * d / fy`, and its column picks its azimuth.
//

import simd
import XCTest

@testable import nemo_software

final class FreeSpaceAnalyzerTests: XCTestCase {

  private let width = 40
  private let height = 60
  private let cameraY: Float = 1.4
  private let groundY: Float = 0  // world y of the sidewalk surface

  /// Row-major depths for a scene. `surfaceAt(u,v)` returns the world-space height
  /// of whatever the pixel sees, or nil for "no return"; the depth that puts the
  /// pixel's ray on that height is filled in. The camera is `cameraY` above the
  /// ground, so a flat floor is rows v > cy at `groundY`.
  private func depthFrame(surfaceAt: (Int, Int) -> Float?) -> DepthFrame {
    let fx = Float(width / 2) / tan(35 * .pi / 180)
    let fy = fx
    let cx = Float(width) / 2, cy = Float(height) / 2
    var depths = [Float](repeating: 0, count: width * height)
    for v in 0..<height {
      for u in 0..<width {
        guard let surfaceY = surfaceAt(u, v) else { continue }
        // Solve world y = cameraY - (v - cy) * d / fy for d.
        let d = (cameraY - surfaceY) * fy / (Float(v) - cy)
        if v != Int(cy), d > 0 { depths[v * width + u] = d }
      }
    }
    var transform = matrix_identity_float4x4
    transform.columns.3 = SIMD4(0, cameraY, 0, 1)
    // simd_float3x3 takes column vectors; ARKit's layout puts cx, cy in column 2.
    return DepthFrame(
      depths: depths, width: width, height: height,
      intrinsics: simd_float3x3(
        SIMD3(fx, 0, 0), SIMD3(0, fy, 0), SIMD3(cx, cy, 1)),
      cameraTransform: transform)
  }

  /// A flat sidewalk, nothing on it.
  private var flatFrame: DepthFrame {
    depthFrame { _, v in v > self.height / 2 ? self.groundY : nil }
  }

  private func config() -> FreeSpaceAnalyzer.Config {
    var config = FreeSpaceAnalyzer.Config()
    config.sampleStride = 1
    config.minSlicePoints = 4
    return config
  }

  // MARK: Metric depth

  func testFlatGroundIsAllClear() {
    let freeSpace = FreeSpaceAnalyzer.analyze(flatFrame, config: config())
    for slice in freeSpace.slices {
      XCTAssertEqual(slice.status, .clear, "slice at \(slice.offsetDegrees)°")
    }
    XCTAssertEqual(freeSpace.clearSlices.count, freeSpace.slices.count)
  }

  func testAWallInTheLaneBlocksItsSlice() {
    // A wall 2 m ahead covering the columns around straight ahead, from the sky rows
    // down past the horizon.
    var depths = flatFrame.depths
    for v in 0..<45 {
      for u in 18...22 { depths[v * width + u] = 2.0 }
    }
    var wall = flatFrame
    wall.depths = depths

    let freeSpace = FreeSpaceAnalyzer.analyze(wall, config: config())
    let centre = freeSpace.slices.first { $0.offsetDegrees == 0 }
    XCTAssertNotNil(centre)
    guard case .blocked(let meters) = centre?.status else {
      return XCTFail("centre slice is \(centre?.status ?? .unknown)")
    }
    XCTAssertEqual(meters ?? 0, 2.0, accuracy: 0.4)

    let farLeft = freeSpace.slices.first { $0.offsetDegrees == -28 }
    XCTAssertNotEqual(farLeft?.status, .blocked(meters: 2.0))
  }

  func testAStepDownIsFlaggedAsADrop() {
    // Past 2 m the ground drops 0.4 m (a loading dock edge, a deep curb): rows
    // whose ray lands beyond 2 m report the lower level.
    var depths = flatFrame.depths
    let fx = Float(width / 2) / tan(35 * .pi / 180)
    let cy = Float(height) / 2
    for v in 0..<height {
      for u in 16...24 {
        // Recompute this pixel's depth as if it saw the lower surface.
        let d = (cameraY - Float(-0.4)) * fx / (Float(v) - cy)
        if v > Int(cy), d > 0, d <= 3.2 { depths[v * width + u] = d }
      }
    }
    var frame = flatFrame
    frame.depths = depths

    let freeSpace = FreeSpaceAnalyzer.analyze(frame, config: config())
    let centre = freeSpace.slices.first { $0.offsetDegrees == 0 }
    guard case .drop(let meters) = centre?.status else {
      return XCTFail("centre slice is \(centre?.status ?? .unknown)")
    }
    XCTAssertEqual(meters ?? 0, 2.0, accuracy: 1.0)
  }

  func testAnEmptyFrameIsUnknownNotClear() {
    let frame = DepthFrame(
      depths: [Float](repeating: 0, count: width * height), width: width, height: height,
      intrinsics: simd_float3x3(diagonal: SIMD3(1, 1, 1)),
      cameraTransform: matrix_identity_float4x4)
    let freeSpace = FreeSpaceAnalyzer.analyze(frame, config: config())
    for slice in freeSpace.slices {
      XCTAssertEqual(slice.status, .unknown)
    }
    XCTAssertTrue(freeSpace.clearSlices.isEmpty, "unknown must never look clear")
  }

  func testSliceContainingOffset() {
    let freeSpace = FreeSpaceAnalyzer.analyze(flatFrame, config: config())
    XCTAssertEqual(freeSpace.slice(containingOffsetDegrees: 2)?.offsetDegrees, 0)
    XCTAssertEqual(freeSpace.slice(containingOffsetDegrees: -18)?.offsetDegrees, -14)
    XCTAssertNil(freeSpace.slice(containingOffsetDegrees: 80))
  }

  // MARK: Relative depth

  func testMonocularSeesACloseWall() {
    // Ground reads low disparity, a near wall high: the centre columns jump.
    var values = [Float](repeating: 0.3, count: width * height)
    for v in 0..<height {
      for u in 18...22 { values[v * width + u] = 0.95 }
    }
    let frame = DisparityFrame(values: values, width: width, height: height)
    let freeSpace = FreeSpaceAnalyzer.analyze(frame, config: .init())
    let centre = freeSpace.slices.first { $0.offsetDegrees == 0 }
    guard case .blocked(let meters) = centre?.status else {
      return XCTFail("centre slice is \(centre?.status ?? .unknown)")
    }
    XCTAssertNil(meters, "monocular depth gives no metric distance")
    XCTAssertEqual(freeSpace.slices.first { $0.offsetDegrees == -28 }?.status, .clear)
  }

  func testMonocularFlatSceneIsClear() {
    let frame = DisparityFrame(
      values: [Float](repeating: 0.4, count: width * height), width: width, height: height)
    let freeSpace = FreeSpaceAnalyzer.analyze(frame, config: .init())
    XCTAssertFalse(freeSpace.slices.contains {
      if case .blocked = $0.status { return true }
      return false
    })
  }
}
