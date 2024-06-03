//
//  File.swift
//  
//
//  Created by Rasmus Krämer on 19.03.24.
//

import Foundation
import MediaPlayer

internal extension LocalAudioEndpoint {
    func setupTimeObserver() {
        audioPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 1000), queue: nil) { [unowned self] _ in
            updateNowPlayingStatus()
            updatePlaybackReporter(scheduled: true)
            
            _playing = audioPlayer.rate > 0
            
            // Only check isPlaybackLikelyToKeepUp will not be enough because this value will return false
            // when the buffer is full and the playback time is not able to statisically predict if the playback can keepup
            // When curren item is not even playing, checking buffering will cause false positives
            if let playItem = audioPlayer.currentItem, _playing{
                // We have to check buffer empty first becaue Apple thinks it is valid to have
                // isPlaybackBufferEmpty == true and isPlaybackBufferFull == true at the same time
                if playItem.isPlaybackBufferEmpty {
                    buffering = true
                } else if playItem.isPlaybackLikelyToKeepUp || playItem.isPlaybackBufferFull {
                    buffering = false
                } else {
                    // The buffer has something, not full, but unlikely to keepup
                    // Uncommon for music files, but added for completeness
                    buffering = true
                }
            } else {
                buffering = false
            }
            
            _currentTime = audioPlayer.currentTime().seconds
            duration = audioPlayer.currentItem?.duration.seconds ?? 0
        }
    }
    func setupObservers() {
        // The player is never discarded, so no removing of the observers is necessary
        NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: nil) { [self] _ in
            if repeatMode == .track {
                currentTime = 0
                playing = true
            } else {
                trackDidFinish()
            }
        }
        
        #if !os(macOS)
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: nil) { [self] notification in
            guard let userInfo = notification.userInfo, let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt, let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
            }
            
            switch type {
                case .began:
                    playing = false
                case .ended:
                    guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        playing = true
                    }
                default: ()
            }
        }
        #endif
        
        #if os(iOS)
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [self] _ in
            setNowPlaying(track: nil)
        }
        #endif
    }
}
