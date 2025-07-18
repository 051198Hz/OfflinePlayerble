//
//  ContentView.swift
//  YNMusicPlayer
//
//  Created by Yune gim on 6/11/25.
//

import SwiftUI
import FileProvider
import OSLog

struct ContentView: View {
    let logger = Logger()
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    @State private var youtubeViewToggle = false
    @State private var isExpanded = false
    @State var playerUUID: UUID = UUID()
    
    @Bindable var audioPlayer: AudioPlayer
    @Bindable var assetStore: MusicAssetStore
    
    var miniPlayerHeight: CGFloat {
        verticalSizeClass == .compact ? 60 : 100
    }
    
    init(store: MusicAssetStore) {
        self.assetStore = store
        self.audioPlayer = AudioPlayer(store: store)
    }
    
    var body: some View {
        ZStack {
            NavigationStack {
                VStack {
                    list
                    player
                }
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu("더보기", systemImage: "ellipsis.circle") {
                            Button("공유", systemImage: "square.and.arrow.up", action: { })
                            Button("유튜브 재생", systemImage: "play.circle.fill", role: .destructive) {
                                youtubeViewToggle.toggle()
                            }

                            EditButton()
                        }
                    }
                    ToolbarItem {
                        FileImportView(
                            allowedTypes: [.audio],
                            title: "add"
                        ) { urls in
                            urls.forEach { url in
                                guard url.startAccessingSecurityScopedResource() else { return }
                                Task {
                                    await assetStore.addMusic(url: url)
                                    url.stopAccessingSecurityScopedResource()
                                }
                            }
                        }
                    }
                }
                
            }
        }
        .sheet(isPresented: $youtubeViewToggle) {
            YoutubeDownloadView(store: assetStore, player: audioPlayer)
        }
    }
    
    var list: some View {
        List {
            ForEach(assetStore.musics) { music in
                MusicRowView(asset: music)
                    .listRowBackground(assetStore.checkSet(music) ? Color.blue.opacity(0.4) : Color.gray.opacity(0.1))
                    .onTapGesture {
                        if assetStore.checkSet(music) {
                            isExpanded = true
                        } else {
                            Task {
                                assetStore.selectedMusic = music.fileName
                                assetStore.selectedMusicAsset = music
                                logger.debug("선택된 항목: \(music.originalName)")
                                await audioPlayer.set(music)
                            }
                        }
                    }
            }
            .onDelete(perform: deleteItems)
        }
    }
    
    var player: some View {
        MiniPlayerView(audioPlayer: audioPlayer)
            .frame(height: 60)
            .shadow(radius: 2)
            .padding(.bottom, 20)
            .onTapGesture {
                withAnimation {
                    isExpanded.toggle()
                }
            }
            .sheet(isPresented: $isExpanded) {
                AudioPlayerView(audioPlayer: audioPlayer)
                    .padding(.bottom, 10)
                    .presentationDetents([.fraction(0.5)])
            }
    }
    
    private func deleteItems(offsets: IndexSet) {
        Task {
            await assetStore.deleteMusic(offsets: offsets)
        }
    }
    
    private func play(_ music: Music) async {
        assetStore.selectedMusic = music.fileName
        assetStore.selectedMusicAsset = music
        logger.debug("선택된 항목: \(music.originalName)")
        await audioPlayer.set(music)
    }
}

//#Preview {
//    ContentView(store: MusicAssetStore.shared)
//}
