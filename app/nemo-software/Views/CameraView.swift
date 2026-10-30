//  CameraView.swift
//  nemo-software
//
//  Main camera screen. This is a debug screen: it shows the live preview and frame
//  stats. Riders won't rely on it; their interface is sound, speech and vibration.
//

import AVFoundation
import SwiftUI

struct CameraView: View {
  /// Created and owned by ContentView (@StateObject there), so this view only observes it.
  @ObservedObject var viewModel: CameraViewModel

  var body: some View {
    ZStack {
      Color.black
        .ignoresSafeArea()

      #if os(iOS)
        if let session = viewModel.previewSession {
          CameraPreview(session: session)
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
      #endif

      VStack {
        Spacer()

        StatusOverlayView(status: viewModel.status, presentation: viewModel.presentation)
          .padding()

        Button(viewModel.isRunning ? "Stop" : "Start") {
          if viewModel.isRunning {
            viewModel.stop()
          } else {
            viewModel.start()
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.status != .ready)
        .accessibilityHint(viewModel.isRunning ? "Stops the camera" : "Starts the camera")
        .padding(.bottom)
      }
    }
    .task {
      await viewModel.setup()
    }
    .onDisappear {
      viewModel.stop()
    }
  }
}

#if os(iOS)

  /// Shows the capture session through an `AVCaptureVideoPreviewLayer`. The preview is
  /// drawn by AVFoundation directly, so it costs nothing on the perception queue.
  private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
      let view = PreviewView()
      view.previewLayer.session = session
      view.previewLayer.videoGravity = .resizeAspectFill
      return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
      override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
      var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
  }

#endif

#Preview {
  CameraView(
    viewModel: CameraViewModel(
      frameProvider: SyntheticFrameProvider(),
      pipeline: PerceptionPipeline(
        detector: VisionObjectDetector(),
        locationProvider: LocationService.shared
      )
    )
  )
}
