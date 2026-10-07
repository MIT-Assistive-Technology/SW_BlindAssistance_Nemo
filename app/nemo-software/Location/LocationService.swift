//  LocationService.swift
//  nemo-software
//
//  Owns CLLocationManager and CMHeading access. Publishes a stream of
//  `LocationSnapshot` values that the perception pipeline can attach to each frame.
//

import Combine
import CoreLocation
import Foundation

public protocol LocationProvider: AnyObject {
  /// The most recent snapshot, or nil if no location/heading has been received.
  var currentSnapshot: LocationSnapshot { get }
}

#if os(iOS)

  /// Live GPS + compass provider.
  public final class LocationService: NSObject, ObservableObject, LocationProvider,
    CLLocationManagerDelegate
  {
    public static let shared = LocationService()

    /// Published whenever a new location or heading arrives.
    @Published public private(set) var currentSnapshot: LocationSnapshot = LocationSnapshot()

    private let locationManager = CLLocationManager()

    private override init() {
      super.init()
      locationManager.delegate = self
    }

    /// Call once after the user grants permission.
    public func start() {
      // TODO: Request the correct authorization for your use case.
      //
      // The MVP uses When-In-Use only. To keep tracking the car during the ride (side of
      // street), start updates from an explicit "I'm in the car" action while the app is in
      // the foreground, with `allowsBackgroundLocationUpdates = true` or a
      // `CLBackgroundActivitySession` (iOS 17; add `CLServiceSession` on iOS 18). The
      // `location` background mode is already in app/Info.plist. iOS shows the blue location
      // indicator while this runs. Don't use geofences: they need Always permission.
      //
      locationManager.requestWhenInUseAuthorization()

      // TODO: Configure desired accuracy and start updates.
      // locationManager.desiredAccuracy = kCLLocationAccuracyBest
      // locationManager.startUpdatingLocation()
      // locationManager.startUpdatingHeading()
    }

    public func stop() {
      // TODO: Stop location and heading updates to save battery.
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManager(
      _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
      // TODO: Update `currentSnapshot.coordinate`, `horizontalAccuracy`, and `timestamp`.
      // Hint: `locations.last` is the newest sample.
    }

    public func locationManager(
      _ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading
    ) {
      // TODO: Update `currentSnapshot.heading`.
      // Use `trueHeading` (map north), not `magneticHeading`: OSM and the server's
      // bearings are true north. Ignore readings with `headingAccuracy < 0`, and prompt
      // calibration when accuracy is worse than 20° (FE-3).
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
      // TODO: Surface permission-denied / unavailable errors to the UI or pipeline.
    }
  }

#else

  /// Non-iOS stub.
  public final class LocationService: ObservableObject, LocationProvider {
    public static let shared = LocationService()
    public private(set) var currentSnapshot: LocationSnapshot = LocationSnapshot()
    public func start() {}
    public func stop() {}
  }

#endif
