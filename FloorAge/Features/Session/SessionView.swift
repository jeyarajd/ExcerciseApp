import SwiftUI

struct SessionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine: SessionEngine
    @State private var speed = 1.0

    init(items: [PlanItem], voice: VoiceCoach) {
        _engine = StateObject(wrappedValue: SessionEngine(items: items, voice: voice))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack(alignment: .topTrailing) {
                AvatarView(controller: engine.avatar)
                    .ignoresSafeArea(edges: .horizontal)
                if engine.phase == .active || engine.phase == .rest {
                    counter.padding(16)
                }
            }
            controls
        }
        .background(Color(.systemBackground))
        .onAppear { engine.start() }
        .onDisappear { engine.end() }
        .onChange(of: engine.phase) { _, phase in
            if phase == .done { model.completeSession() }
        }
    }

    private var header: some View {
        HStack {
            Button {
                engine.end()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("End session")
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Picker("Speed", selection: $speed) {
                    Text("Slower").tag(0.75)
                    Text("Normal").tag(1.0)
                    Text("Faster").tag(1.25)
                }
            } label: {
                Label("Speed", systemImage: "speedometer").labelStyle(.iconOnly)
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .onChange(of: speed) { _, value in engine.setSpeed(value) }
        }
        .padding(.horizontal, 8)
    }

    private var title: String {
        switch engine.phase {
        case .done: "Session complete"
        case .rest: "Rest"
        default: engine.current?.exercise.name ?? ""
        }
    }

    private var subtitle: String {
        guard engine.phase != .done else { return "\(engine.items.count) exercises" }
        let position = "\(engine.index + 1) of \(engine.items.count)"
        if engine.phase == .rest, let item = engine.current { return "Next: \(item.exercise.name) · \(item.amountLabel)" }
        return "\(position) · \(engine.current?.amountLabel ?? "")"
    }

    private var counter: some View {
        ZStack {
            Circle().stroke(Color.accentColor.opacity(0.2), lineWidth: 8)
            Circle()
                .trim(from: 0, to: engine.phase == .rest ? engine.secondsLeft / 15 : engine.progress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: engine.progress)
            VStack(spacing: 0) {
                Text(counterValue)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(counterUnit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 104, height: 104)
        .background(.ultraThinMaterial, in: Circle())
    }

    private var counterValue: String {
        if engine.phase == .active, let reps = engine.current?.reps { return "\(engine.repsDone)/\(reps)" }
        return "\(Int(engine.secondsLeft.rounded(.up)))"
    }

    private var counterUnit: String {
        if engine.phase == .active, engine.current?.reps != nil { return "reps" }
        return "sec"
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 12) {
            switch engine.phase {
            case .intro:
                if let safety = engine.current?.exercise.safety {
                    Label(safety, systemImage: "exclamationmark.shield")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 12) {
                    Button("Skip") { engine.skip() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    Button {
                        engine.beginActive()
                    } label: {
                        Text("I'm ready").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            case .active:
                HStack(spacing: 12) {
                    Button(engine.isPaused ? "Resume" : "Pause") { engine.togglePause() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                    Button("Skip") { engine.skip() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
            case .rest:
                Button {
                    engine.skip()
                } label: {
                    Text("Skip rest").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            case .done:
                Text("You moved today. That's what counts.")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Button {
                    dismiss()
                } label: {
                    Text("Finish").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(16)
    }
}
