import SwiftUI

struct ContentView: View {
  @StateObject private var services = AppServices()
  @StateObject private var cameraViewModel = makeCameraViewModel()

  var body: some View {
    NavigationStack {
      List {
        Section {
          NavigationLink("Ride") {
            RideView(
              viewModel: RideViewModel(
                location: services.location, feedback: services.feedback,
                client: services.entranceClient, session: services.session))
          }
          .accessibilityHint("Load a destination, track the ride, and check the side of street.")

          NavigationLink("Walk") {
            GuidanceView(
              viewModel: GuidanceViewModel(
                session: services.session, location: services.location))
          }
          .accessibilityHint("The walk to the entrance: direction, distance and arrival.")

          NavigationLink("Heading") {
            HeadingView(
              viewModel: HeadingViewModel(
                location: services.location, feedback: services.feedback))
          }
          .accessibilityHint("Live compass heading and its accuracy.")
        } footer: {
          Text("Entrance data © OpenStreetMap contributors.")
        }

        Section {
          NavigationLink("Camera (debug)") {
            CameraView(viewModel: cameraViewModel)
          }
          .accessibilityHint("Developer view of the camera and detections.")
        } footer: {
          Text("The camera preview is for developers; riders are guided by sound.")
        }
      }
      .navigationTitle("Nemo")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
    }
    // A trip interrupted by a relaunch picks up where it left off (FE-10).
    .onAppear(perform: services.resumeInterruptedTripIfAny)
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
