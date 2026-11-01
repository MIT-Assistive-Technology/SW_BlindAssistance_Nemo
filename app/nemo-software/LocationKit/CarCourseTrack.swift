//  CarCourseTrack.swift
//  nemo-software
//
//  The car's recent direction of travel (FE-13). `LocationService` appends a sample per
//  location update between "I'm in the car" and the drop-off; the side-of-street rule
//  reads the last trustworthy driving course out of it.
//
//  No CoreLocation here on purpose: the rule has to be testable from a recorded ride
//  (plan section 6, task R5) rather than by driving around.
//

import Foundation

/// One location update, reduced to what side-of-street detection needs.
nonisolated public struct CourseSample: Equatable, Sendable {
  /// Direction of travel, degrees clockwise from true north. Negative when unknown,
  /// which is what `CLLocation.course` reports when it can't tell.
  public let courseDegrees: Double
  /// `CLLocation.courseAccuracy` in degrees. Negative when invalid.
  public let courseAccuracyDegrees: Double
  /// `CLLocation.speed` in m/s. Negative when invalid.
  public let speedMetersPerSecond: Double
  public let latitude: Double
  public let longitude: Double
  public let timestamp: Date

  public init(
    courseDegrees: Double,
    courseAccuracyDegrees: Double,
    speedMetersPerSecond: Double,
    latitude: Double,
    longitude: Double,
    timestamp: Date
  ) {
    self.courseDegrees = courseDegrees
    self.courseAccuracyDegrees = courseAccuracyDegrees
    self.speedMetersPerSecond = speedMetersPerSecond
    self.latitude = latitude
    self.longitude = longitude
    self.timestamp = timestamp
  }

  /// A course worth using: the car was actually driving and the heading of travel was
  /// measured well. Plan section 6: speeds above 3 m/s with good course accuracy only.
  public var isDrivingCourse: Bool {
    courseDegrees >= 0
      && courseAccuracyDegrees >= 0
      && courseAccuracyDegrees <= CarCourseTrack.maxCourseAccuracyDegrees
      && speedMetersPerSecond >= CarCourseTrack.minDrivingSpeed
  }

  /// Walking speed or slower: the car has stopped (or we're already on foot).
  public var isStopped: Bool {
    speedMetersPerSecond >= 0 && speedMetersPerSecond < CarCourseTrack.stoppedSpeed
  }

  /// Going somewhere, at any speed — including a crawl in traffic that never reaches
  /// driving speed. A crawl still means the drop-off hasn't happened yet, so this is
  /// what arms and cancels stop detection.
  ///
  /// Note that an invalid speed (`CLLocation.speed` is negative when unknown, which
  /// happens in tunnels and urban canyons) is neither moving nor stopped. It must not
  /// count as movement, or it would cancel a real stop.
  public var isMoving: Bool {
    speedMetersPerSecond >= CarCourseTrack.stoppedSpeed
  }
}

/// A rolling window of course samples for the current ride.
nonisolated public struct CarCourseTrack: Equatable, Sendable {
  /// Below this the course is noise, not a direction of travel (plan section 6).
  public static let minDrivingSpeed = 3.0
  /// `CLLocation.courseAccuracy` worse than this counts as "poor course accuracy".
  public static let maxCourseAccuracyDegrees = 20.0
  /// Under this the vehicle counts as stopped.
  public static let stoppedSpeed = 1.0
  /// A driving course older than this is stale: the car may have turned since.
  public static let maxCourseAge: TimeInterval = 60
  /// Window checked for a turn or U-turn right before the stop.
  public static let turnWindow: TimeInterval = 10
  /// A course change bigger than this inside the turn window means the final course
  /// no longer tells us which way the car was travelling along the road.
  public static let turnThresholdDegrees = 25.0
  /// How long the car has to be slow before the stop counts as a drop-off.
  public static let stopDwell: TimeInterval = 5

  /// Samples kept, oldest first. Older ones are dropped.
  public private(set) var samples: [CourseSample] = []
  /// How much history to keep.
  public var window: TimeInterval

  public init(window: TimeInterval = 300, samples: [CourseSample] = []) {
    self.window = window
    self.samples = samples
    trim()
  }

  public mutating func record(_ sample: CourseSample) {
    samples.append(sample)
    samples.sort { $0.timestamp < $1.timestamp }
    trim()
  }

  public mutating func removeAll() { samples.removeAll() }

  private mutating func trim() {
    guard let newest = samples.last?.timestamp else { return }
    let cutoff = newest.addingTimeInterval(-window)
    samples.removeAll { $0.timestamp < cutoff }
  }

  /// The most recent trustworthy driving course at or before `asOf`, or nil when the
  /// ride wasn't tracked, the car never drove fast enough, or the course is stale.
  public func drivingCourse(asOf moment: Date) -> CourseSample? {
    guard
      let sample = samples.last(where: {
        $0.timestamp <= moment && $0.isDrivingCourse
      })
    else { return nil }
    guard moment.timeIntervalSince(sample.timestamp) <= Self.maxCourseAge else { return nil }
    return sample
  }

  /// Did the car turn in the `turnWindow` seconds before `moment`? A turn makes the
  /// final course point the wrong way along the road, so the side becomes unknown.
  public func hadTurn(before moment: Date) -> Bool {
    let window = samples.filter {
      $0.isDrivingCourse
        && $0.timestamp <= moment
        && moment.timeIntervalSince($0.timestamp) <= Self.turnWindow
    }
    guard let reference = window.last else { return false }
    return window.contains {
      abs(Geo.relativeAngle(heading: $0.courseDegrees, target: reference.courseDegrees))
        > Self.turnThresholdDegrees
    }
  }

  /// When the car stopped: the first slow sample after the last driving sample, once it
  /// has stayed slow for `stopDwell`. Nil while the car is still moving.
  ///
  /// This cannot tell a red light from a drop-off — to GPS they are the same event — so
  /// it reports **every** stop and the caller asks the rider. Each move-and-stop cycle
  /// produces a new timestamp, which is what lets the question be asked again at the
  /// next stop after a "not yet".
  ///
  /// NOTE (FE-13): Core Motion reporting "walking" would make a stop trustworthy enough
  /// to act on. It needs an `NSMotionUsageDescription` key, so it's left for the motion
  /// task; speed alone is what this uses.
  public func stopDetected(asOf moment: Date) -> Date? {
    // It has to have been a ride. A phone sitting on a table is not a drop-off.
    guard samples.contains(where: { $0.isDrivingCourse }) else { return nil }
    // Anchor on the last time the car moved at all, not the last good driving course:
    // a car that creeps forward at 2 m/s has moved, even though its course is useless.
    guard let lastMoving = samples.last(where: { $0.isMoving }) else { return nil }
    guard
      let firstSlow = samples.first(where: {
        $0.timestamp > lastMoving.timestamp && $0.isStopped
      })
    else { return nil }
    // Moving again cancels it: that stop was traffic, not a drop-off.
    guard !samples.contains(where: { $0.timestamp > firstSlow.timestamp && $0.isMoving })
    else { return nil }
    guard moment.timeIntervalSince(firstSlow.timestamp) >= Self.stopDwell else { return nil }
    return firstSlow.timestamp
  }

  /// Newest sample of any quality, for the status screen.
  public var latest: CourseSample? { samples.last }
}
