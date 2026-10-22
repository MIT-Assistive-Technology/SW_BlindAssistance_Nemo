//  BeaconChannel.swift
//  nemo-software
//
//  Spatial audio beacon: a soft repeating tone placed at the target's bearing with HRTF,
//  so on headphones the rider hears where to walk. Chain:
//    AVAudioPlayerNode (mono) -> AVAudioEnvironmentNode (HRTFHQ) -> main mixer.
//  The tone is generated in code; no audio asset.
//
//  Without headphones the phone speaker can't convey direction, so the beacon becomes a
//  non-spatial pulse whose rate encodes alignment: faster and higher when facing the target.
//
//  Safety: volume is capped so it never masks traffic, and it ducks during warnings.
//

import AVFoundation
import Foundation
import os

/// HRTF beacon steered by a world bearing and the rider's heading.
public final class BeaconChannel {
  /// Hard cap on output volume (0...1), whatever the profile asks for.
  public static let maxVolume: Float = 0.6
  /// Volume multiplier while a warning is playing.
  public static let duckFactor: Float = 0.2

  /// True between `start()` and `stop()` (also while paused).
  public private(set) var isRunning = false
  public private(set) var isPaused = false

  private var engine = AVAudioEngine()
  private var player = AVAudioPlayerNode()
  private var environment = AVAudioEnvironmentNode()
  private let format: AVAudioFormat
  private let audio: AudioSessionManager
  private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "nemo-software", category: "Beacon")
  private var configObserver: NSObjectProtocol?

  private var targetBearing: Double?
  private var targetDistance: Double = 20
  private var listenerHeading: Double = 0
  private var userVolume: Float = 0.5
  private var duckedUntil: Date?
  private var interrupted = false
  /// The pulse currently scheduled; a new buffer is only built when this changes.
  private var scheduledPulse: Pulse?
  /// Whether the source is currently rendered with HRTF (nil until first render).
  private var spatialMode: Bool?

  private struct Pulse: Equatable {
    var intervalSeconds: Double
    var frequency: Double
  }

  private static let sampleRate: Double = 44_100
  private static let toneSeconds: Double = 0.16

  public init(audio: AudioSessionManager = .shared) {
    self.audio = audio
    // A mono standard format always exists; spatial mixing requires mono input.
    self.format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)!
    buildGraph()
  }

  // MARK: - Public API

  /// Places the beacon at a world bearing (degrees clockwise from true north) and distance.
  /// Closer targets pulse faster.
  public func setTarget(bearingDegrees: Double, distanceMeters: Double) {
    targetBearing = bearingDegrees
    targetDistance = max(0, distanceMeters)
    refresh()
  }

  /// Removes the target; the beacon goes silent but stays ready (e.g. door across the street).
  public func clearTarget() {
    targetBearing = nil
    player.stop()
    scheduledPulse = nil
  }

  /// Updates where the rider faces (degrees clockwise from true north). Call 30-60 times a second.
  public func setListenerHeading(_ headingDegrees: Double) {
    listenerHeading = headingDegrees
    refresh()
  }

  /// Sets the rider's preferred volume (0...1); capped at `maxVolume`.
  public func setVolume(_ volume: Float) {
    userVolume = min(max(volume, 0), 1)
    applyVolume()
  }

  /// Lowers the beacon for `seconds` so a warning (road, driveway) is clearly heard.
  public func duck(for seconds: TimeInterval) {
    duckedUntil = Date().addingTimeInterval(seconds)
    applyVolume()
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(seconds))
      self?.applyVolume()
    }
  }

  /// Starts the audio engine. The tone plays once a target is set.
  public func start() {
    guard !isRunning else { return }
    isRunning = true
    isPaused = false
    audio.beaconWillStart()
    startEngine()
  }

  /// Stops the beacon and releases the audio session.
  public func stop() {
    guard isRunning else { return }
    isRunning = false
    isPaused = false
    player.stop()
    engine.stop()
    scheduledPulse = nil
    audio.beaconDidStop()
  }

  /// Pauses the tone, keeping the target.
  public func pause() {
    guard isRunning, !isPaused else { return }
    isPaused = true
    player.pause()
    engine.pause()
  }

  /// Resumes after `pause()`.
  public func resume() {
    guard isRunning, isPaused else { return }
    isPaused = false
    startEngine()
  }

  // MARK: - Called by FeedbackKit

  func interruptionBegan() {
    interrupted = true
    // The system already stopped the engine; the player loses its schedule.
    scheduledPulse = nil
  }

  func interruptionEnded() {
    interrupted = false
    if isRunning, !isPaused { startEngine() }
  }

  /// Headphones came or went: switch between spatial and pulse mode.
  func routeChanged() {
    scheduledPulse = nil
    refresh()
  }

  /// The media server restarted; every node is invalid, so rebuild the graph.
  func rebuildAfterMediaReset() {
    let wasRunning = isRunning && !isPaused
    if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    engine = AVAudioEngine()
    player = AVAudioPlayerNode()
    environment = AVAudioEnvironmentNode()
    scheduledPulse = nil
    spatialMode = nil
    buildGraph()
    if wasRunning { startEngine() }
  }

  // MARK: - Engine

  private func buildGraph() {
    engine.attach(player)
    engine.attach(environment)
    engine.connect(player, to: environment, format: format)
    engine.connect(environment, to: engine.mainMixerNode, format: nil)

    player.renderingAlgorithm = .HRTFHQ
    player.sourceMode = .pointSource
    environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)
    applyVolume()

    // Route changes and other reconfigurations stop the engine; restart it.
    configObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.handleConfigurationChange()
      }
    }
  }

  private func handleConfigurationChange() {
    scheduledPulse = nil
    if isRunning, !isPaused, !interrupted { startEngine() }
  }

  private func startEngine() {
    guard !interrupted else { return }
    do {
      if !engine.isRunning {
        engine.prepare()
        try engine.start()
      }
      refresh()
    } catch {
      log.error("Beacon engine failed to start: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Rendering

  /// Positions the source and (re)schedules the pulse if its rate or pitch changed.
  private func refresh() {
    guard isRunning, !isPaused, !interrupted, engine.isRunning, let bearing = targetBearing else { return }

    let relative = Self.normalize(bearing - listenerHeading)
    let pulse: Pulse
    let spatial = audio.headphonesConnected
    if spatial != spatialMode {
      player.renderingAlgorithm = spatial ? .HRTFHQ : .equalPowerPanning
      spatialMode = spatial
    }
    if spatial {
      // World frame: north = -Z, east = +X, up = +Y. Source 1 m away at the target bearing.
      let b = bearing * .pi / 180
      player.position = AVAudio3DPoint(x: Float(sin(b)), y: 0, z: Float(-cos(b)))
      // Orientation as forward/up vectors: same effect as a yaw of the heading, without
      // depending on the yaw sign convention.
      let h = listenerHeading * .pi / 180
      environment.listenerVectorOrientation = AVAudio3DVectorOrientation(
        forward: AVAudio3DVector(x: Float(sin(h)), y: 0, z: Float(-cos(h))),
        up: AVAudio3DVector(x: 0, y: 1, z: 0)
      )
      pulse = Self.spatialPulse(distanceMeters: targetDistance)
    } else {
      // Phone speaker: no direction cue, so place it straight ahead and encode alignment in rate.
      environment.listenerVectorOrientation = AVAudio3DVectorOrientation(
        forward: AVAudio3DVector(x: 0, y: 0, z: -1),
        up: AVAudio3DVector(x: 0, y: 1, z: 0)
      )
      player.position = AVAudio3DPoint(x: 0, y: 0, z: -1)
      pulse = Self.alignmentPulse(offsetDegrees: abs(relative))
    }

    if pulse != scheduledPulse, let buffer = makeBuffer(pulse) {
      let options: AVAudioPlayerNodeBufferOptions =
        scheduledPulse == nil ? [.loops, .interrupts] : [.loops, .interruptsAtLoop]
      player.scheduleBuffer(buffer, at: nil, options: options, completionHandler: nil)
      scheduledPulse = pulse
    }
    // Also restarts the player after pause(), when the schedule is still in place.
    if scheduledPulse != nil, !player.isPlaying { player.play() }
  }

  private func applyVolume() {
    var volume = min(userVolume, Self.maxVolume)
    if let duckedUntil, duckedUntil > Date() { volume *= Self.duckFactor }
    player.volume = volume
  }

  /// Headphones: rate encodes distance (quantized so the buffer isn't rebuilt constantly).
  private static func spatialPulse(distanceMeters: Double) -> Pulse {
    let interval: Double
    switch distanceMeters {
    case ..<5: interval = 0.45
    case ..<15: interval = 0.75
    default: interval = 1.1
    }
    return Pulse(intervalSeconds: interval, frequency: 660)
  }

  /// Speaker: within 15 degrees -> fast, high; up to 180 degrees off -> slow, low. 8 steps.
  private static func alignmentPulse(offsetDegrees: Double) -> Pulse {
    if offsetDegrees <= 15 { return Pulse(intervalSeconds: 0.3, frequency: 880) }
    let step = min(7, Int((offsetDegrees - 15) / (165.0 / 7)) + 1)  // 1...7
    return Pulse(intervalSeconds: 0.3 + Double(step) * 0.18, frequency: 660)
  }

  /// One soft tone (fundamental + a fifth, sine-squared envelope) followed by silence.
  private func makeBuffer(_ pulse: Pulse) -> AVAudioPCMBuffer? {
    let rate = format.sampleRate
    let totalFrames = AVAudioFrameCount(max(pulse.intervalSeconds, Self.toneSeconds + 0.05) * rate)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames),
      let samples = buffer.floatChannelData?[0]
    else { return nil }
    buffer.frameLength = totalFrames

    let toneFrames = Int(Self.toneSeconds * rate)
    let twoPi = 2 * Double.pi
    for i in 0..<Int(totalFrames) {
      guard i < toneFrames else {
        samples[i] = 0
        continue
      }
      let t = Double(i) / rate
      let window = sin(Double.pi * Double(i) / Double(toneFrames))
      let tone = 0.7 * sin(twoPi * pulse.frequency * t) + 0.3 * sin(twoPi * pulse.frequency * 1.5 * t)
      samples[i] = Float(0.8 * tone * window * window)
    }
    return buffer
  }

  /// Wraps an angle to -180...180.
  private static func normalize(_ degrees: Double) -> Double {
    var d = degrees.truncatingRemainder(dividingBy: 360)
    if d > 180 { d -= 360 }
    if d < -180 { d += 360 }
    return d
  }
}
