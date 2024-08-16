//
//  ViewModel.swift
//  Multiplatform
//
//  Created by Rasmus Krämer on 26.07.24.
//

import Foundation
import SwiftUI
import AmpFinKit
import AFPlayback

internal extension NowPlaying {
    @Observable
    class ViewModel {
        // MARK: Presentation
        
        @ObservationIgnored var namespace: Namespace.ID!
        @MainActor var dragOffset: CGFloat
        
        @MainActor private(set) var presented: Bool
        @MainActor var queueTab: QueueTab? = .queue
        @MainActor private(set) var currentTab: NowPlaying.Tab
        
        // MARK: Current presentation state
        
        @MainActor var mediaInfoToggled = false
        @MainActor var addToPlaylistSheetPresented: Bool
        
        // MARK: Sliders
        
        @MainActor var seekDragging: Bool
        @MainActor var volumeDragging: Bool
        @MainActor var controlsDragging: Bool
        
        @MainActor var draggedPercentage = 0.0
        
        // MARK: Background
        
        @MainActor private(set) var colors: [Color]
        @MainActor private(set) var highlights: [Color]
        
        // MARK: Current state
        
        @MainActor private(set) var source: AudioPlayer.PlaybackSource
        @MainActor private(set) var playbackInfo: PlaybackInfo?
        
        @MainActor private(set) var playing: Bool
        
        @MainActor private(set) var duration: Double
        @MainActor private(set) var currentTime: Double
        
        @MainActor private(set) var history: [Track]
        @MainActor private(set) var nowPlaying: Track?
        
        @MainActor private(set) var queue: [Track]
        @MainActor private(set) var infiniteQueue: [Track]?
        
        @MainActor private(set) var buffering: Bool
        
        @MainActor private(set) var shuffled: Bool
        @MainActor private(set) var repeatMode: RepeatMode
        
        @MainActor private(set) var mediaInfo: Track.MediaInfo?
        @MainActor private(set) var outputRoute: AudioPlayer.AudioRoute
        
        @MainActor private(set) var allowQueueLater: Bool
        
        // MARK: Lyrics
        
        @MainActor private(set) var lyrics: Track.Lyrics
        @MainActor private(set) var lyricsFetchFailed: Bool
        
        @MainActor private(set) var activeLineIndex: Int
        
        @MainActor private(set) var scrolling: Bool
        @MainActor private(set) var controlsVisible: Bool
        
        @ObservationIgnored private var scrollTimeout: Task<Void, Error>?
        
        // MARK: Helper
        
        @MainActor private(set) var notifyPlaying: Bool
        @MainActor private(set) var notifyForwards: Bool
        @MainActor private(set) var notifyBackwards: Bool
        
        @ObservationIgnored private var tokens = [Any]()
        
        @MainActor
        init() {
            namespace = nil
            dragOffset = .zero
            
            presented = false
            currentTab = .cover
            
            mediaInfoToggled = false
            addToPlaylistSheetPresented = false
            
            seekDragging = false
            volumeDragging = false
            controlsDragging = false
            
            draggedPercentage = 0
            
            colors = []
            highlights = []
            
            source = AudioPlayer.current.source
            
            playing = AudioPlayer.current.playing
            
            duration = AudioPlayer.current.duration
            currentTime = AudioPlayer.current.currentTime
            
            history = AudioPlayer.current.history
            nowPlaying = AudioPlayer.current.nowPlaying
            queue = AudioPlayer.current.queue
            
            buffering = AudioPlayer.current.buffering
            
            shuffled = AudioPlayer.current.shuffled
            repeatMode = AudioPlayer.current.repeatMode
            
            mediaInfo = nil
            outputRoute = AudioPlayer.current.outputRoute
            
            allowQueueLater = AudioPlayer.current.allowQueueLater
            
            lyrics = [:]
            lyricsFetchFailed = false
            
            activeLineIndex = 0
            
            scrolling = true
            controlsVisible = true
            
            scrollTimeout = nil
            
            notifyPlaying = false
            notifyForwards = false
            notifyBackwards = false
            
            setupObservers()
        }
    }
    
    enum QueueTab: Hashable, Identifiable, Equatable, CaseIterable {
        case history
        case queue
        case infiniteQueue
        
        var id: Self {
            self
        }
    }
}

// MARK: Properties

internal extension NowPlaying.ViewModel {
    @MainActor
    var track: Track? {
        if presented, let track = nowPlaying {
            return track
        }
        
        return nil
    }
    @MainActor
    var addToPlaylistTrack: Track? {
        guard addToPlaylistSheetPresented else {
            return nil
        }
        
        return track
    }
    
