//
//  AlbumView.swift
//  Music
//
//  Created by Rasmus Krämer on 06.09.23.
//

import SwiftUI
import AFBaseKit
import AFPlaybackKit

struct AlbumView: View {
    @Environment(\.libraryDataProvider) var dataProvider
    
    let album: Album
    
    @State var tracks = [Track]()
    @State var navbarVisible = false
    @State var imageColors = ImageColors()
    
    var body: some View {
        List {
            Header(album: album, navbarVisible: $navbarVisible, imageColors: $imageColors) { shuffle in
                AudioPlayer.current.startPlayback(tracks: tracks.sorted { $0.index < $1.index }, startIndex: 0, shuffle: shuffle)
            }
            .navigationTitle(album.name)
            .navigationBarTitleDisplayMode(.inline)
            
            TrackList(tracks: tracks, album: album, hideButtons: true)
                .padding(.top, 4)
            
            if let overview = album.overview, overview.trimmingCharacters(in: .whitespacesAndNewlines) != "" {
                Text(overview)
            }
            
            AdditionalAlbums(album: album)
                .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
        .listStyle(.plain)
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        // introspect does not work here
        .modifier(
            ToolbarModifier(album: album, queueTracks: { next in
                AudioPlayer.current.queueTracks(
                    tracks.sorted { $0.index < $1.index },
                    index: next ? 0 : AudioPlayer.current.queue.count)
            }, navbarVisible: $navbarVisible, imageColors: $imageColors)
        )
        .modifier(NowPlayingBarSafeAreaModifier())
        .task {
            if let tracks = try? await dataProvider.getAlbumTracks(id: album.id) {
                self.tracks = tracks
            }
        }
        .onAppear {
            Task.detached {
                if let imageColors = await ImageColors.getImageColors(cover: album.cover) {
                    withAnimation {
                        self.imageColors = imageColors
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AlbumView(album: Album.fixture, tracks: [
            Track.fixture,
            Track.fixture,
            Track.fixture,
            Track.fixture,
            Track.fixture,
            Track.fixture,
            Track.fixture,
            Track.fixture,
            Track.fixture,
            Track.fixture,
            Track.fixture,
            Track.fixture,
            Track.fixture,
            Track.fixture,
            Track.fixture,
        ])
    }
}
