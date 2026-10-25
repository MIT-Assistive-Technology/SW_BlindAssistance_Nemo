//  StatusOverlayView.swift
//  nemo-software
//
//  Displays the camera status, frame flow, current detections and device location.
//

import CoreLocation
import SwiftUI

struct StatusOverlayView: View {
  let status: CameraStatus
  let presentation: FramePresentation?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if status == .ready, let numbers = presentation?.numbers, !numbers.isEmpty {
        Text(numbers.map(\.value).joined(separator: ", "))
          .font(.largeTitle.weight(.bold))
          .foregroundStyle(.white)
          .accessibilityLabel("Numbers \(numbers.map(\.value).joined(separator: ", "))")
      } else {
        Text(headline)
          .font(.headline)
          .foregroundStyle(.white)
      }

      if let stats = presentation?.stats {
        Text(
          "Frames: \(stats.processed) processed, \(stats.dropped) dropped, \(String(format: "%.1f", stats.processedPerSecond))/s"
        )
        .font(.caption)
        .foregroundStyle(.white.opacity(0.8))

        Text(
          "\(stats.frameWidth)×\(stats.frameHeight), detector \(String(format: "%.0f", stats.lastProcessingMs)) ms"
        )
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.6))
      }

      Text("Detections: \(presentation?.detections.count ?? 0)")
        .font(.caption)
        .foregroundStyle(.white.opacity(0.8))

      if let coordinate = presentation?.location?.coordinate {
        Text(
          "GPS: \(String(format: "%.5f", coordinate.latitude)), \(String(format: "%.5f", coordinate.longitude))"
        )
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.6))
      }
    }
    .padding()
    .background(.ultraThinMaterial)
    .cornerRadius(12)
    .accessibilityElement(children: .combine)
  }

  private var headline: String {
    switch status {
    case .notSetUp, .settingUp:
      return "Setting up the camera"
    case .unavailable(.noCamera):
      return "No camera on this device"
    case .unavailable(.permissionDenied):
      return "Camera access is off. Turn it on in Settings, Privacy, Camera."
    case .unavailable(.configurationFailed(let reason)):
      return "Camera unavailable: \(reason)"
    case .ready:
      if let detections = presentation?.detections, !detections.isEmpty {
        return "I see: \(detections.map { $0.labels.first?.identifier ?? "something" }.joined(separator: ", "))"
      }
      return "Tap Start and point the camera at a building number"
    }
  }
}
