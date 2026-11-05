import MediaPlayer
import SwiftUI
import UIKit

struct AppleMusicPlaylistSummary: Identifiable, Equatable {
    let id: MPMediaEntityPersistentID
    let title: String
}

final class AppleMusicController: NSObject, ObservableObject {
    static let shared = AppleMusicController()

    @Published private(set) var title = "Apple Music"
    @Published private(set) var artist = "Keine Wiedergabe"
    @Published private(set) var isPlaying = false
    @Published private(set) var authorizationStatus = MPMediaLibrary.authorizationStatus()
    @Published private(set) var playlists: [AppleMusicPlaylistSummary] = []

    private let player = MPMusicPlayerController.systemMusicPlayer

    private override init() {
        super.init()
        player.beginGeneratingPlaybackNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerStateChanged),
            name: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: player
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerStateChanged),
            name: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: player
        )
        refresh()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        player.endGeneratingPlaybackNotifications()
    }

    var hasAccess: Bool { authorizationStatus == .authorized }

    var accessButtonTitle: String {
        switch authorizationStatus {
        case .denied, .restricted: "Apple-Music-Zugriff in Einstellungen öffnen"
        default: "Apple Music verbinden"
        }
    }

    func requestAccess() {
        switch authorizationStatus {
        case .denied, .restricted:
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        case .authorized:
            refresh()
        case .notDetermined:
            MPMediaLibrary.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    self?.authorizationStatus = status
                    self?.refresh()
                }
            }
        @unknown default:
            break
        }
    }

    func togglePlayback() {
        guard hasAccess else { return }
        if player.playbackState == .playing {
            player.pause()
        } else {
            player.play()
        }
        refresh()
    }

    func previous() {
        guard hasAccess else { return }
        player.skipToPreviousItem()
    }

    func next() {
        guard hasAccess else { return }
        player.skipToNextItem()
    }

    func refresh() {
        authorizationStatus = MPMediaLibrary.authorizationStatus()
        isPlaying = player.playbackState == .playing
        title = player.nowPlayingItem?.title ?? "Apple Music"
        artist = player.nowPlayingItem?.artist ?? (isPlaying ? "Wiedergabe läuft" : "Keine Wiedergabe")
        if hasAccess, playlists.isEmpty {
            refreshPlaylists()
        }
    }

    func refreshPlaylists() {
        guard hasAccess else {
            playlists = []
            return
        }
        playlists = (MPMediaQuery.playlists().collections ?? [])
            .compactMap { $0 as? MPMediaPlaylist }
            .map {
                AppleMusicPlaylistSummary(
                    id: $0.persistentID,
                    title: $0.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                        .nonEmpty ?? "Unbenannte Playlist"
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func playPlaylist(_ summary: AppleMusicPlaylistSummary) {
        guard hasAccess,
              let playlist = (MPMediaQuery.playlists().collections ?? [])
                .compactMap({ $0 as? MPMediaPlaylist })
                .first(where: { $0.persistentID == summary.id }) else { return }
        player.setQueue(with: playlist)
        player.play()
        refresh()
    }

    @objc private func playerStateChanged() {
        refresh()
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

struct AppleMusicRideFlyout: View {
    @ObservedObject private var music = AppleMusicController.shared
    let openLibrary: () -> Void
    let close: () -> Void

    private var railWidth: CGFloat {
        min(64, max(52, UIScreen.main.bounds.width * 0.15))
    }

    var body: some View {
        VStack(spacing: 0) {
            flyoutButton("xmark", label: "Musiksteuerung schließen", action: close)
            if music.hasAccess {
                flyoutButton("backward.fill", label: "Vorheriger Titel", action: music.previous)
                flyoutButton(
                    music.isPlaying ? "pause.fill" : "play.fill",
                    label: music.isPlaying ? "Musik pausieren" : "Musik abspielen",
                    action: music.togglePlayback
                )
                flyoutButton("forward.fill", label: "Nächster Titel", action: music.next)
            } else {
                flyoutButton("person.badge.key.fill", label: "Apple Music verbinden", action: music.requestAccess)
            }
            Divider().overlay(.white.opacity(0.18))
            flyoutButton("music.note.list", label: "Quelle und Playlists", action: openLibrary)
        }
        .padding(.vertical, 4)
        .frame(width: railWidth)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.62), radius: 8, x: -2, y: 3)
        .onAppear { music.refresh() }
    }

    private func flyoutButton(
        _ systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.orange)
        .accessibilityLabel(label)
    }
}

struct AppleMusicControlsView: View {
    @ObservedObject private var music = AppleMusicController.shared

    var body: some View {
        Group {
            if music.hasAccess {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(music.title)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                        Text(music.artist)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    musicButton("backward.fill", label: "Vorheriger Titel", action: music.previous)
                    musicButton(music.isPlaying ? "pause.fill" : "play.fill",
                                label: music.isPlaying ? "Musik pausieren" : "Musik abspielen",
                                action: music.togglePlayback)
                    musicButton("forward.fill", label: "Nächster Titel", action: music.next)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 50)
                .background(.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.2)))
            } else {
                Button(music.accessButtonTitle) {
                    music.requestAccess()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .frame(maxWidth: .infinity, minHeight: 50)
            }
        }
        .onAppear { music.refresh() }
    }

    private func musicButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.headline.weight(.bold))
                .frame(width: 42, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.orange)
        .accessibilityLabel(label)
    }
}

struct AppleMusicSettingsView: View {
    @ObservedObject private var music = AppleMusicController.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Music")
                    .font(.subheadline.weight(.semibold))
                Text(music.hasAccess ? "Verbunden" : "Noch nicht verbunden")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !music.hasAccess {
                Button(music.accessButtonTitle) {
                    music.requestAccess()
                }
                .font(.caption.weight(.semibold))
            }
        }
        .onAppear { music.refresh() }
    }
}

struct AppleMusicPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var music = AppleMusicController.shared

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label("Quelle & Playlists", systemImage: "music.note.list")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.orange)
                Spacer()
                Button("Schließen") { dismiss() }
                    .font(.subheadline.weight(.semibold))
            }
            AppleMusicControlsView()
            VStack(alignment: .leading, spacing: 8) {
                Text("QUELLE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                sourceRow("Apple Music", detail: music.hasAccess ? "Aktiv" : "Freigabe nötig", active: true)
                sourceRow("Spotify", detail: "Developer-App nötig", active: false)
                sourceRow("Amazon Music", detail: "Keine öffentliche iOS-API", active: false)
                sourceRow("Dateien / iCloud", detail: "Eigener Player geplant", active: false)
            }
            if music.hasAccess {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("PLAYLISTS")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Aktualisieren") { music.refreshPlaylists() }
                            .font(.caption.weight(.semibold))
                    }
                    if music.playlists.isEmpty {
                        Text("Keine Playlists in der freigegebenen Mediathek gefunden.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(music.playlists) { playlist in
                                    Button {
                                        music.playPlaylist(playlist)
                                    } label: {
                                        HStack {
                                            Image(systemName: "music.note.list")
                                                .foregroundStyle(.orange)
                                            Text(playlist.title)
                                                .lineLimit(1)
                                            Spacer()
                                            Image(systemName: "play.fill")
                                                .foregroundStyle(.orange)
                                        }
                                        .padding(.horizontal, 12)
                                        .frame(minHeight: 46)
                                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .onAppear {
            music.refresh()
            music.refreshPlaylists()
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func sourceRow(_ name: String, detail: String, active: Bool) -> some View {
        HStack {
            Image(systemName: active ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(active ? .orange : .secondary)
            Text(name)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 42)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
    }
}
