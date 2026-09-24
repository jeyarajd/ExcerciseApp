import Foundation

/// Runs a list of exercises: intro (coach demonstrates), active (counting / timing), rest, done.
/// Reps are counted from the avatar's animation, so the voice count always matches the coach.
final class SessionEngine: ObservableObject {
    enum Phase: Equatable {
        case intro, active, rest, done
    }

    let items: [PlanItem]
    let avatar = AvatarController()

    @Published private(set) var index = 0
    @Published private(set) var phase: Phase = .intro
    @Published private(set) var repsDone = 0
    @Published private(set) var secondsLeft: Double = 0
    @Published private(set) var isPaused = false
    @Published private(set) var mirrored = false
    /// The current timed prompt for exercises with keyframe cues ("Squeeze and lift").
    @Published private(set) var cueText: String?

    private let voice: VoiceCoach
    private var timer: Timer?
    /// Set when the person leaves early. Only reaching the end marks the day as trained.
    private var stopped = false
    private var lastCueAt: Double = 0
    private var cueIndex = 0
    let restSeconds: Double = 15

    init(items: [PlanItem], voice: VoiceCoach) {
        self.items = items
        self.voice = voice
        avatar.onRep = { [weak self] in
            DispatchQueue.main.async { self?.handleRep() }
        }
        avatar.onCue = { [weak self] cue in
            DispatchQueue.main.async { self?.handleCue(cue) }
        }
    }

    var current: PlanItem? { items.indices.contains(index) ? items[index] : nil }
    var next: PlanItem? { items.indices.contains(index + 1) ? items[index + 1] : nil }

    var progress: Double {
        guard let item = current else { return 1 }
        switch phase {
        case .active:
            if let reps = item.reps { return Double(repsDone) / Double(max(reps, 1)) }
            let total = Double(item.seconds ?? 1)
            return 1 - secondsLeft / total
        case .done: return 1
        default: return 0
        }
    }

    // MARK: - Flow

    func start() {
        showIntro()
    }

    func beginActive() {
        guard let item = current else { return }
        phase = .active
        repsDone = 0
        cueText = nil
        cueIndex = 0
        lastCueAt = 0
        mirrored = false
        secondsLeft = Double(item.seconds ?? 0)
        avatar.play(item.exercise)
        avatar.isPlaying = true
        voice.say(String(localized: "Ready. Go!"), interrupt: true)
        startTimer()
    }

    func togglePause() {
        isPaused.toggle()
        avatar.isPlaying = !isPaused
        voice.say(isPaused ? String(localized: "Paused.") : String(localized: "Let's continue."), interrupt: true)
    }

    /// During rest the next exercise is already current, so skipping rest just starts its intro.
    func skip() {
        if phase == .rest {
            timer?.invalidate()
            showIntro()
        } else {
            advance()
        }
    }

    /// Stops everything without completing the session (the close button).
    func end() {
        stopped = true
        timer?.invalidate()
        avatar.isPlaying = false
        voice.stop()
    }

    /// Quiets the coach, e.g. while a demo video plays.
    func stopTalking() {
        voice.stop()
    }

    func setSpeed(_ speed: Double) {
        avatar.speed = speed
    }

    private func showIntro() {
        guard let item = current else { return finish() }
        phase = .intro
        timer?.invalidate()
        cueText = nil
        avatar.play(item.exercise)
        avatar.isPlaying = true
        let amount = item.reps.map { String(localized: "\($0) reps.") } ?? String(localized: "\(item.seconds ?? 0) seconds.")
        voice.say(String(localized: "\(item.exercise.intro) \(amount)"), interrupt: true)
    }

    private func advance() {
        timer?.invalidate()
        guard index + 1 < items.count else { return finish() }
        index += 1
        if phase == .active {
            startRest()
        } else {
            showIntro()
        }
    }

    private func startRest() {
        phase = .rest
        secondsLeft = restSeconds
        cueText = nil
        if let item = current {
            avatar.play(item.exercise)
            voice.say(String(localized: "Nice work. Rest. Next up, \(item.exercise.name)."), interrupt: true)
        }
        startTimer()
    }

    private func finish() {
        timer?.invalidate()
        phase = .done
        avatar.play(id: "idle")
        cueText = nil
        voice.say(String(localized: "That's the session done. Great job showing up today!"), interrupt: true)
    }

    // MARK: - Ticking

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick(0.1) }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick(_ dt: Double) {
        guard !isPaused, !stopped, let item = current else { return }
        switch phase {
        case .rest:
            secondsLeft -= dt
            if secondsLeft <= 0 { showIntro() }
        case .active where item.reps == nil:
            let total = Double(item.seconds ?? 30)
            let before = secondsLeft
            secondsLeft = max(0, secondsLeft - dt)
            let elapsed = total - secondsLeft
            if item.exercise.mirrorHalfway == true, !mirrored, secondsLeft <= total / 2 {
                mirrored = true
                avatar.play(item.exercise, mirrored: true)
                voice.say(String(localized: "Switch sides."), interrupt: true)
            } else if before > 10, secondsLeft <= 10, total > 20 {
                voice.say(String(localized: "Ten seconds left."))
            } else if Int(before.rounded(.up)) != Int(secondsLeft.rounded(.up)), (1...3).contains(Int(secondsLeft.rounded(.up))) {
                voice.say(String(localized: "\(Int(secondsLeft.rounded(.up)))"), interrupt: true)
            } else if elapsed - lastCueAt >= 9, secondsLeft > 12 {
                sayNextCue(item)
                lastCueAt = elapsed
            }
            if secondsLeft <= 0 {
                voice.say(String(localized: "And rest."), interrupt: true)
                advance()
            }
        default:
            break
        }
    }

    private func handleRep() {
        guard phase == .active, !isPaused, !stopped, let item = current, let target = item.reps else { return }
        repsDone += 1
        if repsDone >= target {
            voice.say(String(localized: "\(repsDone). Done!"), interrupt: true)
            advance()
            return
        }
        if item.exercise.mirrorHalfway == true, !mirrored, repsDone == target / 2 {
            mirrored = true
            avatar.play(item.exercise, mirrored: true)
            voice.say(String(localized: "\(repsDone). Switch sides."), interrupt: true)
            return
        }
        voice.say(String(localized: "\(repsDone)"), interrupt: true)
        let timedCues = item.exercise.keyframes.contains { $0.cue != nil }
        if target - repsDone == 2 {
            voice.say(String(localized: "Two more!"))
        } else if repsDone % 4 == 2, !timedCues {
            sayNextCue(item)
        }
    }

    /// Keyframe cues show on screen whenever the coach plays; they're spoken during the exercise.
    private func handleCue(_ cue: String) {
        guard !stopped, phase == .intro || phase == .active else { return }
        cueText = cue
        guard phase == .active, !isPaused else { return }
        voice.say(cue)
    }

    private func sayNextCue(_ item: PlanItem) {
        let cues = item.exercise.cues
        guard !cues.isEmpty else { return }
        voice.say(cues[cueIndex % cues.count])
        cueIndex += 1
    }
}
