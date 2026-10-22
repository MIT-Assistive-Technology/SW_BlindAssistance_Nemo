//  FeedbackProfile.swift
//  nemo-software
//
//  The rider's feedback choices from setup and Settings, saved on the phone (no account).
//

import Foundation

public struct FeedbackProfile: Codable, Equatable, Sendable {
  public var name: String
  /// Schema version, bumped when fields change so old saved profiles can be migrated.
  public var version: Int
  public var hapticsOn: Bool
  public var beaconOn: Bool
  public var voiceOn: Bool
  public var verbosity: Verbosity
  public var units: Units
  /// true = camera-first (phone held or chest-mounted, building check on);
  /// false = pocket mode (beacon on GPS course; camera, haptics and ARKit off).
  public var cameraFirst: Bool
  /// 0...1, capped so the beacon never masks traffic.
  public var beaconVolume: Double

  public init(
    name: String, version: Int = 1, hapticsOn: Bool, beaconOn: Bool, voiceOn: Bool,
    verbosity: Verbosity, units: Units = .feet, cameraFirst: Bool = true,
    beaconVolume: Double = 0.6
  ) {
    self.name = name
    self.version = version
    self.hapticsOn = hapticsOn
    self.beaconOn = beaconOn
    self.voiceOn = voiceOn
    self.verbosity = verbosity
    self.units = units
    self.cameraFirst = cameraFirst
    self.beaconVolume = min(max(beaconVolume, 0), 1)
  }

  public static let hapticsFirst = FeedbackProfile(
    name: "Haptics-first", hapticsOn: true, beaconOn: true, voiceOn: true, verbosity: .minimal)
  public static let audioFirst = FeedbackProfile(
    name: "Audio-first", hapticsOn: true, beaconOn: true, voiceOn: true, verbosity: .normal)
  public static let voiceOnly = FeedbackProfile(
    name: "Voice-only", hapticsOn: false, beaconOn: false, voiceOn: true, verbosity: .normal)

  public static let presets: [FeedbackProfile] = [hapticsFirst, audioFirst, voiceOnly]
}
