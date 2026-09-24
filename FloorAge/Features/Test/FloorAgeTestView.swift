import SwiftUI

/// Guided Floor Age check: for each test the coach demonstrates, explains, then the person records
/// their result. Tests that aren't safe for the person's limitations are offered as "skip".
struct FloorAgeTestView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var voice: VoiceCoach
    @Environment(\.dismiss) private var dismiss
    @StateObject private var avatar = AvatarController(exerciseID: FloorTest.sitRise.exerciseID)

    @State private var step: Int
    @State private var scores: [String: Double] = [:]
    @State private var result: FloorAgeResult?

    // Sit to rise inputs
    @State private var downSupports = 0
    @State private var upSupports = 0
    @State private var unsteady = false
    // Balance
    @State private var balanceStart: Date?
    @State private var balanceBest: Double?
    @State private var balanceNow: Double = 0
    // Chair stand
    @State private var chairCountdown: Int?
    @State private var chairTask: Task<Void, Never>?
    @State private var chairReps = 12
    @State private var chairDone = false
    // Reach
    @State private var reach: ReachLevel?

    private let tests = FloorTest.allCases

    /// `startStep` 1–4 opens straight at a test (used for screenshots); 0 is the intro.
    init(startStep: Int = 0) {
        _step = State(initialValue: startStep)
    }
    private let tick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    FloorAgeResultView(result: result) { dismiss() }
                } else if step == 0 {
                    intro
                } else {
                    testStep(tests[step - 1])
                }
            }
            .background(AppBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if result == nil { Button("Close") { stopTimers(); voice.stop(); dismiss() } }
                }
            }
        }
        .onAppear {
            if tests.indices.contains(step - 1) { avatar.play(id: tests[step - 1].exerciseID) }
        }
        .onDisappear { stopTimers() }
        .onReceive(tick) { _ in
            if let start = balanceStart {
                balanceNow = min(Date().timeIntervalSince(start), 45)
                if balanceNow >= 45 { stopBalance() }
            }
        }
    }

    // MARK: - Intro

    private var intro: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AvatarView(controller: avatar)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                Text("Your Floor Age check")
                    .font(.largeTitle.bold())
                Text("Four short tests, about 10 minutes. The coach shows each one first. Your result is an estimate of how old your body moves, not a medical test.")
                    .foregroundStyle(.secondary)
                ForEach(tests) { test in
                    Label(test.title, systemImage: test.symbol)
                }
                Label("You'll need: a mat or carpet, a sturdy chair, a wall nearby.", systemImage: "checklist")
                    .font(.callout)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                Button {
                    go(to: 1)
                } label: {
                    Text("Start").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
        .onAppear { voice.say(String(localized: "Let's find your Floor Age. Four short tests. I'll show you each one first."), interrupt: true) }
    }

    // MARK: - Test steps

    private func testStep(_ test: FloorTest) -> some View {
        let unsafe = PlanBuilder.unsafe(for: model.profile?.limitations ?? []).contains(test.exerciseID)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AvatarView(controller: avatar)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                HStack {
                    Text("Test \(step) of \(tests.count)").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    if let exercise = ExerciseLibrary.shared.exercise(test.exerciseID) {
                        DemoVideoButton(exercise: exercise, compact: true) { voice.stop() }
                    }
                    Button {
                        voice.say(test.instructions, interrupt: true)
                    } label: {
                        Label("Hear again", systemImage: "speaker.wave.2")
                    }
                    .font(.subheadline)
                }
                Text(test.title).font(.title.bold())
                Text(test.instructions)
                if unsafe {
                    Label("Based on what you told us, skip this test or do it only if it feels completely safe.", systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                input(for: test)
                HStack {
                    Button("Skip test") { advance(skipping: test) }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button {
                        save(test)
                    } label: {
                        Text(step == tests.count ? "See my Floor Age" : "Next")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave(test))
                }
                .controlSize(.large)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func input(for test: FloorTest) -> some View {
        switch test {
        case .sitRise:
            VStack(alignment: .leading, spacing: 12) {
                Stepper("Supports going down: \(downSupports)", value: $downSupports, in: 0...5)
                Stepper("Supports getting up: \(upSupports)", value: $upSupports, in: 0...5)
                Toggle("I wobbled or lost balance", isOn: $unsteady)
                Text("A support is any hand, knee, forearm or side of the leg touching the floor or a surface.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Score: \(FloorAgeCalculator.sitRiseScore(downSupports: downSupports, upSupports: upSupports, unsteady: unsteady), specifier: "%.1f") / 10")
                    .font(.headline)
            }
        case .balance:
            VStack(spacing: 12) {
                Text(String(format: "%.1f s", balanceStart == nil ? (balanceBest ?? 0) : balanceNow))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                if balanceStart == nil {
                    Button {
                        balanceStart = Date()
                        balanceNow = 0
                        voice.say(String(localized: "Lift your foot. Go."), interrupt: true)
                    } label: {
                        Text(balanceBest == nil ? "Start timer" : "Try again").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                } else {
                    Button(role: .destructive) {
                        stopBalance()
                    } label: {
                        Text("Stop").frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let best = balanceBest {
                    Text("Best: \(best, specifier: "%.1f") s").foregroundStyle(.secondary)
                }
            }
        case .chairStand:
            VStack(spacing: 12) {
                if let countdown = chairCountdown {
                    Text("\(countdown)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                } else if !chairDone {
                    Button {
                        startChairStand()
                    } label: {
                        Text("Start 30-second timer").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                if chairDone {
                    Stepper("Full stands: \(chairReps)", value: $chairReps, in: 0...60)
                        .font(.headline)
                }
            }
        case .reach:
            VStack(spacing: 8) {
                ForEach(ReachLevel.allCases) { level in
                    Button {
                        reach = level
                    } label: {
                        HStack {
                            Text(level.label)
                            Spacer()
                            if reach == level { Image(systemName: "checkmark.circle.fill") }
                        }
                        .padding(12)
                        .background(reach == level ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.regularMaterial),
                                    in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Actions

    private func go(to newStep: Int) {
        stopTimers()
        step = newStep
        guard newStep >= 1, newStep <= tests.count else { return }
        let test = tests[newStep - 1]
        avatar.play(id: test.exerciseID)
        voice.say(String(localized: "\(test.title). \(test.instructions)"), interrupt: true)
    }

    private func canSave(_ test: FloorTest) -> Bool {
        switch test {
        case .sitRise: true
        case .balance: balanceBest != nil && balanceStart == nil
        case .chairStand: chairDone
        case .reach: reach != nil
        }
    }

    private func save(_ test: FloorTest) {
        switch test {
        case .sitRise:
            scores[test.rawValue] = FloorAgeCalculator.sitRiseScore(downSupports: downSupports, upSupports: upSupports, unsteady: unsteady)
        case .balance:
            scores[test.rawValue] = balanceBest
        case .chairStand:
            scores[test.rawValue] = Double(chairReps)
        case .reach:
            scores[test.rawValue] = reach.map { Double($0.rawValue) }
        }
        next()
    }

    private func advance(skipping test: FloorTest) {
        scores[test.rawValue] = nil
        next()
    }

    private func next() {
        if step < tests.count {
            go(to: step + 1)
        } else {
            finish()
        }
    }

    private func finish() {
        guard !scores.isEmpty else {
            voice.stop()
            dismiss()
            return
        }
        let result = FloorAgeResult(age: model.profile?.age ?? 40, scores: scores)
        model.add(result)
        self.result = result
        avatar.play(id: "idle")
        let difference = result.floorAge - result.age
        let summary = difference > 0
            ? String(localized: "Your Floor Age is \(result.floorAge). That's \(difference) years above your age, and we'll work on it together.")
            : String(localized: "Your Floor Age is \(result.floorAge). Brilliant, your body moves younger than your age!")
        voice.say(summary, interrupt: true)
    }

    private func stopBalance() {
        guard let start = balanceStart else { return }
        let held = min(Date().timeIntervalSince(start), 45)
        balanceStart = nil
        balanceBest = max(balanceBest ?? 0, held)
        voice.say(String(localized: "\(Int(held.rounded())) seconds."), interrupt: true)
    }

    /// Stops a running balance timer or chair-stand countdown without recording anything.
    private func stopTimers() {
        balanceStart = nil
        chairTask?.cancel()
        chairTask = nil
        if !chairDone { chairCountdown = nil }
    }

    private func startChairStand() {
        chairCountdown = 3
        voice.say(String(localized: "Arms crossed. Three. Two. One. Go!"), interrupt: true)
        chairTask = Task { @MainActor in
            for n in stride(from: 2, through: 1, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                chairCountdown = n
            }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            avatar.play(id: FloorTest.chairStand.exerciseID)
            for remaining in stride(from: 30, through: 1, by: -1) {
                chairCountdown = remaining
                if remaining == 15 { voice.say(String(localized: "Fifteen seconds.")) }
                if remaining == 5 { voice.say(String(localized: "Five, four, three, two, one.")) }
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
            }
            chairCountdown = nil
            chairDone = true
            voice.say(String(localized: "Stop! How many full stands did you do?"), interrupt: true)
        }
    }
}
