//  PerceptionPipelineTests.swift
//  nemo-softwareTests
//
//  What the camera is allowed to say. The raw sentence ("Number 77. Sign Main St.") and
//  the "I see" line are for the debug Camera screen. During a walk they must stay silent,
//  because riders only hear the reviewed phrases (SAFE-1).
//

import CoreVideo
import ImageIO
import XCTest

@testable import nemo_software

@MainActor
final class PerceptionPipelineTests: XCTestCase {

  private final class RecordingSpeaker: SpeechOutput {
    var spoken: [String] = []
    func speak(_ text: String) { spoken.append(text) }
    func stop() {}
  }

  private final class FakeDetector: ObjectDetector {
    let detections: [Detection]
    init(_ labels: [String]) {
      detections = labels.map {
        Detection(
          boundingBox: .zero, labels: [DetectionLabel(identifier: $0, confidence: 0.9)])
      }
    }
    func detect(
      _ pixelBuffer: CVPixelBuffer,
      filter: @escaping (Detection) -> Bool,
      orientation: CGImagePropertyOrientation
    ) -> [Detection] { detections.filter(filter) }
  }

  private final class FakeRecognizer: NumberRecognizer, @unchecked Sendable {
    let result: CameraTextRead
    init(_ result: CameraTextRead) { self.result = result }
    func read(
      _ pixelBuffer: CVPixelBuffer,
      orientation: CGImagePropertyOrientation,
      expectedBundleTexts: [String]
    ) -> CameraTextRead { result }
  }

  private final class FakeLocation: LocationProvider {
    var currentSnapshot = LocationSnapshot()
  }

  private let number77 = CameraTextRead(numbers: [
    RecognizedNumber(text: "77", value: "77", confidence: 0.9, boundingBox: .zero)
  ])

  private var speaker: RecordingSpeaker!
  private var location: FakeLocation!
  private let provider = SyntheticFrameProvider()

  override func setUp() async throws {
    try await super.setUp()
    speaker = RecordingSpeaker()
    location = FakeLocation()
  }

  private func pipeline(labels: [String] = [], read: CameraTextRead = CameraTextRead())
    -> PerceptionPipeline
  {
    PerceptionPipeline(
      detector: FakeDetector(labels),
      numberRecognizer: FakeRecognizer(read),
      locationProvider: location,
      speaker: speaker,
      // High enough that the rate cap never drops a test frame, which would hang `send`.
      maxFramesPerSecond: 1_000_000_000)
  }

  private func makeBuffer() throws -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault, 8, 8, kCVPixelFormatType_32BGRA, nil, &buffer)
    XCTAssertEqual(status, kCVReturnSuccess)
    return try XCTUnwrap(buffer)
  }

  /// Sends one frame and waits until the pipeline has finished with it. Speech and
  /// `onTextRead` both happen before `onPresentation`.
  private func send(frameTo pipeline: PerceptionPipeline) async throws {
    let done = expectation(description: "frame processed")
    pipeline.onPresentation = { _ in done.fulfill() }
    pipeline.processFrame(provider, buffer: try makeBuffer())
    await fulfillment(of: [done], timeout: 5)
  }

  func testTheCameraScreenSpeaksTheSentence() async throws {
    let pipeline = pipeline(read: number77)
    try await send(frameTo: pipeline)
    XCTAssertEqual(speaker.spoken, ["Number 77."])
  }

  func testTheCameraScreenSaysWhatItSeesWhenThereIsNoText() async throws {
    let pipeline = pipeline(labels: ["person"])
    try await send(frameTo: pipeline)
    XCTAssertEqual(speaker.spoken, ["I see: person"])
  }

  func testTheSeenLineIsNotRepeatedOnEveryFrame() async throws {
    let pipeline = pipeline(labels: ["person"])
    try await send(frameTo: pipeline)
    try await send(frameTo: pipeline)
    try await send(frameTo: pipeline)
    XCTAssertEqual(speaker.spoken, ["I see: person"])
  }

  func testNothingRawIsSpokenDuringAWalk() async throws {
    let pipeline = pipeline(labels: ["person"], read: number77)
    pipeline.announcesReads = false
    try await send(frameTo: pipeline)
    XCTAssertEqual(speaker.spoken, [])

    let seenOnly = self.pipeline(labels: ["person"])
    seenOnly.announcesReads = false
    try await send(frameTo: seenOnly)
    XCTAssertEqual(speaker.spoken, [])
  }

  func testTextReadsStillReachNavigationDuringAWalk() async throws {
    let pipeline = pipeline(read: number77)
    pipeline.announcesReads = false
    var reads: [CameraTextRead] = []
    pipeline.onTextRead = { reads.append($0) }
    try await send(frameTo: pipeline)
    XCTAssertEqual(reads.first?.numbers.first?.value, "77")
  }
}
