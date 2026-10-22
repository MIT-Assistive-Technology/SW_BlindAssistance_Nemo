//  LocationService.swift
//  nemo-software
//
//  Owns CLLocationManager and Core Motion. Publishes `LocationSnapshot` for the perception
//  pipeline and turns raw updates into `SessionInput`s for the trip:
//    .carCourse    every course sample while "I'm in the car" tracking runs
//    .carStopped   the last stop, sent once Core Motion reports walking (a red light isn't a drop-off)
//    .walkingDetected
//    .pose         GPS position + true heading (or GPS course in pocket mode)
//  Permission problems go to `onProblem` so the app can say them aloud, not just show them.
//
//  When In Use only. Background updates run only after the rider taps "I'm in the car"
//  (CLBackgroundActivitySession + allowsBackgroundLocationUpdates; the `location` background
//  mode is in app/Info.plist). Location never leaves the phone.
//

import Combine
import CoreLocation
import CoreMotion
import Foundation

public protocol LocationProvider: AnyObject {
  /// The most recent snapshot, or an empty one if nothing has been received.
  var currentSnapshot: LocationSnapshot { get }
}

/// Things the rider must hear about, not just see.
enum LocationProblem: Equatable {
  case permissionDenied
  case locationUnavailable
  case compassNeedsCalibration
}

