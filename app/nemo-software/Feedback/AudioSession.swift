//
//  AudioSession.swift
//  
//
//  Created by Trish Zheng on 10/26/26.
//

import Foundation
#if os(iOS)
import AVFoundation

public final class AudioSessionManager {
    public static let shared = AudioSessionManager()
    
    private let session = AVAudioSession.sharedInstance()
    
    public var onInterruption: ((Bool) -> Void)?
    
    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: session
        )
    }
    
    /// Spoken audio that ducks music and mixes with the Uber app, and keeps playing with
    /// the screen locked (the `audio` background mode is in app/Info.plist). Settings from
    /// Jing's AppServices, which now calls this instead of setting the session itself.
    public func start() {
        do {
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .mixWithOthers]
            )
            try session.setActive(true)
        } catch {
            // Losing audio is bad, but it must not take the app down on launch.
            print("[AudioSessionManager] audio session setup failed: \(error.localizedDescription)")
        }
    }
    
    public func stop() {
        try? session.setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
    
    @objc private func handleInterruption(
        _ note: Notification
    ) {
        guard let raw = note.userInfo?[
            AVAudioSessionInterruptionTypeKey
        ] as? UInt,
        let type = AVAudioSession.InterruptionType(
            rawValue: raw
        ) else { return }
        
        switch type{
        case .began:
            onInterruption?(true)
        case .ended:
            try? session.setActive(true)
            onInterruption?(false)
        default:
            break
        }
    }
}
#endif

