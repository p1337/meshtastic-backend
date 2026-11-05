import MediaPlayer
import SwiftUI
import UIKit

final class AppleMusicController: NSObject, ObservableObject {
    static let shared = AppleMusicController()

    @Published private(set) var title = "Apple Music"
    @Published private(set) var artist = "Keine Wiedergabe"
    @Published private(set) var isPlaying = false
    @Published private(set) var authorizationStatus = MPMediaLibrary.authorizationStatus()

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
    }

    @objc private func playerStateChanged() {
        refresh()
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

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label("Musik", systemImage: "music.note")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.orange)
                Spacer()
                Button("Schließen") { dismiss() }
                    .font(.subheadline.weight(.semibold))
            }
            AppleMusicControlsView()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .presentationDetents([.height(180), .medium])
        .presentationDragIndicator(.visible)
    }
}