    @MainActor
    var showRoundedCorners: Bool {
        dragOffset != 0 || !presented
    }
    
    @MainActor
    var displayedProgress: Double {
        seekDragging ? draggedPercentage : playedPercentage
    }
    @MainActor
    var playedPercentage: Double {
        currentTime / duration
    }
    
    @MainActor
    var qualityText: String? {
        if let mediaInfo = mediaInfo {
            var result = [String]()
            
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            formatter.usesGroupingSeparator = true
            
            if mediaInfoToggled && (mediaInfo.bitDepth != nil || mediaInfo.sampleRate != nil) {
                if let bitDepth = mediaInfo.bitDepth {
                    result.append(formatter.string(from: .init(value: bitDepth))!)
                }
                if let sampleRate = mediaInfo.sampleRate {
                    result.append(formatter.string(from: .init(value: sampleRate))!)
                }
            } else {
                if let codec = mediaInfo.codec {
                    result.append(codec.uppercased())
                }
                if let bitrate = mediaInfo.bitrate {
                    result.append(formatter.string(from: .init(value: bitrate / 1000))!)
                }
            }
            
            if result.isEmpty {
                return nil
            }
            
            return result.joined(separator: " - ")
        }
        
        return nil
    }
    
    @MainActor
    var lyricsKeys: [Double] {
        Array(lyrics.keys).sorted(by: <)
    }
    
    @MainActor
    var lyricsLoaded: Bool {
        !lyrics.isEmpty && !lyricsKeys.isEmpty
    }
}

// MARK: Observers

private extension NowPlaying.ViewModel {
    // This is truly swift the way it was intended to be
    func setupObservers() {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
        
        tokens = []
        
        tokens.append(NotificationCenter.default.addObserver(forName: AudioPlayer.sourceDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor in
                self?.source = AudioPlayer.current.source
            }
        })
        
        tokens.append(NotificationCenter.default.addObserver(forName: AudioPlayer.trackDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
            Task {
                await MainActor.run { [weak self] in
                    if self?.nowPlaying == nil && AudioPlayer.current.nowPlaying != nil {
                        self?.setPresented(true)
                    }
                    
                    self?.nowPlaying = AudioPlayer.current.nowPlaying
                    self?.mediaInfo = nil
                }
                
                await withTaskGroup(of: Void.self) {
                    // MARK: Fetch media info
                    $0.addTask { await self?.updateMediaInfo() }
                    // MARK: extract colors
                    $0.addTask {
                        if let cover = await self?.track?.cover {
                            guard let dominantColors = try? await AFVisuals.extractDominantColors(10, cover: cover) else {
                                await MainActor.run { [weak self] in
                                    self?.colors = []
                                    self?.highlights = []
                                }
                                
                                return
                            }
                            
                            let colors = dominantColors.map { $0.color }
                            let highlights = AFVisuals.determineSaturated(AFVisuals.highPassFilter(colors, threshold: 0.5), threshold: 0.3)
                            
                            await MainActor.run { [colors, highlights, weak self] in
                                withAnimation {
                                    self?.highlights = highlights
                                    self?.colors = colors.filter { !highlights.contains($0) }
                                }
                            }
                        }
                    }
                    // MARK: Fetch Lyrics
                    $0.addTask {
                        await MainActor.run { [weak self] in
                            withAnimation {
                                self?.lyrics = [:]
                            }
                            
                            self?.setActiveLine(0)
                        }
                        
                        let trackId = AudioPlayer.current.nowPlaying?.id
                        
                        await MainActor.run { [weak self] in
                            self?.lyricsFetchFailed = trackId == nil
                        }
                        
                        guard let trackId else {
                            return
                        }
                        
                        var lyrics = try? OfflineManager.shared.lyrics(trackId: trackId, allowUpdate: true)
                        
                        if lyrics == nil {
                            lyrics = try? await JellyfinClient.shared.lyrics(trackId: trackId)
                        }
                        
                        await MainActor.run { [lyrics, weak self] in
                            withAnimation {
                                self?.lyricsFetchFailed = lyrics == nil
                                self?.lyrics = lyrics ?? [:]
                            }
                        }
                        
                        self?.updateLyricsIndex()
                    }
                }
            }
        })
        tokens.append(NotificationCenter.default.addObserver(forName: AudioPlayer.playingDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playing = AudioPlayer.current.playing
                self?.notifyPlaying.toggle()
            }
        })
        
        tokens.append(NotificationCenter.default.addObserver(forName: AudioPlayer.bufferingDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.buffering = AudioPlayer.current.buffering
            }
        })
        tokens.append(NotificationCenter.default.addObserver(forName: AudioPlayer.playbackInfoDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playbackInfo = AudioPlayer.current.playbackInfo
            }
        })
        
        tokens.append(NotificationCenter.default.addObserver(forName: AudioPlayer.timeDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.duration = AudioPlayer.current.duration
                self?.currentTime = AudioPlayer.current.currentTime
                
                self?.updateLyricsIndex()
            }
        })
        tokens.append(NotificationCenter.default.addObserver(forName: AudioPlayer.queueDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.history = AudioPlayer.current.history
                self?.queue = AudioPlayer.current.queue
                self?.infiniteQueue = AudioPlayer.current.infiniteQueue
                
                if self?.queue.isEmpty == true && self?.history.isEmpty == true {
                    self?.queueTab = .queue
                }
                
                withAnimation {
                    self?.shuffled = AudioPlayer.current.shuffled
                    self?.repeatMode = AudioPlayer.current.repeatMode
                }
            }
        })
        tokens.append(NotificationCenter.default.addObserver(forName: AudioPlayer.queueModeDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in
                withAnimation {
                    self?.shuffled = AudioPlayer.current.shuffled
                    self?.repeatMode = AudioPlayer.current.repeatMode
                }
            }
        })
        
        tokens.append(NotificationCenter.default.addObserver(forName: AudioPlayer.bitrateDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateMediaInfo()
            }
        })
        
        tokens.append(NotificationCenter.default.addObserver(forName: AudioPlayer.routeDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.outputRoute = AudioPlayer.current.outputRoute
            }
        })
    }
    func updateMediaInfo() async {
        let mediaInfo = await AudioPlayer.current.mediaInfo
        
        await MainActor.run {
            withAnimation {
                self.mediaInfo = mediaInfo
                self.mediaInfoToggled = mediaInfo?.lossless ?? false
            }
        }
    }
}

