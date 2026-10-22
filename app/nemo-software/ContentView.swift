import SwiftUI

/// Root screen: the active trip if there is one, otherwise the destination picker.
/// The wiring between sensors, session and feedback lives in `AppModel` (the composition
/// root), shared with the App Intents.
struct ContentView: View {
  @StateObject private var model = AppModel.shared

  var body: some View {
    NavigationStack {
      if let session = model.session {
        SessionView(model: model, session: session)
      } else {
        DestinationView(model: model)
      }
    }
  }
}

// Kept identical to main's version so the camera-stream branch merges cleanly. The live
// camera debug screen is built by AppModel.cameraDebug.

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
