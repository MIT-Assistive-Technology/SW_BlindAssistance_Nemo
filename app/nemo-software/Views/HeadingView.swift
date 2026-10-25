//  HeadingView.swift
//  nemo-software
//
//  FE-3: live true heading, its accuracy, and a calibration prompt. The screen exists
//  to be checked against a known street bearing in the field, so it is deliberately
//  plain: large text, few elements, every control labelled for VoiceOver.
//

import SwiftUI

struct HeadingView: View {
  @ObservedObject var viewModel: HeadingViewModel

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 8) {
          // A text style, not a fixed point size, so Dynamic Type up to AX5 works for
          // riders with some remaining sight.
          Text(viewModel.headingText)
            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            .monospacedDigit()
          Text(viewModel.accuracyText)
            .font(.headline)
            .foregroundStyle(viewModel.needsCalibration ? .orange : .secondary)
        }
        .padding(.vertical, 4)
        // One element, one sentence: VoiceOver shouldn't read a number and a unit apart.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Heading")
        .accessibilityValue(viewModel.accessibilityText)
        .accessibilityAddTraits(.updatesFrequently)
      } header: {
        Text("True heading")
      } footer: {
        Text(
          "Degrees clockwise from true north, the same reference the map data uses. Compare it with a street's known bearing to check the compass."
        )
      }

      if viewModel.needsCalibration {
        Section {
          Button("Calibrate compass", action: viewModel.calibrate)
            .accessibilityHint(
              "Restarts compass updates. Move the phone in a figure eight, away from metal.")
        } footer: {
          Text(Phrases.compassCalibration)
        }
      }

      Section {
        Button("Speak heading", action: viewModel.speakNow)
          .accessibilityHint("Says the current heading out loud.")
        Toggle("Speak changes", isOn: $viewModel.speaksChanges)
          .accessibilityHint("Says the heading whenever it changes direction.")
      }

      if let problem = viewModel.problem {
        Section {
          Text(problem)
            .foregroundStyle(.orange)
            .accessibilityLabel("Problem")
            .accessibilityValue(problem)
        }
      }
    }
    .navigationTitle("Heading")
    .onAppear(perform: viewModel.onAppear)
    .onDisappear(perform: viewModel.onDisappear)
  }
}

#Preview {
  let services = AppServices()
  NavigationStack {
    HeadingView(
      viewModel: HeadingViewModel(location: services.location, feedback: services.feedback))
  }
}
