import SwiftUI

@main
struct NemoApp: App {
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .onChange(of: scenePhase) { _, phase in
      // Save the trip so a relaunch resumes it.
      if phase != .active { AppModel.shared.saveTrip() }
    }
  }
}
