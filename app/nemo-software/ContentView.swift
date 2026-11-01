import SwiftUI

struct ContentView: View {
  @StateObject private var viewModel = makeCameraViewModel()

  var body: some View {
    NavigationStack {
      CameraView(viewModel: viewModel)
        .navigationTitle("Nemo")
        #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {// TEMPORARY (FE-4 ear test): fires a beacon tone at a fixed angle.
              ToolbarItem(placement: .topBarTrailing) {
                  Button("Beacon") { beaconTest() }
              }
              ToolbarItem(placement: .topBarTrailing){
                  Button("Buzz") { hapticTest() }
              }
          }
        #endif
    }
  }
}

// MARK: - Composition root

private func makeCameraViewModel() -> CameraViewModel {
  // The Simulator has no camera, so it gets blank frames to exercise the pipeline.
  #if targetEnvironment(simulator)
    let frameProvider: any FrameProvider = SyntheticFrameProvider()
  #else
    let frameProvider: any FrameProvider = CameraFrameProvider()
  #endif
  let detector: ObjectDetector = VisionObjectDetector()
  let pipeline = PerceptionPipeline(
    detector: detector,
    locationProvider: LocationService.shared,
    speaker: Speaker()
  )
  return CameraViewModel(frameProvider: frameProvider, pipeline: pipeline)
}

#Preview {
  ContentView()
}

// TEMPORARY (FE-4 ear test): press the Beacon button on a real device with
// headphones — you should hear the tick coming from ~45° to your right.
private let testBeacon = BeaconChannel()
private func beaconTest() {
    testBeacon.updateTarget(relativeAngleDegrees: 45)   // aim 45° right
    testBeacon.play(.doorDetected(offsetDegrees: 45, meters: 5))  // start tone
}

private let testHaptics = HapticsChannel()
private func hapticTest() {
    testHaptics.play(.warning("test"))
}