// MARK: Setter

internal extension NowPlaying.ViewModel {
    func selectTab(_ tab: NowPlaying.Tab) {
        Task { @MainActor in
            controlsVisible = true
            
            withAnimation(.bouncy) {
                if currentTab == tab {
                    currentTab = .cover
                } else {
                    currentTab = tab
                }
            }
            
            updateLyricsIndex()
            startScrollTimer()
        }
    }
    func setPresented(_ presented: Bool) {
        Task { @MainActor in
            if presented {
                dragOffset = 0
            }
            if currentTab != .lyrics || presented {
                controlsVisible = true
            }
            
            addToPlaylistSheetPresented = false
            
            UIApplication.shared.isIdleTimerDisabled = presented
            
            withTransaction(\.nowPlayingOverlayToggled, true) {
                withAnimation(presented ? .bouncy.delay(0.25) : .bouncy) {
                    self.presented = presented
                }
            }
        }
    }
    
    func setPosition(percentage: Double) {
        Task { @MainActor in
            draggedPercentage = percentage
        }
        
        AudioPlayer.current.currentTime = AudioPlayer.current.duration * percentage
    }
}

// MARK: Lyrics

internal extension NowPlaying.ViewModel {
    @MainActor
    func scroll(_ proxy: ScrollViewProxy, anchor: UnitPoint) {
        if scrolling && !controlsDragging {
            return
        }
        
        withAnimation(.spring) {
            proxy.scrollTo(activeLineIndex, anchor: anchor)
        }
    }
    
    func didInteract() {
        Task { @MainActor in
            guard currentTab == .lyrics && !controlsDragging else {
                return
            }
            
            withAnimation {
                scrolling = true
                controlsVisible = true
            }
        }
        
        startScrollTimer()
    }
    
    func startScrollTimer() {
        scrollTimeout?.cancel()
        scrollTimeout = Task {
            try await Task.sleep(nanoseconds: UInt64(4) * NSEC_PER_SEC)
            try Task.checkCancellation()
            
            guard await controlsDragging == false, await currentTab == .lyrics else {
                return
            }
            
            await MainActor.run {
                withAnimation {
                    controlsVisible = false
                    scrolling = false
                }
            }
        }
    }
    
    func setActiveLine(_ index: Int) {
        Task { @MainActor in
            withAnimation(.spring) {
                activeLineIndex = index
            }
        }
    }
    func updateLyricsIndex() {
        Task { @MainActor in
            guard !lyricsKeys.isEmpty else {
                setActiveLine(0)
                return
            }
            
            let currentTime = AudioPlayer.current.currentTime
            
            if let index = lyricsKeys.lastIndex(where: { $0 <= currentTime }) {
                setActiveLine(index)
            } else {
                setActiveLine(0)
            }
        }
    }
}
