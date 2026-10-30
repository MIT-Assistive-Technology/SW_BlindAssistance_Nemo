//  LocationService.swift
//  nemo-software
//
//  Owns CLLocationManager and CMHeading access. Publishes a stream of
//  `LocationSnapshot` values that the perception pipeline can attach to each frame.
//
//  Two jobs:
//    - FE-3: live true heading and its accuracy for the heading readout screen.
//    - FE-13: record the car's course between "I'm in the car" and the drop-off, so the
//      side-of-street rule has something to work from.
//
//  Permission is When-In-Use only, asked at the moment of use. Never Always: geofences
//  would need it and the MVP doesn't use them.
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

    /// Latest usable compass reading, nil until one arrives (FE-3).
    @Published public private(set) var headingReadout: HeadingReadout?

    @Published public private(set) var authorizationStatus: CLAuthorizationStatus =
      .notDetermined

    /// True between `start()` and `stop()`.
    @Published public private(set) var isUpdating = false

    /// True between "I'm in the car" and the drop-off (FE-13).
    @Published public private(set) var isTrackingRide = false

    /// The car's recent courses. Only filled while `isTrackingRide`, because a side of
    /// street worked out from an untracked ride would be a guess.
    @Published public private(set) var carTrack = CarCourseTrack()

    /// Last CoreLocation failure, in words the UI can show and speak.
    @Published public private(set) var lastFailure: String?

    public var isHeadingAvailable: Bool { CLLocationManager.headingAvailable() }

    public var isAuthorized: Bool {
      authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    private let locationManager: CLLocationManager
    /// Keeps location running for the ride, with the blue indicator on (ADR 0013).
    private var rideSession: CLBackgroundActivitySession?

    public init(locationManager: CLLocationManager = CLLocationManager()) {
      self.locationManager = locationManager
      super.init()
      locationManager.delegate = self
      locationManager.desiredAccuracy = kCLLocationAccuracyBest
      locationManager.headingFilter = 2
      locationManager.headingOrientation = .portrait
      authorizationStatus = locationManager.authorizationStatus
    }

    /// Start GPS and compass updates, asking for permission the first time.
    public func start() {
      if authorizationStatus == .notDetermined {
        locationManager.requestWhenInUseAuthorization()
      }
      guard !isUpdating else { return }
      isUpdating = true
      locationManager.startUpdatingLocation()
      if CLLocationManager.headingAvailable() {
        locationManager.startUpdatingHeading()
      }
    }

    public func stop() {
      stopRideTracking()
      guard isUpdating else { return }
      isUpdating = false
      locationManager.stopUpdatingLocation()
      locationManager.stopUpdatingHeading()
    }

    /// "I'm in the car": keep location going for the whole ride so the car's course is
    /// on record when it stops (FE-13). Started from the foreground on purpose, with
    /// When-In-Use permission and iOS's blue indicator, so the rider can see it running.
    public func startRideTracking() {
      guard !isTrackingRide else { return }
      start()
      locationManager.activityType = .automotiveNavigation
      locationManager.pausesLocationUpdatesAutomatically = false
      // Needs the `location` background mode in app/Info.plist; without it this crashes.
      locationManager.allowsBackgroundLocationUpdates = true
      rideSession = CLBackgroundActivitySession()
      carTrack.removeAll()
      isTrackingRide = true
    }

    public func stopRideTracking() {
      guard isTrackingRide else { return }
      isTrackingRide = false
      rideSession?.invalidate()
      rideSession = nil
      locationManager.allowsBackgroundLocationUpdates = false
      locationManager.pausesLocationUpdatesAutomatically = true
      locationManager.activityType = .other
    }

    /// Forget the ride's courses (new trip, or the rider answered the side question).
    public func resetCarTrack() {
      carTrack.removeAll()
    }

    /// Request a fresh compass reading after the rider calibrates.
    public func restartHeadingUpdates() {
      guard CLLocationManager.headingAvailable() else { return }
      locationManager.stopUpdatingHeading()
      locationManager.startUpdatingHeading()
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManager(
      _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
      guard let location = locations.last else { return }
      lastFailure = nil
      currentSnapshot = LocationSnapshot(
        coordinate: location.coordinate,
        horizontalAccuracy: location.horizontalAccuracy,
        heading: currentSnapshot.heading,
        timestamp: location.timestamp,
        headingReadout: headingReadout,
        courseDegrees: location.course,
        courseAccuracyDegrees: location.courseAccuracy,
        speedMetersPerSecond: location.speed
      )
      if isTrackingRide {
        carTrack.record(CourseSample(location))
      }
    }

    public func locationManager(
      _ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading
    ) {
      // `headingAccuracy` is negative when the reading is unusable, and `trueHeading`
      // is -1 until there's a location fix to work out declination from. Magnetic
      // heading is never used: the server's bearings are true north.
      guard newHeading.headingAccuracy >= 0, newHeading.trueHeading >= 0 else { return }
      let readout = HeadingReadout(
        trueHeadingDegrees: newHeading.trueHeading,
        accuracyDegrees: newHeading.headingAccuracy,
        timestamp: newHeading.timestamp)
      headingReadout = readout
      currentSnapshot = LocationSnapshot(
        coordinate: currentSnapshot.coordinate,
        horizontalAccuracy: currentSnapshot.horizontalAccuracy,
        heading: newHeading,
        // The snapshot's timestamp is the position's. A heading update must not make an
        // old fix look fresh; the heading carries its own time in `readout`.
        timestamp: currentSnapshot.timestamp,
        headingReadout: readout,
        courseDegrees: currentSnapshot.courseDegrees,
        courseAccuracyDegrees: currentSnapshot.courseAccuracyDegrees,
        speedMetersPerSecond: currentSnapshot.speedMetersPerSecond
      )
    }

    /// Let iOS show its own calibration sheet; the app also says what to do (FE-3).
    public func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager)
      -> Bool
    {
      headingReadout?.needsCalibration ?? true
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
      authorizationStatus = manager.authorizationStatus
      switch authorizationStatus {
      case .denied, .restricted:
        lastFailure = Phrases.locationPermissionDenied
        stop()
      case .authorizedWhenInUse, .authorizedAlways:
        lastFailure = nil
        if isUpdating {
          locationManager.startUpdatingLocation()
          if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
          }
        }
      default:
        break
      }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
      if let clError = error as? CLError, clError.code == .denied {
        lastFailure = Phrases.locationPermissionDenied
        return
      }
      lastFailure = Phrases.locationUnavailable
    }
  }

  extension CourseSample {
    /// Everything side-of-street detection needs out of a CoreLocation update.
    public init(_ location: CLLocation) {
      self.init(
        courseDegrees: location.course,
        courseAccuracyDegrees: location.courseAccuracy,
        speedMetersPerSecond: location.speed,
        latitude: location.coordinate.latitude,
        longitude: location.coordinate.longitude,
        timestamp: location.timestamp)
    }
  }

#else

  /// Non-iOS stub.
  public final class LocationService: ObservableObject, LocationProvider {
    public static let shared = LocationService()
    public private(set) var currentSnapshot: LocationSnapshot = LocationSnapshot()
    public private(set) var headingReadout: HeadingReadout?
    public private(set) var isTrackingRide = false
    public private(set) var carTrack = CarCourseTrack()
    public func start() {}
    public func stop() {}
    public func startRideTracking() {}
    public func stopRideTracking() {}
    public func resetCarTrack() {}
    public func restartHeadingUpdates() {}
  }

#endif
