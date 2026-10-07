//  CameraView.swift
//  nemo-software
//
//  Main camera screen. Placeholder UI: replace with a real preview and spoken/haptic
//  feedback controls as implementation progresses.
//

import SwiftUI

struct CameraView: View {
  /// Created and owned by ContentView (@StateObject there), so this view only observes it.
  @ObservedObject var viewModel: CameraViewModel

  var body: some View {
    ZStack {
      // TODO: Add a live camera preview.
      // Options:
      //   - Use AVFoundation's AVCaptureVideoPreviewLayer via UIViewRepresentable.
      //   - Or render the pipeline's `presentation` pixel buffer as a UIImage.
      Color.black
        .ignoresSafeArea()

      VStack {
        Spacer()

        StatusOverlayView(presentation: viewModel.presentation)
          .padding()

        Button(viewModel.isRunning ? "Stop" : "Start") {
          if viewModel.isRunning {
            viewModel.stop()
          } else {
            viewModel.start()
          }
        }
        .buttonStyle(.borderedProminent)
        .padding(.bottom)
      }
    }
    .onAppear {
      viewModel.setup()
    }
    .onDisappear {
      viewModel.stop()
    }
  }
}

#Preview {
  CameraView(
    viewModel: CameraViewModel(
      frameProvider: CameraFrameProvider(),
      pipeline: PerceptionPipeline(
        detector: VisionObjectDetector(),
        locationProvider: LocationService.shared,
        speaker: Speaker()
      )
    )
  )
}
