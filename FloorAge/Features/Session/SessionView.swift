import SwiftUI

struct SessionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine: SessionEngine
    @State private var speed = 1.0
    @State private var startedAt = Date()
    @State private var coachShown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var watch = WatchLink.shared
    private let items: [PlanItem]

    init(items: [PlanItem], voice: VoiceCoach) {
        self.items = items
        _engine = StateObject(wrappedValue: SessionEngine(items: items, voice: voice))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack(alignment: .topTrailing) {
                AvatarView(controller: engine.avatar)
                    .ignoresSafeArea(edges: .horizontal)
                    // The coach (with its shadow) steps in rather than popping up.
                    .opacity(coachShown ? 1 : 0)
                    .scaleEffect(coachShown || reduceMotion ? 1 : 0.96)
                    .overlay(alignment: .bottom) {
                        if let cue = engine.cueText, engine.phase == .intro || engine.phase == .active {
                            Text(cue)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 12)
                                .background(Color.accentColor.gradient, in: Capsule())
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                                .padding(.bottom, 20)
                                .transition(.scale.combined(with: .opacity))
                                .id(cue)
                        }
                    }
                    .animation(.spring(duration: 0.35), value: engine.cueText)
                if engine.phase == .active || engine.phase == .rest {
                    counter.padding(16)
                }
            }
            controls
        }
        .background(AppBackground())
        .onAppear {
            startedAt = Date()
            engine.start()
            withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .spring(duration: 0.4)) { coachShown = true }
        }
        // The Apple Watch remote: show what's playing, and take its pause and skip taps.
        .onReceive(engine.objectWillChange.receive(on: RunLoop.main)) { _ in watch.send(watchStatus) }
        .onDisappear { watch.send(nil as SessionStatus?) }
        .onChange(of: watch.command?.1) {
            switch watch.command?.0 {
            case .pause: if engine.phase == .active || engine.phase == .rest { engine.togglePause() }
            case .skip: if engine.phase == .intro { engine.beginActive() } else if engine.phase != .done { engine.skip() }
            case nil: break
            }
        }
        .onDisappear { engine.end() }
        .onChange(of: engine.phase) { _, phase in
            guard phase == .done else { return }
            model.completeSession()
            Task { await model.refreshReminders() }
            saveToHealth()
        }
    }

    /// Records the finished session as a workout in Apple Health, if that's switched on.
    private func saveToHealth() {
        guard model.isOwner else { return }
        let end = Date()
        let kegelsOnly = items.allSatisfy { $0.exercise.id == "kegel" }
        let met = kegelsOnly ? Calories.MET.pelvicFloor : Calories.MET.session
        let kcal = Calories.burned(met: met, weightKg: model.profile?.weightKg ?? 70, minutes: end.timeIntervalSince(startedAt) / 60)
        let start = startedAt
        Task { await AppleHealth.saveWorkout(kegelsOnly ? .mindAndBody : .functionalStrengthTraining, start: start, end: end, kcal: kcal) }
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
            MusicButton()
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
        case .done: String(localized: "Session complete")
        case .rest: String(localized: "Rest")
        default: engine.current?.exercise.name ?? ""
        }
    }

    private var subtitle: String {
        guard engine.phase != .done else { return String(localized: "\(engine.items.count) exercises") }
        let position = String(localized: "\(engine.index + 1) of \(engine.items.count)")
        if engine.phase == .rest, let item = engine.current { return String(localized: "Next: \(item.exercise.name) · \(item.amountLabel)") }
        return String(localized: "\(position) · \(engine.current?.amountLabel ?? "")")
    }

    private var counter: some View {
        ZStack {
            Circle().stroke(Color.accentColor.opacity(0.2), lineWidth: 8)
            Circle()
                .trim(from: 0, to: engine.phase == .rest ? engine.secondsLeft / engine.restSeconds : engine.progress)
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

    private var watchStatus: SessionStatus {
        SessionStatus(exercise: title,
                      detail: engine.phase == .done ? String(localized: "Done") : "\(counterValue) \(counterUnit)",
                      progress: engine.phase == .rest ? engine.secondsLeft / engine.restSeconds : engine.progress,
                      step: subtitle,
                      isPaused: engine.isPaused,
                      isResting: engine.phase == .rest,
                      isDone: engine.phase == .done)
    }

    private var counterValue: String {
        if engine.phase == .active, let reps = engine.current?.reps { return "\(engine.repsDone)/\(reps)" }
        return "\(Int(engine.secondsLeft.rounded(.up)))"
    }

    private var counterUnit: String {
        if engine.phase == .active, engine.current?.reps != nil { return String(localized: "reps") }
        return String(localized: "sec")
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
                if let exercise = engine.current?.exercise {
                    DemoVideoButton(exercise: exercise) { engine.stopTalking() }
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
