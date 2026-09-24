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
    /// False during the 3-2-1 before the 30 seconds start.
    @State private var chairGo = false
    // Reach
    @State private var reach: ReachLevel?
    /// Once the person picks an answer themselves, the camera stops suggesting one.
    @State private var reachPickedByHand = false
    // Camera scoring (chair stand, balance, reach)
    @StateObject private var camera: PoseCamera
    @State private var useCamera: Bool
    @State private var chairCounter = ChairStandCounter()
    @State private var balanceDetector = BalanceDetector()
    @State private var reachEstimator = ReachEstimator()

    private let tests = FloorTest.allCases

    /// `startStep` 1–4 opens straight at a test (used for screenshots); 0 is the intro.
    /// `demoCamera` plays scripted movement instead of the camera (Debug demo screens).
    init(startStep: Int = 0, demoCamera: PoseCamera.Demo? = nil) {
        _step = State(initialValue: startStep)
        _camera = StateObject(wrappedValue: PoseCamera(demo: demoCamera))
        _useCamera = State(initialValue: demoCamera != nil)
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
            camera.onPose = handle
            if tests.indices.contains(step - 1) {
                avatar.play(id: tests[step - 1].exerciseID)
                updateCamera(for: tests[step - 1])
                if camera.isDemo, tests[step - 1] == .chairStand { startChairStand() }
            }
        }
        .onDisappear {
            stopTimers()
            camera.stop()
        }
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
            VStack(alignment: .leading, spacing: 18) {
                AvatarView(controller: avatar)
                    .frame(height: 290)
                    .background(RadialGradient(colors: [Feature.floorAge.tint.opacity(0.28), .clear],
                                               center: .bottom, startRadius: 10, endRadius: 230))
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Floor Age")
                    Text("Your Floor Age check")
                        .font(.display(.largeTitle))
                    HStack(spacing: 8) {
                        chip("\(tests.count) tests", symbol: "list.number")
                        chip("About 10 min", symbol: "clock")
                    }
                    Text("Four short tests, about 10 minutes. The coach shows each one first. Your result is an estimate of how old your body moves, not a medical test.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }

                VStack(spacing: 10) {
                    ForEach(Array(tests.enumerated()), id: \.element) { index, test in
                        HStack(spacing: 14) {
                            FeatureBadge(feature: test.feature, symbol: test.symbol, size: 46)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(test.title).font(.display(.headline))
                                Text(test.area).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Text(String(format: "%02d", index + 1))
                                .font(.metric(26))
                                .foregroundStyle(test.feature.gradient)
                                .opacity(0.55)
                        }
                        .tintedCard(test.feature, padding: 14)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checklist")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Feature.glance.gradient)
                    Text("You'll need: a mat or carpet, a sturdy chair, a wall nearby.")
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .tintedCard(.glance, padding: 14)

                Button {
                    go(to: 1)
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(GradientButtonStyle(feature: .floorAge))
                .padding(.top, 4)
            }
            .padding()
        }
        .onAppear { voice.say(String(localized: "Let's find your Floor Age. Four short tests. I'll show you each one first."), interrupt: true) }
    }

    private func chip(_ text: LocalizedStringKey, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(Feature.floorAge.colors[1])
            .background(Feature.floorAge.tint.opacity(0.14), in: Capsule())
    }

    // MARK: - Test steps

    private func testStep(_ test: FloorTest) -> some View {
        let unsafe = PlanBuilder.unsafe(for: model.profile?.limitations ?? []).contains(test.exerciseID)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Group {
                    if useCamera, test.usesCamera {
                        CameraStage(camera: camera, feature: test.feature, hint: cameraHint(test))
                            .frame(height: 440)
                    } else {
                        AvatarView(controller: avatar)
                            .frame(height: 280)
                    }
                }
                .background(RadialGradient(colors: [test.feature.tint.opacity(0.28), .clear],
                                           center: .bottom, startRadius: 10, endRadius: 230))
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(alignment: .top) { progressBar.padding(14) }

                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("Test \(step) of \(tests.count)", feature: test.feature)
                    Text(test.title).font(.display(.largeTitle))
                    Label(test.area, systemImage: test.symbol)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Capsule().fill(test.feature.gradient).frame(width: 4)
                        Text(test.instructions).font(.body)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button {
                            voice.say(test.instructions, interrupt: true)
                        } label: {
                            Label("Hear again", systemImage: "speaker.wave.2.fill")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .foregroundStyle(test.feature.colors.last!)
                                .background(test.feature.tint.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        if test.usesCamera {
                            Button {
                                useCamera.toggle()
                                updateCamera(for: test)
                            } label: {
                                Label(useCamera ? "Camera on" : "Use camera", systemImage: useCamera ? "camera.fill" : "camera.viewfinder")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .foregroundStyle(useCamera ? .white : test.feature.colors.last!)
                                    .background(useCamera ? AnyShapeStyle(test.feature.gradient) : AnyShapeStyle(test.feature.tint.opacity(0.14)),
                                                in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        if let exercise = ExerciseLibrary.shared.exercise(test.exerciseID) {
                            DemoVideoButton(exercise: exercise, compact: true) { voice.stop() }
                        }
                    }
                    if test.usesCamera, !useCamera {
                        Text("Tip: prop the phone up 2–3 m away and the camera counts for you. Nothing is recorded.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .tintedCard(test.feature)

                if unsafe {
                    Label("Based on what you told us, skip this test or do it only if it feels completely safe.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color(red: 0.8, green: 0.35, blue: 0.05))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .tintedCard(.steps, padding: 14)
                }

                input(for: test)

                HStack(spacing: 12) {
                    Button("Skip test") { advance(skipping: test) }
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                    Button {
                        save(test)
                    } label: {
                        Label(step == tests.count ? "See my Floor Age" : "Next",
                              systemImage: step == tests.count ? "sparkles" : "arrow.right")
                    }
                    .buttonStyle(GradientButtonStyle(feature: test.feature))
                    .disabled(!canSave(test))
                }
                .padding(.top, 4)
            }
            .padding()
        }
    }

    /// One segment per test, filled up to the current one.
    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(Array(tests.enumerated()), id: \.element) { index, test in
                Capsule()
                    .fill(index < step ? AnyShapeStyle(test.feature.gradient) : AnyShapeStyle(.white.opacity(0.6)))
                    .frame(height: 6)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func input(for test: FloorTest) -> some View {
        switch test {
        case .sitRise:
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    CounterTile(title: "Going down", unit: "supports", value: $downSupports, range: 0...5, feature: test.feature)
                    CounterTile(title: "Getting up", unit: "supports", value: $upSupports, range: 0...5, feature: test.feature)
                }
                Toggle("I wobbled or lost balance", isOn: $unsteady)
                    .tint(test.feature.colors.last!)
                    .font(.body.weight(.medium))
                Text("A support is any hand, knee, forearm or side of the leg touching the floor or a surface.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Score: \(FloorAgeCalculator.sitRiseScore(downSupports: downSupports, upSupports: upSupports, unsteady: unsteady), specifier: "%.1f") / 10")
                    .font(.metric(20))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(test.feature.gradient, in: Capsule())
            }
            .tintedCard(test.feature)
        case .balance:
            let seconds = balanceStart == nil ? (balanceBest ?? 0) : balanceNow
            VStack(spacing: 14) {
                ArcGauge(progress: seconds / 45, lineWidth: 16) {
                    VStack(spacing: 0) {
                        Text(String(format: "%.1f", seconds))
                            .font(.metric(54))
                            .monospacedDigit()
                        Text("seconds").font(.subheadline).opacity(0.85)
                    }
                }
                .frame(maxWidth: 260)
                if balanceStart == nil {
                    Button {
                        balanceStart = Date()
                        balanceNow = 0
                        voice.say(String(localized: "Lift your foot. Go."), interrupt: true)
                    } label: {
                        Label(balanceBest == nil ? "Start timer" : "Try again", systemImage: "timer")
                    }
                    .buttonStyle(OnHeroButtonStyle(feature: test.feature))
                } else {
                    Button {
                        stopBalance()
                    } label: {
                        Label("Stop", systemImage: "stop.fill").frame(minHeight: 36)
                    }
                    .buttonStyle(OnHeroButtonStyle(feature: .steps))
                }
                if let best = balanceBest {
                    Text("Best: \(best, specifier: "%.1f") s").font(.subheadline.weight(.semibold)).opacity(0.9)
                }
                if useCamera, balanceStart == nil {
                    Label("Lift your foot and the timer starts by itself", systemImage: "camera.fill")
                        .font(.footnote.weight(.semibold))
                        .opacity(0.9)
                }
            }
            .frame(maxWidth: .infinity)
            .heroCard(test.feature, symbol: test.symbol, padding: 20)
        case .chairStand:
            VStack(spacing: 14) {
                if let countdown = chairCountdown {
                    ArcGauge(progress: chairGo ? Double(countdown) / 30 : 1, lineWidth: 16) {
                        VStack(spacing: 0) {
                            Text("\(countdown)")
                                .font(.metric(60))
                                .monospacedDigit()
                                .contentTransition(.numericText(countsDown: true))
                                .animation(.snappy, value: countdown)
                            Text(chairGo ? "seconds left" : "Get ready").font(.subheadline).opacity(0.85)
                        }
                    }
                    .frame(maxWidth: 260)
                    if useCamera, chairGo {
                        Label("\(chairCounter.count) stands", systemImage: "camera.fill")
                            .font(.metric(22))
                            .contentTransition(.numericText())
                            .animation(.snappy, value: chairCounter.count)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.2), in: Capsule())
                    }
                } else if !chairDone {
                    Image(systemName: "timer")
                        .font(.system(size: 54, weight: .semibold))
                        .padding(.vertical, 8)
                    Button {
                        startChairStand()
                    } label: {
                        Label("Start 30-second timer", systemImage: "play.fill")
                    }
                    .buttonStyle(OnHeroButtonStyle(feature: test.feature))
                }
                if chairDone {
                    CounterTile(title: "Full stands", unit: nil, value: $chairReps, range: 0...60, feature: test.feature, onHero: true)
                }
            }
            .frame(maxWidth: .infinity)
            .heroCard(test.feature, symbol: test.symbol, padding: 20)
        case .reach:
            VStack(spacing: 10) {
                if useCamera, !reachPickedByHand, reachEstimator.level != nil {
                    Label("Suggested by the camera. Tap another answer if it's not right.", systemImage: "camera.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(test.feature.colors.last!)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(ReachLevel.allCases) { level in
                    let selected = reach == level
                    Button {
                        withAnimation(.snappy) { reach = level }
                        reachPickedByHand = true
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(test.feature.gradient))
                            Text(level.label)
                                .font(.body.weight(selected ? .semibold : .regular))
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            ReachMeter(level: level.rawValue, selected: selected, feature: test.feature)
                        }
                        .foregroundStyle(selected ? .white : .primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(selected ? AnyShapeStyle(test.feature.gradient) : AnyShapeStyle(Color(.systemBackground).opacity(0.8)))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(test.feature.tint.opacity(selected ? 0 : 0.35), lineWidth: 1)
                        }
                        .shadow(color: test.feature.colors.last!.opacity(selected ? 0.35 : 0.08), radius: selected ? 10 : 6, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    // MARK: - Camera

    /// Runs the camera only while it's switched on and the current test can use it.
    private func updateCamera(for test: FloorTest) {
        chairCounter = ChairStandCounter()
        balanceDetector = BalanceDetector()
        if useCamera, test.usesCamera {
            camera.start()
        } else {
            camera.stop()
        }
    }

    private func handle(_ pose: BodyPose) {
        guard useCamera, tests.indices.contains(step - 1), result == nil else { return }
        switch tests[step - 1] {
        case .chairStand:
            if chairGo, chairCountdown != nil, chairCounter.update(pose) {
                chairReps = chairCounter.count
            }
        case .balance:
            switch balanceDetector.update(pose) {
            case .lifted where balanceStart == nil:
                balanceStart = Date()
                balanceNow = 0
            case .down where balanceStart != nil:
                stopBalance()
            default:
                break
            }
        case .reach:
            reachEstimator.update(pose)
            if !reachPickedByHand, let level = reachEstimator.level, level != reach {
                withAnimation(.snappy) { reach = level }
            }
        case .sitRise:
            break
        }
    }

    private func cameraHint(_ test: FloorTest) -> String {
        switch camera.status {
        case .denied: return String(localized: "Camera access is off. Allow it in iPhone Settings › Privacy & Security › Camera.")
        case .unavailable: return String(localized: "This device has no front camera.")
        case .off, .starting: return String(localized: "Starting the camera…")
        case .running: break
        }
        guard let pose = camera.pose else { return String(localized: "Step into view, 2–3 m from the phone") }
        guard pose.legsVisible else { return String(localized: "Step back so your feet are in view") }
        return test == .balance ? String(localized: "Tracking. Face the phone.") : String(localized: "Tracking. Stand side-on to the phone.")
    }

    // MARK: - Actions

    private func go(to newStep: Int) {
        stopTimers()
        step = newStep
        guard newStep >= 1, newStep <= tests.count else {
            camera.stop()
            return
        }
        let test = tests[newStep - 1]
        avatar.play(id: test.exerciseID)
        updateCamera(for: test)
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
        camera.stop()
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
        chairGo = false
        chairCounter = ChairStandCounter()
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
            chairGo = true
            for remaining in stride(from: 30, through: 1, by: -1) {
                chairCountdown = remaining
                if remaining == 15 { voice.say(String(localized: "Fifteen seconds.")) }
                if remaining == 5 { voice.say(String(localized: "Five, four, three, two, one.")) }
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
            }
            chairCountdown = nil
            if useCamera, camera.status == .running { chairReps = chairCounter.count }
            chairDone = true
            voice.say(String(localized: "Stop! How many full stands did you do?"), interrupt: true)
        }
    }
}

extension FloorTest {
    /// Tests the camera can score. Sit to rise is entered by hand: hands and knees touching the
    /// floor are too easy to miss from one camera.
    var usesCamera: Bool { self != .sitRise }

    /// Each test keeps its own colours through the check and on the result.
    var feature: Feature {
        switch self {
        case .sitRise: .floorAge
        case .balance: .bmi
        case .chairStand: .plan
        case .reach: .calories
        }
    }
}

/// A big number with round minus and plus buttons, in place of a plain Stepper.
struct CounterTile: View {
    let title: LocalizedStringKey
    let unit: LocalizedStringKey?
    @Binding var value: Int
    let range: ClosedRange<Int>
    let feature: Feature
    var onHero = false

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).opacity(onHero ? 0.9 : 0.75)
            HStack(spacing: 14) {
                round("minus", enabled: value > range.lowerBound) { value -= 1 }
                Text("\(value)")
                    .font(.metric(40))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: value)
                    .frame(minWidth: 40)
                round("plus", enabled: value < range.upperBound) { value += 1 }
            }
            if let unit {
                Text(unit).font(.caption).opacity(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(onHero ? AnyShapeStyle(.white.opacity(0.16)) : AnyShapeStyle(feature.tint.opacity(0.1)),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value, format: .number))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if value < range.upperBound { value += 1 }
            case .decrement: if value > range.lowerBound { value -= 1 }
            @unknown default: break
            }
        }
    }

    private func round(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: 38, height: 38)
                .foregroundStyle(onHero ? AnyShapeStyle(feature.colors.last!) : AnyShapeStyle(.white))
                .background(onHero ? AnyShapeStyle(.white) : AnyShapeStyle(feature.gradient), in: Circle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
    }
}

/// Rising bars: how far this reach level gets you.
private struct ReachMeter: View {
    let level: Int
    let selected: Bool
    let feature: Feature

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<5) { i in
                Capsule()
                    .fill(i < level ? (selected ? AnyShapeStyle(.white) : AnyShapeStyle(feature.gradient))
                                    : AnyShapeStyle((selected ? Color.white : feature.tint).opacity(0.25)))
                    .frame(width: 4, height: 8 + CGFloat(i) * 3)
            }
        }
        .accessibilityHidden(true)
    }
}
