//  TripView.swift
//  nemo-software
//
//  The one rider screen, from the address to the door (plan section 11, screen 4). In
//  VoiceOver order:
//    1. What's happening now (headline and detail, read together)
//    2. The next-step button, always in the same place, whose label says what it does
//    3. "Where am I", the biggest thing on screen, for any stage
//    4. End trip
//  The address field only shows before a ride. Developer tools are behind a toolbar
//  button so swiping never lands on them mid-trip.
//

import SwiftUI

struct TripView: View {
  @ObservedObject var viewModel: TripViewModel
  let services: AppServices
  @State private var showingDeveloper = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        status

        if viewModel.unfinishedTrip != nil {
          unfinishedTrip
        } else {
          if viewModel.state == .setup { destination }
          nextStep
        }

        Button(action: viewModel.whereAmI) {
          Text("Where am I")
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: 220)
        }
        .buttonStyle(.borderedProminent)
        .tint(.indigo)
        .accessibilityHint("Says where you are in the trip, and the direction and distance to the door.")

        if viewModel.isTripActive && viewModel.unfinishedTrip == nil && viewModel.state != .setup {
          Button("End trip", role: .destructive, action: viewModel.endTrip)
            .frame(maxWidth: .infinity)
            .accessibilityHint("Stops guidance and ends this trip.")
        }

        Text("Entrance data © OpenStreetMap contributors.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      .padding()
    }
    .navigationTitle("Nemo")
    #if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Developer") { showingDeveloper = true }
            .accessibilityHint("Testing tools: debug readout, old screens, camera, beacon and buzz tests.")
        }
      }
    #endif
    .sheet(isPresented: $showingDeveloper) {
      NavigationStack {
        DeveloperView(services: services, guidance: viewModel.guidance)
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { showingDeveloper = false }
            }
          }
      }
    }
  }

  private var status: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(viewModel.headline)
        .font(.system(.title, design: .rounded, weight: .semibold))
      Text(viewModel.detail)
        .font(.body)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(viewModel.headline)
    .accessibilityValue(viewModel.detail)
    .accessibilityAddTraits([.isHeader, .updatesFrequently])
  }

  private var destination: some View {
    VStack(alignment: .leading, spacing: 10) {
      TextField("Address", text: $viewModel.address)
        .textFieldStyle(.roundedBorder)
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .accessibilityLabel("Destination address")
        .accessibilityHint("Type, dictate or paste the address from your ride app.")
      HStack {
        // Riders usually have the address in the Uber app, not in their head.
        PasteButton(payloadType: String.self) { strings in
          guard let pasted = strings.first else { return }
          viewModel.address = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .accessibilityLabel("Paste address")
        // Once a destination is loaded, the next step is the ride; loading another
        // address stays available here.
        if viewModel.hasDestination {
          Button("Load a different address") { Task { await viewModel.ride.load() } }
            .disabled(viewModel.ride.isLoading)
        }
      }
    }
  }

  @ViewBuilder
  private var nextStep: some View {
    if viewModel.nextStep != nil {
      Button(action: viewModel.performNextStep) {
        Text(viewModel.nextStepTitle)
          .font(.title2.weight(.semibold))
          .frame(maxWidth: .infinity, minHeight: 64)
      }
      .buttonStyle(.borderedProminent)
      .disabled(viewModel.nextStep == .loadDestination && viewModel.ride.isLoading)
      .accessibilityHint(viewModel.nextStepHint)
    }
    if viewModel.state == .riding && viewModel.ride.isAskingIfOutOfCar {
      Button("Not yet, still in the car", action: viewModel.stillInCar)
        .frame(maxWidth: .infinity)
        .accessibilityHint("Dismisses the question until the car stops again.")
    }
  }

  private var unfinishedTrip: some View {
    VStack(spacing: 12) {
      Button(action: viewModel.resumeTrip) {
        Text("Resume trip")
          .font(.title2.weight(.semibold))
          .frame(maxWidth: .infinity, minHeight: 64)
      }
      .buttonStyle(.borderedProminent)
      .accessibilityHint("Picks up the trip where it left off.")
      Button("End trip", role: .destructive, action: viewModel.endTrip)
        .frame(maxWidth: .infinity)
        .accessibilityHint("Forgets this trip.")
    }
  }
}

/// Testing tools, kept off the rider's screen. The old Ride, Walk and Heading screens
/// stay here so their debug readouts are still one tap away.
struct DeveloperView: View {
  let services: AppServices
  @ObservedObject var guidance: GuidanceViewModel
  @ObservedObject private var session: NavigationSession

  init(services: AppServices, guidance: GuidanceViewModel) {
    self.services = services
    self.guidance = guidance
    session = services.session
  }

  var body: some View {
    List {
      Section("Debug") {
        row("Stage", "\(guidance.state.rawValue): \(guidance.stateText)")
        row("GPS accuracy", guidance.debugGPS)
        row("Heading", guidance.debugHeading)
        row("Bearing to door", guidance.debugBearing)
        row("Turn needed", guidance.offsetDegrees.map { "\(Int($0))°" } ?? "–")
        row("Distance", guidance.metersToDoor.map { "\(Int($0)) m" } ?? "–")
        row("Side of street", guidance.debugSide)
        row("Last lost because", guidance.debugLostReason)
        row("Door finder", AppServices.canDetectDoors ? "LiDAR doors + text" : "text only")
        row("Last door sighting", doorSighting)
        row("Last said", guidance.debugLastSaid)
      }

      Section {
        NavigationLink("Ride (old screen)") {
          RideView(
            viewModel: RideViewModel(
              location: services.location, feedback: services.feedback,
              client: services.entranceClient, session: services.session))
        }
        NavigationLink("Walk (old screen)") {
          GuidanceView(
            viewModel: GuidanceViewModel(
              session: services.session, location: services.location,
              feedback: services.feedback))
        }
        NavigationLink("Heading") {
          HeadingView(
            viewModel: HeadingViewModel(location: services.location, feedback: services.feedback))
        }
        NavigationLink("Camera") {
          CameraView(viewModel: services.camera)
        }
      } header: {
        Text("Screens")
      } footer: {
        Text("The old screens share the same trip, so they can be used to inspect it.")
      }

      Section("Sound and vibration") {
        // TEMPORARY (FE-4 ear test): fires a beacon tone at a fixed angle.
        Button("Beacon test") { beaconTest() }
          .accessibilityHint("Plays the beacon tone 45 degrees to your right.")
        // TEMPORARY (FE-5 feel test): plays the warning haptic pattern.
        Button("Buzz test") { hapticTest() }
          .accessibilityHint("Plays the warning vibration.")
      }

      Section {
        Button("End trip and reset", role: .destructive, action: services.resetAll)
          .accessibilityHint("Ends any trip and deletes saved entrance data, so the next one starts clean.")
      } footer: {
        Text("Use between tests.")
      }
    }
    .navigationTitle("Developer")
  }

  private var doorSighting: String {
    guard let sighting = session.lastDoorSighting else { return "–" }
    let age = Int(Date().timeIntervalSince(sighting.timestamp))
    let what: String
    switch sighting.kind {
    case .door: what = "LiDAR door"
    case .clue(let clue): what = Phrases.doorClueName(clue)
    }
    let meters = sighting.meters.map { String(format: ", %.1f m", $0) } ?? ""
    return "\(what), \(Int(sighting.offsetDegrees))°\(meters), \(age) s ago"
  }

  private func row(_ label: String, _ value: String) -> some View {
    LabeledContent(label) {
      Text(value).multilineTextAlignment(.trailing)
    }
    .font(.caption)
  }
}
