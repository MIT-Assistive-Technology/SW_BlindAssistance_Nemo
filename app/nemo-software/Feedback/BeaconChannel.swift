//  BeaconChannel.swift
//  nemo-software
//
//  FE-4, by Trish Zheng. Moved out of FeedbackKit.swift during the merge of
//  `trish-navigation` so the speech and beacon channels live in separate files.
//
//  Changes made while merging:
//    - `.bearingLock` now carries `metersToDoor`, so the pattern binds it.
//    - `renderingAlgorithm = .HRTF`. The default is `equalPowerPanning`, which only
//      encodes the left–right axis: a door 45° ahead-right and one 135° behind-right
//      pan identically, so "turn until it centres" would have a second solution 180°
//      out. HRTF filters for front/back as well.
//    - The audio session is NOT configured here. `AppServices` owns it, so the beacon
//      and the speech channel can't fight over the category.
//

import AVFoundation
import Foundation

// Directional audio beacon: a tone that sounds like it sits at the door's position in space(HRTF spatialization on stereo headphones)
public final class BeaconChannel: FeedbackChannel {
  public let name = "beacon"

  private let engine = AVAudioEngine()  // wires node to output
  private let environment = AVAudioEnvironmentNode()  // gives sound a 3D position
  private let player = AVAudioPlayerNode()  // plays looping tone
  private var buffer: AVAudioPCMBuffer?
  private var hasChosenAlgorithm = false

  public init() {
    setupGraph()
  }

  //Point the tone at the door
  public func updateTarget(relativeAngleDegrees angle: Double) {
    let radians = angle * .pi / 180
    let distance: Float = 2
    // Environment space: you sit at (0,0,0) facing -z. +x = your right ear.
    player.position = AVAudio3DPoint(
      x: Float(sin(radians)) * distance,
      y: 0,
      z: Float(-cos(radians)) * distance)
  }

  public func play(_ event: FeedbackEvent) {
    switch event {
    case .direction(let offset), .doorDetected(let offset, _):
      updateTarget(relativeAngleDegrees: offset)  // aim the tone at the angle
      startTone()  // make sure it's playing
    case .bearingLock:
      startTone()  // locked on — keep ticking
    case .arrival, .lost:
      stop()  // no valid target → silence
    default:
      break  // speech/haptics own the rest
    }
  }

  // Wires audio graph: player - environment - mixer - speakers
  private func setupGraph() {
    guard let buffer = makeBeaconBuffer() else { return }
    self.buffer = buffer

    engine.attach(player)  //plug player into engine
    engine.attach(environment)  //plug 3d node into engine
    engine.connect(player, to: environment, format: buffer.format)  // player feed 3d node
    engine.connect(environment, to: engine.mainMixerNode, format: nil)  // 3d node feeds output
  }

  /// Which algorithms apply depends on the engine's current output format, so this is
  /// asked after the engine starts rather than while wiring the graph.
  private func applyHRTFIfPossible() {
    guard !hasChosenAlgorithm else { return }
    hasChosenAlgorithm = true
    // `applicableRenderingAlgorithms` is [NSNumber], not the enum.
    let supported = environment.applicableRenderingAlgorithms.compactMap {
      AVAudio3DMixingRenderingAlgorithm(rawValue: $0.intValue)
    }
    // The default is equalPowerPanning, which only encodes left–right: a door 45°
    // ahead-right and one 135° behind-right would sound identical.
    if supported.contains(.HRTF) {
      player.renderingAlgorithm = .HRTF
    } else {
      print("[BeaconChannel] HRTF unavailable for this output; falling back to panning.")
    }
  }

  // Start engine, loop tone
  private func startTone() {
    guard let buffer else { return }  // do nothing if setup failed
    if !engine.isRunning {
      engine.prepare()
      try? engine.start()
      applyHRTFIfPossible()
    }
    if !player.isPlaying {
      player.scheduleBuffer(buffer, at: nil, options: .loops)  // loop tick
      player.play()
    }
  }

  // Generates audio buffer that we loop
  private func makeBeaconBuffer() -> AVAudioPCMBuffer? {
    guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)
    else { return nil }
    let frameCount = AVAudioFrameCount(44100 * 0.5)  // 0.5s buffer
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
      let data = buffer.floatChannelData?[0]
    else { return nil }
    buffer.frameLength = frameCount

    let tickFrames = Int(44100 * 0.06)
    for i in 0..<tickFrames {
      let t = Double(i) / 44100
      let envelope = exp(-t * 40)
      data[i] = Float(sin(2 * .pi * 880 * t) * envelope * 0.3)
    }
    return buffer
  }

  public func stop() {
    player.stop()
    engine.stop()
  }
}
