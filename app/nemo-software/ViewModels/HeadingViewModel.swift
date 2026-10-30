//  HeadingViewModel.swift
//  nemo-software
//
//  FE-3: the heading readout screen's state. Starts the sensors while the screen is up,
//  and decides when to speak (the throttling itself is `HeadingAnnouncer`, which is
//  pure and unit tested).
//

import Combine
import CoreLocation
import Foundation

@MainActor
public final class HeadingViewModel: ObservableObject {
  @Published public private(set) var readout: HeadingReadout?
  /// Nil when everything is fine; otherwise what's wrong, in spoken words.
  @Published public private(set) var problem: String?
  /// Speak the heading as it changes. Off means the rider reads it with VoiceOver.
  @Published public var speaksChanges = true

  private let location: LocationService
  private let feedback: FeedbackKit
  private var announcer = HeadingAnnouncer()
  private var cancellables = Set<AnyCancellable>()

  public init(location: LocationService, feedback: FeedbackKit) {
    self.location = location
    self.feedback = feedback

    location.$headingReadout
      .receive(on: DispatchQueue.main)
      .sink { [weak self] readout in self?.apply(readout) }
      .store(in: &cancellables)

    location.$lastFailure
      .receive(on: DispatchQueue.main)
      .removeDuplicates()
      .sink { [weak self] failure in
        guard let self else { return }
        problem = failure
        // A denied permission is announced by voice, not just shown (FE-3).
        if failure == Phrases.locationPermissionDenied {
          feedback.emit(.locationPermissionDenied)
        }
      }
      .store(in: &cancellables)
  }

  public var headingText: String {
    guard let readout else { return "Waiting for the compass" }
    return "\(Int(readout.trueHeadingDegrees.rounded()) % 360)° \(readout.compassPoint)"
  }

  public var accuracyText: String {
    guard let readout else { return "No reading yet" }
    return "Accuracy ±\(Int(readout.accuracyDegrees.rounded()))°"
  }

  /// What VoiceOver reads for the whole readout, as one sentence.
  public var accessibilityText: String {
    guard let readout else { return "Waiting for the compass." }
    var text = readout.spokenText
    if readout.needsCalibration { text += " " + Phrases.compassCalibration }
    return text
  }

  public var needsCalibration: Bool { readout?.needsCalibration ?? false }

  public func onAppear() {
    guard location.isHeadingAvailable else {
      problem = Phrases.headingUnavailable
      feedback.emit(.headingUnavailable)
      return
    }
    location.start()
  }

  public func onDisappear() {
    // Keep the ride's tracking alive if it's running; only this screen's updates stop.
    if !location.isTrackingRide { location.stop() }
    feedback.stopAll()
  }

  /// "Speak heading" button: say the current reading even if nothing changed.
  /// Forced, because asking again and hearing nothing (the chatter guard) is
  /// indistinguishable from a broken app when you can't see the screen.
  public func speakNow() {
    announcer.reset()
    guard let readout else {
      feedback.emit(
        location.isHeadingAvailable ? .locationPermissionDenied : .headingUnavailable,
        force: true)
      return
    }
    emit(readout, force: true)
  }

  public func calibrate() {
    location.restartHeadingUpdates()
    feedback.emit(.compassCalibration, force: true)
  }

  private func apply(_ readout: HeadingReadout?) {
    self.readout = readout
    guard speaksChanges, let readout else { return }
    if let phrase = announcer.announcement(for: readout), !phrase.isEmpty {
      emit(readout, calibration: phrase == Phrases.compassCalibration)
    }
  }

  private func emit(_ readout: HeadingReadout, calibration: Bool = false, force: Bool = false) {
    if calibration || readout.needsCalibration {
      feedback.emit(.compassCalibration, force: force)
    } else {
      feedback.emit(
        .heading(degrees: readout.trueHeadingDegrees, accuracyDegrees: readout.accuracyDegrees),
        force: force)
    }
  }
}
