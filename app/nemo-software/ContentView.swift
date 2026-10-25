import SwiftUI

struct ContentView: View {
  @StateObject private var viewModel = makeCameraViewModel()

  var body: some View {
    NavigationStack {
      CameraView(viewModel: viewModel)
        .navigationTitle("Nemo")
        #if os(iOS)
          .navigationBarTitleDisplayMode(.inline)
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
    numberRecognizer: VisionNumberRecognizer(),
    locationProvider: LocationService.shared,
    speaker: Speaker()
  )
  return CameraViewModel(frameProvider: frameProvider, pipeline: pipeline)
}

#Preview {
  ContentView()
}
