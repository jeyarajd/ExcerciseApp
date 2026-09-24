import SwiftUI
import UIKit

/// Opens the person's own music app from a workout. Their music keeps playing when they come
/// back, and the coach's voice lowers it while speaking (see `VoiceCoach`).
struct MusicButton: View {
    /// URL schemes must also be listed under LSApplicationQueriesSchemes in project.yml.
    private static let apps: [(name: String, url: String)] = [
        ("Apple Music", "music://"),
        ("Spotify", "spotify://"),
        ("YouTube Music", "youtubemusic://"),
        ("JioSaavn", "jiosaavn://"),
        ("Gaana", "gaana://"),
    ]

    private var installed: [(name: String, url: URL)] {
        Self.apps.compactMap { app in
            guard let url = URL(string: app.url), UIApplication.shared.canOpenURL(url) else { return nil }
            return (app.name, url)
        }
    }

    var body: some View {
        Menu {
            Section("Play your music") {
                ForEach(installed, id: \.name) { app in
                    Button(app.name) { UIApplication.shared.open(app.url) }
                }
            }
            if installed.isEmpty {
                Text("No music app found")
            }
        } label: {
            Image(systemName: "music.note")
                .font(.headline)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Music")
    }
}
