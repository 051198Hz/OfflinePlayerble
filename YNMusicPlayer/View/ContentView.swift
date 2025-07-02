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
    
    @State private var searchQueryString: String = ""
    
    @State private var youtubeViewToggle = false
    @State private var isExpanded = false
    @State var playerUUID: UUID = UUID()
    @State var musics: [Music] = []
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
            ForEach($musics) { music in
                MusicRowView(asset: music, logger: logger)
                    .listRowBackground(assetStore.checkSet(music.wrappedValue) ? Color.blue.opacity(0.4) : Color.gray.opacity(0.1))
                    .onTapGesture {
                        if assetStore.checkSet(music.wrappedValue) {
                            isExpanded = true
                        } else {
                            Task {
                                assetStore.selectedMusic = music.wrappedValue.fileName
                                assetStore.selectedMusicAsset = music.wrappedValue
                                logger.debug("선택된 항목: \(music.wrappedValue.originalName)")
                                await audioPlayer.set(music.wrappedValue)
                            }
                        }
                    }
            }
            .onDelete(perform: deleteItems)
        }
        .onChange(of: searchQueryString, initial: true) { oldValue, newValue in
            Task.detached(priority: .userInitiated) {
                await search(contains: newValue)
            }
        }
        .searchable(text: $searchQueryString)
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
    
    private func search(contains query: String) async {
        if query.isEmpty {
            await MainActor.run {
                musics = assetStore.musics
            }
            return
        }
        
        do {
            let searchResult = try await self.assetStore.musics.concurrentAsyncFilter { @Sendable music in
                try await MetadataStore.shared.loadIfNeeded(for: music).title.localizedStandardContains(query)
            }
            await MainActor.run {
                musics = searchResult
            }
        } catch {
            logger.error("🔴 검색 실패: \(error)")
        }
    }
}

//#Preview {
//    ContentView(store: MusicAssetStore.shared)
//}

extension Array where Element: Sendable {
    func concurrentAsyncFilter(_ isIncluded: @Sendable @escaping (Element) async throws -> Bool) async throws -> [Element] {
        try await withThrowingTaskGroup(of: (Element?).self) { group in
            for element in self {
                group.addTask {
                    return try await isIncluded(element) ? element : nil
                }
            }
            var result: [Element] = []
            for try await maybeElement in group {
                if let element = maybeElement {
                    result.append(element)
                }
            }
            return result
        }
    }
}
