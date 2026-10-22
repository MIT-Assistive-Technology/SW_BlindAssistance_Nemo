//  SessionView.swift
//  nemo-software
//
//  The active trip. VoiceOver-first and deliberately small (at most 4 elements):
//    1. what the app last said
//    2. one full-screen button: "Start guidance" before walking, then "Where am I. Repeat"
//    3. "I'm in the car" (only before the ride ends)
//    4. Stop
//  Magic tap (two-finger double-tap) pauses and resumes. No time limits, no long presses,
//  no swipe-only controls.
//

import SwiftUI

struct SessionView: View {
  @ObservedObject var model: AppModel
  @ObservedObject var session: NavigationSession

  var body: some View {
    VStack(spacing: 16) {
      Text(statusText)
        .font(.title2.weight(.semibold))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(statusText)
        .accessibilityAddTraits(.updatesFrequently)

      Button {
        model.primaryAction()
      } label: {
        Text(model.primaryActionTitle)
          .font(.largeTitle.weight(.bold))
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .accessibilityHint(primaryHint)

      if session.state == .setup, !model.isInCar {
        Button {
          model.imInTheCar()
        } label: {
          Text("I'm in the car")
            .font(.title2.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.bordered)
        .accessibilityHint(
          "Tap once your ride starts. Location stays on during the ride to work out which side of the street you're dropped on."
        )
      }

      Button(role: .destructive) {
        model.stopTrip()
      } label: {
        Text("Stop")
          .font(.title2.weight(.semibold))
          .frame(maxWidth: .infinity, minHeight: 64)
      }
      .buttonStyle(.bordered)
      .accessibilityLabel("Stop guiding")
      .accessibilityHint("Ends this trip.")
    }
    .padding()
    .navigationTitle("Guidance")
    .navigationBarTitleDisplayMode(.inline)
    .accessibilityAction(.magicTap) { model.togglePause() }
  }

  private var statusText: String {
    if session.isPaused { return "Paused. Two-finger double-tap to resume." }
    if !model.status.isEmpty { return model.status }
    switch session.state {
    case .setup:
      return model.isInCar ? "Riding. I'll tell you when to get out." : "Entrance loaded."
    case .arrived:
      return "Trip finished."
    default:
      return "Guidance on."
    }
  }

  private var primaryHint: String {
    switch session.state {
    case .setup, .arrival:
      return "Starts guidance once you're out of the car. Two-finger double-tap pauses."
    default:
      return "Says where the entrance should be from here. Two-finger double-tap pauses."
    }
  }
}
