import SwiftUI

/// One rider screen for the whole trip (`TripView`). The old Ride, Walk, Heading and
/// Camera screens, and the beacon and buzz tests, are under its Developer button.
struct ContentView: View {
  @StateObject private var services: AppServices
  @StateObject private var trip: TripViewModel

  init() {
    let services = AppServices()
    _services = StateObject(wrappedValue: services)
    _trip = StateObject(wrappedValue: TripViewModel(services: services))
  }

  var body: some View {
    NavigationStack {
      TripView(viewModel: trip, services: services)
    }
    // Look for a trip interrupted by a relaunch, but let the rider choose (FE-10).
    // Nothing is spoken at launch.
    .onAppear(perform: services.checkForUnfinishedTrip)
  }
}

// TEMPORARY (FE-4 ear test): press Beacon test on a real device with headphones — you
// should hear the tick coming from ~45° to your right.
private let testBeacon = BeaconChannel()
func beaconTest() {
  testBeacon.updateTarget(relativeAngleDegrees: 45)  // aim 45° right
  testBeacon.play(.doorDetected(offsetDegrees: 45, meters: 5))  // start tone
}

private let testHaptics = HapticsChannel()
func hapticTest() {
  testHaptics.play(.warning("test"))
}

#Preview {
  ContentView()
}
