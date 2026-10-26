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
    
    public func start() {
        try? session.setCategory(
            .playback,
            options: [.mixWithOthers]
        )
        try? session.setActive(true)
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

