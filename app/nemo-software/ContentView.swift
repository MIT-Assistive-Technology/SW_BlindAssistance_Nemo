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
        .toolbar {
          // TEMPORARY (FE-4 ear test): fires a beacon tone at a fixed angle.
          ToolbarItem(placement: .topBarTrailing) {
            Button("Beacon") { beaconTest() }
              .accessibilityHint("Developer test: plays the beacon tone 45 degrees to your right.")
          }
          ToolbarItem(placement: .topBarTrailing) {
            Button("Buzz") { hapticTest() }
              .accessibilityHint("Developer test: plays the warning haptic.")
          }
        }
      #endif
    }
    // A trip interrupted by a relaunch picks up where it left off (FE-10).
    .onAppear(perform: services.resumeInterruptedTripIfAny)
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

// TEMPORARY (FE-4 ear test): press the Beacon button on a real device with
// headphones — you should hear the tick coming from ~45° to your right.
private let testBeacon = BeaconChannel()
private func beaconTest() {
  testBeacon.updateTarget(relativeAngleDegrees: 45)  // aim 45° right
  testBeacon.play(.doorDetected(offsetDegrees: 45, meters: 5))  // start tone
}

private let testHaptics = HapticsChannel()
private func hapticTest() {
  testHaptics.play(.warning("test"))
}

#Preview {
  ContentView()
}
