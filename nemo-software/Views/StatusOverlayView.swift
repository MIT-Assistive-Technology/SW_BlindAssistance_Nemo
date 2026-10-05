//  StatusOverlayView.swift
//  nemo-software
//
//  Displays the current detections and device location.
//

import CoreLocation
import SwiftUI

struct StatusOverlayView: View {
  let presentation: FramePresentation?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let detections = presentation?.detections, !detections.isEmpty {
        Text(
          "I see: \(detections.map { $0.labels.first?.identifier ?? "something" }.joined(separator: ", "))"
        )
        .font(.headline)
        .foregroundStyle(.white)
      } else {
        Text("Tap Start and point the camera")
          .font(.headline)
          .foregroundStyle(.white)
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
  }
}
