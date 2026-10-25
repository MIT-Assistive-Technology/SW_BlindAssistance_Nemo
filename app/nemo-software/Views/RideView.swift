//  RideView.swift
//  nemo-software
//
//  FE-11 + FE-13: load the destination bundle, track the ride, and say which side of
//  the street the entrance is on when the rider is out of the car.
//
//  Built for someone who can't see it:
//    - Every action says something out loud; nothing important is screen-only.
//    - "I'm out of the car" is always in the same place during a ride, so it can be
//      found by swiping without reading.
//    - "Repeat" exists for every announcement, because traffic drowns things out.
//    - No fixed font sizes, so Dynamic Type up to AX5 works.
//

import SwiftUI

struct RideView: View {
  @ObservedObject var viewModel: RideViewModel

  var body: some View {
    List {
      Section("Destination") {
        TextField("Address", text: $viewModel.address)
          .textInputAutocapitalization(.words)
          .autocorrectionDisabled()
          .accessibilityLabel("Destination address")
          .accessibilityHint("Type, dictate or paste the address from your ride app.")
        // Riders usually have the address in the Uber app, not in their head.
        PasteButton(payloadType: String.self) { strings in
          guard let pasted = strings.first else { return }
          viewModel.address = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .accessibilityLabel("Paste address")
        Button(viewModel.isLoading ? "Loading…" : "Load entrance details") {
          Task { await viewModel.load() }
        }
        .disabled(viewModel.isLoading)
        .accessibilityHint("Fetches the entrance bundle and saves it on this phone.")
        Text(viewModel.status)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .accessibilityLabel("Status")
          .accessibilityValue(viewModel.status)
      }

      if let brief = viewModel.briefText {
        Section {
          Text(brief)
            .accessibilityLabel("What the map shows")
            .accessibilityValue(brief)
          Button("Repeat the brief") { viewModel.speakBrief(force: true) }
            .accessibilityHint("Says it again.")
        } header: {
          Text("Brief")
        } footer: {
          if let note = viewModel.cacheNote {
            Text(note + " Guidance works from this copy with no signal.")
          }
        }
      }

      Section {
        Button(viewModel.isTrackingRide ? "Stop tracking" : "I'm in the car") {
          if viewModel.isTrackingRide {
            viewModel.stopRide()
          } else {
            viewModel.startRide()
          }
        }
        .accessibilityHint(
          "Records the car's direction of travel so the app can tell which side of the street you were dropped on."
        )

        // The rider's own signal. Always in the same spot for the whole ride, whether
        // or not the phone has noticed the stop.
        if viewModel.isTrackingRide && !viewModel.isOutOfCar {
          Button("I'm out of the car", action: viewModel.confirmOutOfCar)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .accessibilityHint(
              "Tap once you're on the ground. The app then says which side of the street your entrance is on."
            )
        }
        if viewModel.isAskingIfOutOfCar {
          Text(viewModel.dropOffPrompt)
            .font(.footnote)
            .accessibilityLabel("Question")
            .accessibilityValue(viewModel.dropOffPrompt)
          Button("Not yet, still in the car", action: viewModel.stillInCar)
            .accessibilityHint("Dismisses the question until the car stops again.")
        }

        Text(viewModel.trackSummary)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .accessibilityLabel("Ride tracking")
          .accessibilityValue(viewModel.trackSummaryAccessibility)
      } header: {
        Text("The ride")
      } footer: {
        Text(
          "Location keeps running during the ride, with iOS's blue indicator on. Permission stays \"while using the app\". A stop only prompts: you decide when you're out of the car."
        )
      }

      if let sideText = viewModel.sideText {
        Section {
          Text(sideText)
            .accessibilityLabel("Side of street")
            .accessibilityValue(sideText)
          if viewModel.needsSideAnswerFromRider {
            Button("Yes, the building side is to my right") {
              viewModel.answerSideQuestion(sameSide: true)
            }
            Button("No, the building is across the street") {
              viewModel.answerSideQuestion(sameSide: false)
            }
          }
          Button("Repeat", action: viewModel.repeatSideAnswer)
            .accessibilityHint("Says the side of the street again.")
        } header: {
          Text("Side of street")
        } footer: {
          if let reason = viewModel.sideReason {
            Text("Not decided, for testing: \(reason).")
          }
        }
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
    .navigationTitle("Ride")
    .onAppear(perform: viewModel.onAppear)
    .onDisappear(perform: viewModel.onDisappear)
  }
}

#Preview {
  let services = AppServices()
  NavigationStack {
    RideView(
      viewModel: RideViewModel(
        location: services.location, feedback: services.feedback,
        client: services.entranceClient))
  }
}
