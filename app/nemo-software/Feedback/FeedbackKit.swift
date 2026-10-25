//  FeedbackKit.swift
//  nemo-software
//
//  The only place that makes sound, speech or vibration. Guidance code emits
//  semantic events; FeedbackKit plays each one on the channels the rider switched on
//  in their profile. Never call AVSpeechSynthesizer or Core Haptics from guidance code.
//

import Foundation
import AVFoundation

/// What happened, not how to present it.
public enum FeedbackEvent: Sendable {
    case direction(offsetDegrees: Double)
    case distance(meters: Double)
    case bearingLock
    case landmark(phrase: String)
    case buildingConfirmed(text: String)
    case doorDetected(offsetDegrees: Double, meters: Double)
    case warning(String)
    case lost
    case arrival
    // No free-text case on purpose: every spoken phrase is written in SpeechChannel so the
    // certainty-word test (SAFE-1) can check all of them.
}

/// One output: speech, spatial beacon, haptics, earcons, Apple Watch.
public protocol FeedbackChannel: AnyObject {
    var name: String { get }
    func play(_ event: FeedbackEvent)
    func stop()
}

public final class FeedbackKit {
    private var channels: [FeedbackChannel]
    
    public init(channels: [FeedbackChannel]) {
        self.channels = channels
    }
    
    public func emit(_ event: FeedbackEvent) {
        // TODO (FE-6/FE-7): route by the rider's FeedbackProfile (which channels are on,
        // per-event overrides, verbosity). Critical events (.warning, .lost, .arrival) go
        // to at least 2 channels by default.
        channels.forEach { $0.play(event) }
    }
    
    /// Stop everything immediately (magic tap / Back Tap "stop").
    public func stopAll() {
        channels.forEach { $0.stop() }
    }
}

/// Speech channel built on the existing `Speaker`.
public final class SpeechChannel: FeedbackChannel {
    public let name = "speech"
    private let speaker: Speaker
    private var lastPhrase = ""
    private var lastSpokenAt = Date.distantPast
    private let minRepeatInterval: TimeInterval = 4
    
    public init(speaker: Speaker) {
        self.speaker = speaker
    }
    
    public func play(_ event: FeedbackEvent) {
        let phrase = phrase(for: event)
        // Critical events bypass the chatter guard (warning is never suppressed
        switch event{
        case .warning, .lost, .arrival:
            speaker.speak(phrase)
            return
        default:
            break
        }
        
        // Chatter guard + speak(ONLY IF it's a new phrase OR 4s+ since the last one)
        let now = Date()
        guard phrase != lastPhrase || now.timeIntervalSince(lastSpokenAt) >= minRepeatInterval else {return}
        lastPhrase = phrase
        lastSpokenAt = now
        speaker.speak(phrase)
    }
    
    // Maps event to fixed, reviewed phrase
    func phrase(for event: FeedbackEvent) -> String{
        // Picking the phrase
        switch event {
        case .warning(let message):
            return message
        case .lost:
            return "I've lost the door. Stop and scan slowly."
        case .arrival:
            return "The door should be right in front of you. Feel for the handle."
        case .direction(let offset):
            return directionName(offset)
        case .distance(let meters):
            return "About \(feet(fromMeters: meters)) feet"
        case .bearingLock:
            return "Locked on"
        case .landmark(let landmarkPhrase):
            return landmarkPhrase
        case .buildingConfirmed(let text):
            return "That looks like your building. I see \(text)"
        case .doorDetected(let offset, let meters):
            return "Door \(directionName(offset).lowercased()), \(feet(fromMeters: meters)) feet"
        }
    }
        
    
    // Produces directionName based on angle degree
    private func directionName(_ offset: Double) -> String{
        switch abs(offset) {
        case 0..<8: return "Ahead"
        case 8..<20: return offset < 0 ? "Slightly left" : "Slightly right"
        default: return offset < 0 ? "Left" : "Right"
        }
    }
    
    // Converts meters to rounded feet
    private func feet(fromMeters meters: Double) -> Int{
        Int ((meters * 3.28084 / 5).rounded()) * 5
    }
    public func stop() { speaker.stop() }
}

// Directional audio beacon: a tone that sounds like it sits at the door's position in space(HRTF spatialization on stereo headphones)
public final class BeaconChannel: FeedbackChannel {
    public let name = "beacon"
    
    private let engine = AVAudioEngine() // wires node to output
    private let environment = AVAudioEnvironmentNode() // gives sound a 3D position
    private let player = AVAudioPlayerNode() // plays looping tone
    private var buffer: AVAudioPCMBuffer?
    
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
            z: Float(-cos(radians)) * distance        )
    }
    
    public func play(_ event: FeedbackEvent) {
        switch event {
        case .direction(let offset), .doorDetected(let offset, _):
            updateTarget(relativeAngleDegrees: offset)   // aim the tone at the angle
            startTone()                                   // make sure it's playing
        case .bearingLock:
            startTone()                                   // locked on — keep ticking
        case .arrival, .lost:
            stop()                                        // no valid target → silence
        default:
            break                                         // speech/haptics own the rest
        }
        }
    // Wires audio graph: player - environment - mixer - speakers
    private func setupGraph() {
        guard let buffer = makeBeaconBuffer() else { return }
        self.buffer = buffer
        
        engine.attach(player) //plug player into engine
        engine.attach(environment) //plug 3d node into engine
        engine.connect(player, to: environment, format: buffer.format) // player feed 3d node
        engine.connect(environment, to: engine.mainMixerNode, format: nil) // 3d node feeds output
    }
    
    // Start engine, loop tone
    private func startTone() {
        guard let buffer else { return } // do nothing if setup failed
        if !engine.isRunning {
            engine.prepare()
            try? engine.start()
        }
        if !player.isPlaying {
            player.scheduleBuffer(buffer, at: nil, options: .loops) // loop tick
            player.play()
        }
    }
    
    // Generates audio buffer that we loop
    private func makeBeaconBuffer() -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)
        else { return nil}
        let frameCount = AVAudioFrameCount(44100 * 0.5) // 0.5s buffer
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
                let data = buffer.floatChannelData?[0] else { return nil}
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
// TODO (FE-5): HapticsChannel — Core Haptics AHAP patterns (tick, lock, pulse, arrival, warning).
