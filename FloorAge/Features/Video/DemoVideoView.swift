import AVKit
import SwiftUI

/// Real-person demo clips bundled with the app as `Resources/Videos/demo_<exercise id>.mp4`.
/// They play offline and loop. An exercise without a clip simply shows no video button, so clips
/// can be added one at a time. The 3D coach still leads every session and counts the reps.
enum DemoVideo {
    static func url(for exerciseID: String) -> URL? {
        Bundle.main.url(forResource: "demo_\(exerciseID)", withExtension: "mp4")
    }
}

/// "Watch a real demo" button that opens the exercise's clip. Shows nothing if there is no clip.
struct DemoVideoButton: View {
    let exercise: Exercise
    /// Icon only, for list rows.
    var compact = false
    /// Runs before the video opens, e.g. to stop the voice coach talking over it.
    var onOpen: () -> Void = {}
    @State private var showing = false

    var body: some View {
        if let url = DemoVideo.url(for: exercise.id) {
            Button {
                onOpen()
                showing = true
            } label: {
                if compact {
                    Image(systemName: "play.rectangle.fill")
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 44)
                } else {
                    Label("Watch a real demo", systemImage: "play.rectangle.fill")
                }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Watch a demo video of \(exercise.name)")
            .sheet(isPresented: $showing) {
                DemoVideoSheet(exercise: exercise, url: url)
            }
        }
    }
}

struct DemoVideoSheet: View {
    let exercise: Exercise
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?
    /// Width / height of the clip, so the player fits it without black bars.
    @State private var aspect: CGFloat = 4 / 3

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VideoPlayer(player: player)
                    .aspectRatio(aspect, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: .infinity)
                Text(exercise.intro)
                if let safety = exercise.safety {
                    Label(safety, systemImage: "exclamationmark.shield")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .background(AppBackground())
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            if looper == nil {
                looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            }
            player.play()
        }
        .onDisappear { player.pause() }
        .task {
            guard let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
                  let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) else { return }
            let shown = size.applying(transform)
            if shown.width != 0, shown.height != 0 { aspect = abs(shown.width / shown.height) }
        }
    }
}
