//  NavigationSession.swift
//  nemo-software
//
//  The trip state machine (FE-10). Drives which sensors run and what FeedbackKit says.
//  See docs/car-to-curb-plan.md sections 3 (user workflow) and 11 (phone).
//
//    Setup -> Arrival -> Orient -> Guide -> Confirm -> Arrived
//                          ^         |         |
//                          +------ Lost <------+
//

import Combine
import Foundation

public enum SessionState: Equatable, Sendable {
  /// Destination set, bundle cached, waiting for the ride to end.
  case setup
  /// Car stopped: work out the side of street, brief the rider.
  case arrival
  /// Rider turns until the heading is within 15° of the door for 1 s.
  case orient
  /// Walking: beacon, landmarks, building check (camera-first mode).
  case guide
  /// Last ~10 m: camera door check.
  case confirm
  case arrived
  /// Off by more than 60° for 5 s, tracking lost, or no door found for 20 s.
  case lost
}

public final class NavigationSession: ObservableObject {
  @Published public private(set) var state: SessionState = .setup

  private let feedback: FeedbackKit
  private let bundle: ResolveResult

  public init(bundle: ResolveResult, feedback: FeedbackKit) {
    self.bundle = bundle
    self.feedback = feedback
  }

  /// The door the rider is being guided to.
  public var target: Candidate? { bundle.candidates.first }

  public func start() {
    // TODO (FE-10): move to .arrival and say "Exit on the curb side." Then compute the side of
    // street (FE-13, Geo.sameSide; nil -> ask "Did you get out onto the sidewalk?") and give
    // the brief: "Your entrance should be on this side of the street, about 110 feet ahead."
    // If the door is across the street: say so, point the beacon to the crossing or stay
    // silent, and never point it at the door.
    state = .arrival
  }

  public func stop() {
    feedback.stopAll()
  }

  // TODO (FE-10): add update(position:heading:) called by LocationKit/ARGuide that
  // applies the transitions above, saves breadcrumbs, announces landmarks ~5 m ahead,
  // and moves to .lost / back to .orient at the last breadcrumb.
  // First-steps check: after ~5 m, if the walking direction is more than ~30° off the
  // expected sidewalk direction, say "I'm not sure" before giving more guidance.
  // Persist state so a relaunch mid-trip resumes (side unknown -> ask).
  // Test it by replaying a recorded GPS trace (QA-4), not by walking.
}
