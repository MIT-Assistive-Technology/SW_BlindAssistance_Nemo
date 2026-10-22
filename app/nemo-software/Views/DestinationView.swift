//  DestinationView.swift
//  nemo-software
//
//  Choose where to go: saved places first, then an address field (type, dictate, braille
//  or paste from the ride app), then the pilot buildings saved on the phone.
//

import SwiftUI
import UIKit

struct DestinationView: View {
  @ObservedObject var model: AppModel
  @State private var address = ""
  @State private var saveIt = false
  @FocusState private var fieldFocused: Bool

  var body: some View {
    List {
      if !model.savedPlaces.isEmpty {
        Section("Saved places") {
          ForEach(model.savedPlaces) { place in
            Button {
              Task { await model.startTrip(address: place.address, name: place.name) }
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(place.name).font(.headline)
                if place.name != place.address {
                  Text(place.address).font(.subheadline).foregroundStyle(.secondary)
                }
              }
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Loads the entrance and starts a trip.")
            .accessibilityAction(named: "Delete") { model.deletePlace(place) }
          }
          .onDelete { offsets in
            offsets.map { model.savedPlaces[$0] }.forEach { model.deletePlace($0) }
          }
        }
      }

      Section("Address") {
        TextField("Destination address", text: $address)
          .textContentType(.fullStreetAddress)
          .textInputAutocapitalization(.words)
          .submitLabel(.go)
          .focused($fieldFocused)
          .onSubmit(search)
          .accessibilityHint("Type, dictate or paste the address, then press Go.")
        Toggle("Save as a place", isOn: $saveIt)
        Button(action: search) {
          Text(model.isBusy ? "Looking up" : "Find entrance")
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || model.isBusy)
        if let notice = model.notice {
          Text(notice)
            .accessibilityAddTraits(.updatesFrequently)
        }
      }

      if !model.pilotEntries.isEmpty {
        Section("Pilot buildings on this phone") {
          ForEach(model.pilotEntries) { entry in
            Button {
              model.startTrip(entry: entry)
            } label: {
              Text(entry.address ?? entry.id)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .accessibilityHint("Loads the entrance and starts a trip.")
          }
        }
      }
    }
    .navigationTitle("Where to?")
    .toolbar {
      NavigationLink {
        SettingsView(model: model)
      } label: {
        Label("Settings", systemImage: "gear")
      }
    }
  }

  private func search() {
    let query = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return }
    fieldFocused = false
    let save = saveIt
    Task {
      if await model.startTrip(address: query), save {
        model.savePlace(name: query, address: query)
      }
    }
  }
}
