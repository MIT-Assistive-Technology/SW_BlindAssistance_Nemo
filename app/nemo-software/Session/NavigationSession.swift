//  NavigationSession.swift
//  nemo-software
//
//  App-side wrapper around `SessionReducer` (Logic/). All trip logic lives in the reducer so
//  it can be tested on Linux; this class only publishes state for SwiftUI and hands each
//  effect to `onEffect`, which the composition root wires to FeedbackKit, ARGuide and
//  LocationService.
//

import Combine
import Foundation

public final class NavigationSession: ObservableObject {
  @Published public private(set) var state: SessionState
  @Published public private(set) var isPaused: Bool
  @Published public private(set) var target: Candidate?
  @Published public private(set) var sameSide: Bool?

  /// The current reducer; encode it on `.persist` and pass it back to `init` on relaunch.
  public private(set) var reducer: SessionReducer

  /// Receives every effect, in order, after each input.
  public var onEffect: (SessionEffect) -> Void

  public init(
    reducer: SessionReducer = SessionReducer(),
    onEffect: @escaping (SessionEffect) -> Void = { _ in }
  ) {
    self.reducer = reducer
    self.onEffect = onEffect
    state = reducer.state
    isPaused = reducer.isPaused
    target = reducer.target
    sameSide = reducer.sameSide
  }

  public var bundle: ResolveResult? { reducer.bundle }

  public func send(_ input: SessionInput) {
    let effects = reducer.handle(input)
    if state != reducer.state { state = reducer.state }
    if isPaused != reducer.isPaused { isPaused = reducer.isPaused }
    if target?.id != reducer.target?.id || target?.lat != reducer.target?.lat
      || target?.lon != reducer.target?.lon
    {
      target = reducer.target
    }
    if sameSide != reducer.sameSide { sameSide = reducer.sameSide }
    effects.forEach(onEffect)
  }

  public func load(_ bundle: ResolveResult) { send(.bundleLoaded(bundle)) }
  public func start() { send(.startTapped) }
  public func togglePause() { send(reducer.isPaused ? .resume : .pause) }
  public func stop() { send(.stop) }
}
