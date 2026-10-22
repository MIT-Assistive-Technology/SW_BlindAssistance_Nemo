//  SettingsView.swift
//  nemo-software
//
//  The rider's FeedbackProfile (saved on the phone as it changes), the entrance service
//  address, saved-place cleanup, the debug camera screen and map attribution.
//

import SwiftUI
import UIKit

struct SettingsView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    Form {
      Section {
        ForEach(FeedbackProfile.presets, id: \.name) { preset in
          Button {
            model.profile = preset
          } label: {
            HStack {
              Text(preset.name)
              Spacer()
              if model.profile.name == preset.name {
                Image(systemName: "checkmark").accessibilityHidden(true)
              }
            }
            .frame(minHeight: 44)
          }
          .accessibilityAddTraits(model.profile.name == preset.name ? .isSelected : [])
          .accessibilityHint("Sets all feedback options at once.")
        }
      } header: {
        Text("Presets")
      }

      Section {
        Toggle("Voice", isOn: $model.profile.voiceOn)
        Toggle("Direction tone", isOn: $model.profile.beaconOn)
          .accessibilityHint("A tone that plays from the direction to walk. Works best with headphones.")
        Toggle("Vibration", isOn: $model.profile.hapticsOn)
        VStack(alignment: .leading) {
          Text("Tone volume")
          Slider(value: $model.profile.beaconVolume, in: 0...1)
            .accessibilityLabel("Tone volume")
        }
      } header: {
        Text("Feedback")
      } footer: {
        Text("Warnings and arrival always use at least two of these.")
      }

      Section {
        Picker("Speech detail", selection: $model.profile.verbosity) {
          Text("Short").tag(Verbosity.minimal)
          Text("Normal").tag(Verbosity.normal)
        }
        Picker("Units", selection: $model.profile.units) {
          Text("Feet").tag(Units.feet)
          Text("Meters").tag(Units.meters)
        }
        Picker("Phone position", selection: $model.profile.cameraFirst) {
          Text("Held or chest mount, camera on").tag(true)
          Text("In a pocket").tag(false)
        }
        .accessibilityHint("In a pocket, the camera and vibration stay off and the tone follows your walking direction.")
      } header: {
        Text("Guidance")
      }

      Section {
        TextField("Service address, for example https://example.org", text: $model.serverURL)
          .keyboardType(.URL)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .accessibilityLabel("Entrance service address")
          .accessibilityHint("Leave empty to use the built-in example building.")
        Button("Download pilot buildings") {
          Task { await model.refreshBundles() }
        }
        .disabled(model.isBusy)
        if let notice = model.notice {
          Text(notice).accessibilityAddTraits(.updatesFrequently)
        }
      } header: {
        Text("Map data")
      } footer: {
        Text("Only the destination address is sent. Your location and camera never leave the phone.")
      }

      Section {
        Button("Delete all saved places", role: .destructive) {
          model.deleteAllPlaces()
        }
        .disabled(model.savedPlaces.isEmpty)
      } header: {
        Text("Privacy")
      }

      Section {
        NavigationLink("Camera test screen") {
          CameraView(viewModel: model.cameraDebug)
            .navigationTitle("Camera test")
        }
        .accessibilityHint("For testing only. Shows what the door detector sees.")
      } header: {
        Text("Testing")
      }

      Section {
        Text("Map data © OpenStreetMap contributors, available under the Open Database License.")
        Link("openstreetmap.org/copyright", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
      } header: {
        Text("About")
      }
    }
    .navigationTitle("Settings")
  }
}
