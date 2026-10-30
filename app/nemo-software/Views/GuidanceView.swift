//  GuidanceView.swift
//  nemo-software
//
//  The active session screen (FE-10). Plan section 11: seven elements or fewer, a big
//  "where am I / repeat" control and a Stop button. The rider is guided by sound; this
//  screen is for the few taps they need and for sighted testers watching the state.
//

import SwiftUI

struct GuidanceView: View {
  // Owned here, built once: a NavigationLink destination is rebuilt on every parent
  // redraw, and a fresh view model each time would drop state and double-subscribe.
  @StateObject private var viewModel: GuidanceViewModel

  init(viewModel: @autoclosure @escaping () -> GuidanceViewModel) {
    _viewModel = StateObject(wrappedValue: viewModel())
  }

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 6) {
          Text(viewModel.stateText)
            .font(.system(.title2, design: .rounded, weight: .semibold))
          Text(viewModel.detailText)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Guidance")
        .accessibilityValue("\(viewModel.stateText). \(viewModel.detailText)")
        .accessibilityAddTraits(.updatesFrequently)
      }

      Section {
        // The one control a walking rider needs, so it's the biggest thing here.
        Button("Where am I", action: viewModel.repeatGuidance)
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .frame(maxWidth: .infinity)
          .accessibilityHint("Says the direction and distance again.")

        if viewModel.isWaitingToCross && !viewModel.isGuiding {
          Button("I'm across the street", action: viewModel.riderIsAcross)
            .buttonStyle(.borderedProminent)
            .accessibilityHint(
              "Tap once you're across. Guidance then starts. The app never tells you when it's safe to cross."
            )
        }

        if viewModel.isGuiding {
          Button("Stop guiding", role: .destructive, action: viewModel.stop)
            .accessibilityHint("Ends the trip.")
        } else {
          Button("Start guiding", action: viewModel.start)
            .accessibilityHint("Starts the walk to the entrance.")
        }
      } footer: {
        if !viewModel.canStartGuidance && !viewModel.isGuiding {
          Text(
            "Guidance starts once a destination is loaded and you've told me which side of the street you're on. If your entrance is across the road, it waits until you say you're across."
          )
        }
      }
    }
    .navigationTitle("Walk")
    .onAppear(perform: viewModel.onAppear)
    .onDisappear(perform: viewModel.onDisappear)
  }
}

#Preview {
  let services = AppServices()
  NavigationStack {
    GuidanceView(
      viewModel: GuidanceViewModel(session: services.session, location: services.location))
  }
}
