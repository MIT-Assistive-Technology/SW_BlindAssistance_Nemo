//  AudioSession.swift
//  nemo-software
//
//  The one owner of the audio session (FE-8). Speech and the beacon say when they start
//  and stop; nothing else calls setCategory or setActive.
//

import Foundation
#if os(iOS)
import AVFoundation

public final class AudioSessionManager {
    public static let shared = AudioSessionManager()

    private let session = AVAudioSession.sharedInstance()
    private var isSpeaking = false
    private var isBeaconPlaying = false

    public var onInterruption: ((Bool) -> Void)?

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: session
        )
    }

    /// Mixes with the Uber app and the rider's music, and keeps playing with the screen
    /// locked (the `audio` background mode is in app/Info.plist). Nothing is ducked
    /// until a phrase is spoken.
    public func start() {
        apply()
    }

    /// Other audio is ducked only while a phrase is being spoken.
    public func setSpeaking(_ speaking: Bool) {
        guard speaking != isSpeaking else { return }
        isSpeaking = speaking
        apply()
    }

    public func setBeaconPlaying(_ playing: Bool) {
        guard playing != isBeaconPlaying else { return }
        isBeaconPlaying = playing
        apply()
    }

    /// iOS lifts ducking only when the session is deactivated, so the session goes
    /// inactive whenever neither speech nor the beacon needs it.
    private func apply() {
        do {
            try session.setCategory(
                .playback,
                mode: .default,
                options: isSpeaking ? [.mixWithOthers, .duckOthers] : [.mixWithOthers]
            )
            if isSpeaking || isBeaconPlaying {
                try session.setActive(true)
            } else {
                try session.setActive(false, options: .notifyOthersOnDeactivation)
            }
        } catch {
            // Losing audio is bad, but it must not take the app down.
            print("[AudioSession] update failed: \(error.localizedDescription)")
        }
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
            // Without `shouldResume` the session stays inactive until the next phrase or
            // beacon update asks for it.
            let rawOptions = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            if AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume) {
                apply()
            }
            onInterruption?(false)
        default:
            break
        }
    }
}
#endif
