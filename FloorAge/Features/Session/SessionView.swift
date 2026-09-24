import SwiftUI

struct SessionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine: SessionEngine
    @State private var speed = 1.0
    @State private var startedAt = Date()
    @State private var finishedAt: Date?
    @State private var coachShown = false
    @State private var repPulse = false
    /// What the session changed in each exercise family's level, for the summary.
    @State private var changes: [String: Progression.Change] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var watch = WatchLink.shared
    private let items: [PlanItem]
    /// Screenshots only: open straight into rest or the summary.
    private let demoPhase: SessionEngine.Phase?

    init(items: [PlanItem], voice: VoiceCoach, demoPhase: SessionEngine.Phase? = nil) {
        self.items = items
        self.demoPhase = demoPhase
        _engine = StateObject(wrappedValue: SessionEngine(items: items, voice: voice))
    }

    var body: some View {
        content
            .modifier(SessionFeedback(engine: engine, speed: speed, repPulse: $repPulse, reduceMotion: reduceMotion))
            .onAppear {
                startedAt = Date()
                engine.start()
                #if DEBUG
                if let demoPhase { engine.showDemo(demoPhase) }
                #endif
                withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .spring(duration: 0.4)) { coachShown = true }
            }
            .modifier(WatchRemote(engine: engine, watch: watch, status: { watchStatus }))
            .onDisappear { engine.end() }
            .onChange(of: engine.phase) { _, phase in
                guard phase == .done else { return }
                finishedAt = Date()
                model.completeSession()
                changes = model.logSession(engine.familyResults)
                logActivity()
                Task { await model.refreshReminders() }
                saveToHealth()
            }
    }

    /// The coached session, then the full-screen summary once it's done.
    private var content: some View {
        Group {
            if engine.phase == .done {
                SessionSummaryView(minutes: minutes, reps: engine.totalReps, practised: engine.practised,
                                   streak: model.streak(), results: engine.familyResults, changes: changes) { dismiss() }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
            } else {
                screen
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.25) : .spring(duration: 0.45), value: engine.phase == .done)
    }

    private var screen: some View {
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
                                .foregroundStyle(.primary)
                                .padding(.horizontal, Space.xl)
                                .padding(.vertical, Space.m)
                                // Glass with a thin brand edge. The tint under the material keeps the
                                // text above 4.5:1 whatever is behind it.
                                .background(.ultraThinMaterial, in: Capsule())
                                .background(Color(.systemBackground).opacity(0.45), in: Capsule())
                                .overlay(Capsule().strokeBorder(Feature.floorAge.gradient, lineWidth: 1.5))
                                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                                .accessibilityAddTraits(.updatesFrequently)
                                .padding(.bottom, Space.xl)
                                .transition(.scale.combined(with: .opacity))
                                .id(cue)
                        }
                    }
                    .animation(.spring(duration: 0.35), value: engine.cueText)
                if engine.phase == .active || engine.phase == .rest {
                    counter.padding(Space.l)
                }
            }
            controls
        }
        .background(AppBackground())
    }

    private var minutes: Int {
        max(1, Int(((finishedAt ?? Date()).timeIntervalSince(startedAt) / 60).rounded()))
    }

    /// Counts the session towards the week's strength and balance dials.
    private func logActivity() {
        let areas = Set(engine.practised.flatMap(\.exercise.areas))
        var kinds: [ActivityRecord.Kind] = []
        if !areas.isDisjoint(with: [.legs, .floor]) { kinds.append(.strength) }
        if areas.contains(.balance) { kinds.append(.balance) }
        guard !kinds.isEmpty else { return }
        model.logActivity(ActivityRecord(date: Date(), minutes: minutes, kinds: kinds))
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
        .padding(.horizontal, Space.s)
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

    /// The ring fills with each set, in the colours of the area being trained (the next one's
    /// during rest).
    private var counter: some View {
        let feature = engine.current?.exercise.feature ?? .plan
        return ZStack {
            Circle().stroke(feature.tint.opacity(0.2), lineWidth: 8)
            Circle()
                .trim(from: 0, to: engine.phase == .rest ? engine.secondsLeft / engine.restLength : engine.progress)
                .stroke(AngularGradient(colors: feature.colors + [feature.colors[0]], center: .center),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: feature.tint.opacity(0.45), radius: 4)
                .animation(.linear(duration: 0.1), value: engine.progress)
            VStack(spacing: 0) {
                Text(counterValue)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.25), value: counterValue)
                    .scaleEffect(repPulse ? 1.14 : 1)
                Text(counterUnit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(width: 104, height: 104)
        .background(.ultraThinMaterial, in: Circle())
    }

    private var watchStatus: SessionStatus {
        SessionStatus(exercise: title,
                      detail: engine.phase == .done ? String(localized: "Done") : "\(counterValue) \(counterUnit)",
                      progress: engine.phase == .rest ? engine.secondsLeft / engine.restLength : engine.progress,
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
        VStack(spacing: Space.m) {
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
                HStack(spacing: Space.m) {
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
                HStack(spacing: Space.m) {
                    Button(engine.isPaused ? "Resume" : "Pause") { engine.togglePause() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                    Button("Skip") { engine.skip() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
            case .rest:
                if let item = engine.current {
                    NextUpCard(item: item) { engine.skip() }
                }
            case .done:
                // The summary replaces the whole screen.
                EmptyView()
            }
        }
        .padding(Space.l)
    }
}

/// Haptics and the rep counter's pulse.
private struct SessionFeedback: ViewModifier {
    @ObservedObject var engine: SessionEngine
    let speed: Double
    @Binding var repPulse: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            // A tap for every counted rep, success when an exercise or the session ends.
            .sensoryFeedback(.increase, trigger: engine.repsDone) { (old: Int, new: Int) -> Bool in new > old }
            .sensoryFeedback(.success, trigger: engine.phase) { (_: SessionEngine.Phase, new: SessionEngine.Phase) -> Bool in
                new == .rest || new == .done
            }
            .sensoryFeedback(.selection, trigger: speed)
            .onChange(of: engine.repsDone) { (old: Int, new: Int) in
                guard new > old, !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.1)) { repPulse = true }
                withAnimation(.easeIn(duration: 0.2).delay(0.1)) { repPulse = false }
            }
    }
}

/// The Apple Watch remote: shows what's playing, and takes its pause and skip taps.
private struct WatchRemote: ViewModifier {
    @ObservedObject var engine: SessionEngine
    @ObservedObject var watch: WatchLink
    let status: () -> SessionStatus

    func body(content: Content) -> some View {
        content
            .onReceive(engine.objectWillChange.receive(on: RunLoop.main)) { _ in watch.send(status()) }
            .onDisappear { watch.send(nil as SessionStatus?) }
            .onChange(of: watch.command?.1) {
                switch watch.command?.0 {
                case .pause: if engine.phase == .active || engine.phase == .rest { engine.togglePause() }
                case .skip: if engine.phase == .intro { engine.beginActive() } else if engine.phase != .done { engine.skip() }
                case nil: break
                }
            }
    }
}
