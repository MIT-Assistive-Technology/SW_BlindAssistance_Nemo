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
  let frameProvider: any FrameProvider = CameraFrameProvider()
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