#if os(iOS)

  /// Live GPS + compass + motion provider. Delegate callbacks arrive on the main run loop
  /// (the manager is created on the main thread), so they hop into the main actor directly.
  final class LocationService: NSObject, ObservableObject, LocationProvider,
    CLLocationManagerDelegate
  {
    static let shared = LocationService()

    @Published private(set) var currentSnapshot: LocationSnapshot = LocationSnapshot()
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isCarTracking = false

    /// Session inputs (car course, stop, walking, pose). Set by the composition root.
    var onInput: ((SessionInput) -> Void)?
    /// Problems to announce by voice.
    var onProblem: ((LocationProblem) -> Void)?
    /// Pocket mode: the compass isn't the rider's facing direction, so use GPS course while walking.
    var useCourseAsHeading = false

    private let locationManager = CLLocationManager()
    private let motion = CMMotionActivityManager()
    private var backgroundSession: CLBackgroundActivitySession?
    private var wantsUpdates = false

    // Car-stop detection.
    private var wasDriving = false
    private var lastStopAt: Date?
    private var isMotionRunning = false

    // Pose throttling and compass warnings.
    private var lastLocation: CLLocation?
    private var lastPoseAt = Date.distantPast
    private var lastCalibrationWarning = Date.distantPast
    private static let minPoseInterval: TimeInterval = 0.2

    private override init() {
      super.init()
      locationManager.delegate = self
      locationManager.desiredAccuracy = kCLLocationAccuracyBest
      locationManager.headingFilter = 2
      locationManager.activityType = .otherNavigation
      authorization = locationManager.authorizationStatus
    }

    // MARK: - Public API

    /// Starts foreground location and heading updates, asking for When In Use permission
    /// the first time. Safe to call more than once.
    func start() {
      wantsUpdates = true
      switch locationManager.authorizationStatus {
      case .notDetermined:
        locationManager.requestWhenInUseAuthorization()
      // Updates start in locationManagerDidChangeAuthorization.
      case .denied, .restricted:
        onProblem?(.permissionDenied)
      default:
        beginUpdates()
      }
    }

    /// Stops everything, including car tracking and background updates.
    func stop() {
      wantsUpdates = false
      stopCarTracking()
      endBackgroundUpdates()
      locationManager.stopUpdatingLocation()
      locationManager.stopUpdatingHeading()
    }

    /// The rider's explicit "I'm in the car" action. Must be called while the app is in the
    /// foreground. Keeps location running for the ride (blue indicator) and records the car's
    /// course for side-of-street detection.
    func startCarTracking() {
      guard !isCarTracking else { return }
      isCarTracking = true
      wasDriving = false
      lastStopAt = nil
      if backgroundSession == nil { backgroundSession = CLBackgroundActivitySession() }
      locationManager.allowsBackgroundLocationUpdates = true
      locationManager.showsBackgroundLocationIndicator = true
      locationManager.pausesLocationUpdatesAutomatically = false
      locationManager.activityType = .automotiveNavigation
      start()
      startMotion()
    }

    /// Ends the car phase (after the drop-off). Background updates keep running for the walk
    /// until `stop()`, so the beacon can follow GPS with the screen locked.
    func stopCarTracking() {
      guard isCarTracking else { return }
      isCarTracking = false
      locationManager.activityType = .otherNavigation
      stopMotion()
    }

    // MARK: - CLLocationManagerDelegate (main run loop)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
      let status = manager.authorizationStatus
      MainActor.assumeIsolated { self.authorizationChanged(status) }
    }

    nonisolated func locationManager(
      _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
      guard let latest = locations.last else { return }
      MainActor.assumeIsolated { self.handle(latest) }
    }

    nonisolated func locationManager(
      _ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading
    ) {
      MainActor.assumeIsolated { self.handle(newHeading) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
      let code = (error as? CLError)?.code
      MainActor.assumeIsolated { self.handleFailure(code) }
    }

    // MARK: - Private

    private func authorizationChanged(_ status: CLAuthorizationStatus) {
      authorization = status
      switch status {
      case .authorizedWhenInUse, .authorizedAlways:
        if wantsUpdates { beginUpdates() }
      case .denied, .restricted:
        if wantsUpdates { onProblem?(.permissionDenied) }
      default:
        break
      }
    }

    private func beginUpdates() {
      locationManager.startUpdatingLocation()
      if CLLocationManager.headingAvailable() { locationManager.startUpdatingHeading() }
    }

    private func endBackgroundUpdates() {
      backgroundSession?.invalidate()
      backgroundSession = nil
      locationManager.allowsBackgroundLocationUpdates = false
    }

    private func handleFailure(_ code: CLError.Code?) {
      guard let code else { return }
      switch code {
      case .denied:
        onProblem?(.permissionDenied)
      case .locationUnknown, .headingFailure:
        // Transient: Core Location keeps trying.
        break
      default:
        onProblem?(.locationUnavailable)
      }
    }

    private func handle(_ location: CLLocation) {
      guard location.horizontalAccuracy >= 0 else { return }
      lastLocation = location
      currentSnapshot = LocationSnapshot(
        coordinate: location.coordinate,
        horizontalAccuracy: location.horizontalAccuracy,
        heading: currentSnapshot.heading,
        timestamp: location.timestamp
      )

      if isCarTracking {
        if location.speed >= 0, location.course >= 0 {
          onInput?(
            .carCourse(
              degrees: location.course, speed: location.speed,
              accuracy: location.courseAccuracy, at: location.timestamp))
        }
        if location.speed > 3 {
          wasDriving = true
          lastStopAt = nil
        } else if wasDriving, location.speed >= 0, location.speed < 0.5, lastStopAt == nil {
          lastStopAt = location.timestamp
        }
      }
      emitPose(force: true)
    }

    private func handle(_ heading: CLHeading) {
      // Negative accuracy = invalid; negative trueHeading = no location fix yet.
      guard heading.headingAccuracy >= 0, heading.trueHeading >= 0 else { return }
      currentSnapshot = LocationSnapshot(
        coordinate: currentSnapshot.coordinate,
        horizontalAccuracy: currentSnapshot.horizontalAccuracy,
        heading: heading,
        timestamp: heading.timestamp
      )
      if heading.headingAccuracy > 20, Date().timeIntervalSince(lastCalibrationWarning) > 60 {
        lastCalibrationWarning = Date()
        onProblem?(.compassNeedsCalibration)
      }
      emitPose(force: false)
    }

    /// Direction the rider faces: true heading, or GPS course in pocket mode while walking.
    private var facingDegrees: Double? {
      if useCourseAsHeading, let location = lastLocation, location.speed > 0.7,
        location.course >= 0, location.courseAccuracy >= 0, location.courseAccuracy < 30
      {
        return location.course
      }
      if let heading = currentSnapshot.heading, heading.trueHeading >= 0 {
        return heading.trueHeading
      }
      if let location = lastLocation, location.course >= 0 { return location.course }
      return nil
    }

    private func emitPose(force: Bool) {
      guard let location = lastLocation, let facing = facingDegrees else { return }
      let now = Date()
      guard force || now.timeIntervalSince(lastPoseAt) >= Self.minPoseInterval else { return }
      lastPoseAt = now
      onInput?(
        .pose(
          lat: location.coordinate.latitude, lon: location.coordinate.longitude,
          headingDegrees: facing, accuracyMeters: location.horizontalAccuracy, at: now))
    }

    // MARK: - Core Motion (stop, then walking)

    /// Core Motion needs NSMotionUsageDescription; without it the app would crash, so motion
    /// stays off and the rider starts guidance by hand.
    private var motionAllowed: Bool {
      CMMotionActivityManager.isActivityAvailable()
        && Bundle.main.object(forInfoDictionaryKey: "NSMotionUsageDescription") != nil
        && CMMotionActivityManager.authorizationStatus() != .denied
    }

    private func startMotion() {
      guard !isMotionRunning, motionAllowed else { return }
      isMotionRunning = true
      motion.startActivityUpdates(to: .main) { [weak self] activity in
        MainActor.assumeIsolated { self?.handle(activity) }
      }
    }

    private func stopMotion() {
      guard isMotionRunning else { return }
      isMotionRunning = false
      motion.stopActivityUpdates()
    }

    private func handle(_ activity: CMMotionActivity?) {
      guard let activity, activity.confidence != .low else { return }
      if activity.automotive {
        wasDriving = true
        return
      }
      guard activity.walking, isCarTracking, wasDriving else { return }
      onInput?(.carStopped(at: lastStopAt ?? activity.startDate))
      onInput?(.walkingDetected)
      stopCarTracking()
    }
  }

#else

  /// Non-iOS stub.
  final class LocationService: ObservableObject, LocationProvider {
    static let shared = LocationService()
    private(set) var currentSnapshot: LocationSnapshot = LocationSnapshot()
    var onInput: ((SessionInput) -> Void)?
    var onProblem: ((LocationProblem) -> Void)?
    var useCourseAsHeading = false
    private(set) var isCarTracking = false
    func start() {}
    func stop() {}
    func startCarTracking() {}
    func stopCarTracking() {}
  }

#endif
