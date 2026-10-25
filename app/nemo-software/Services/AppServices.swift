//  AppServices.swift
//  nemo-software
//
//  Composition root for the long-lived objects the screens share: sensors, feedback
//  channels and the bundle cache. One place to swap a live client or a replay provider
//  in, so no view has to know how its dependencies were built.
//

import Combine
import Foundation

@MainActor
public final class AppServices: ObservableObject {
  public let location: LocationService
  public let feedback: FeedbackKit
  public let bundleStore: BundleStore
  public let entranceClient: CachingEntranceClient
  /// One trip state machine shared by the ride and walk screens, so a hand-over at the
  /// drop-off doesn't lose it (FE-10).
  public let session: NavigationSession
  public let sessionStore: SessionStore

  /// Defaults are built inside the initializer, not as default arguments: a default
  /// argument is evaluated outside the actor, and `LocationService.shared` is
  /// main-actor isolated.
  public init(
    location: LocationService? = nil,
    bundleStore: BundleStore = BundleStore(),
    // The stub reads the bundled resolve.example.json. Swap in
    // `LiveEntranceClient(baseURL: ...)` once the server is up; the cache in front of
    // it means the walk still works with no signal (FE-11).
    upstream: EntranceClient? = nil,
    channels: [FeedbackChannel]? = nil
  ) {
    self.location = location ?? .shared
    self.bundleStore = bundleStore
    self.entranceClient = CachingEntranceClient(
      upstream: upstream ?? StubEntranceClient(), store: bundleStore)
    let feedback = FeedbackKit(channels: channels ?? [SpeechChannel(speaker: Speaker())])
    self.feedback = feedback
    let sessionStore = SessionStore()
    self.sessionStore = sessionStore
    self.session = NavigationSession(feedback: feedback, store: sessionStore)
  }

  /// Pick up a trip that was interrupted by a relaunch (FE-10). Call once at launch.
  public func resumeInterruptedTripIfAny() {
    guard let snapshot = sessionStore.load(), snapshot.state != .setup,
      let bundle = bundleStore.result(for: snapshot.address)
    else { return }
    session.resume(from: snapshot, bundle: bundle)
  }
}
