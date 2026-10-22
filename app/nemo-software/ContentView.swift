import SwiftUI

/// Root screen: the active trip if there is one, otherwise the destination picker.
/// The wiring between sensors, session and feedback lives in `AppModel` (the composition
/// root), shared with the App Intents.
struct ContentView: View {
  @StateObject private var model = AppModel.shared

  var body: some View {
    NavigationStack {
      if let session = model.session {
        SessionView(model: model, session: session)
      } else {
        DestinationView(model: model)
      }
    }
  }
}

#Preview {
  ContentView()
}
