import Foundation

/// Progress on the evidence, not the calendar. Each exercise family (see `ExerciseFamily`) has a
/// level, A to D, that moves only on what the person actually did:
/// - Otago Exercise Programme manual (Campbell & Robertson): move up a level once the person can
///   do 2 sets of 10 good reps; rest 1–2 minutes between sets.
/// - ACSM progression models in resistance training (Med Sci Sports Exerc 2009): raise the load
///   once you can do 1–2 reps more than the target.
///
/// The rule ("2-for-2"): the target plus 2 in each of the last two sessions moves up one level.
/// Because the coach counts reps from the animation and stops at the target, "Easy" after the
/// session stands for those 2 reps in reserve. Missing the target by 3 or more twice moves down.
/// "Hard" twice keeps the level and drops a set. Something hurting swaps to the easier level for a
/// week. More than a week away drops one level ("Let's ease back in"). Missed days never reset
/// anything else.
struct SessionLog: Codable, Equatable {
    var date: Date
    /// Reps, or seconds for holds and timed moves (per set).
    var targetReps: Int
    /// The weakest set's count.
    var doneReps: Int
    /// "How hard was that?": 3 easy, 5 just right, 7 hard. Nil until answered.
    var rpe: Int?
    /// "Something hurt" was picked for this exercise.
    var hurt: Bool?
}

struct ExerciseProgress: Codable, Equatable, Identifiable {
    /// The family's id.
    var id: String
    /// 0 = level A.
    var level: Int
    /// Sessions at the current level, oldest first (cleared when the level changes).
    var lastSessions: [SessionLog] = []
    /// The last session at any level, to notice a long break.
    var lastTrained: Date?
    /// Until this date the coach plays the level below, after something hurt.
    var easierUntil: Date?
}

/// The answer to "How hard was that?".
enum Effort: Int, CaseIterable, Identifiable {
    case easy = 3, justRight = 5, hard = 7

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .easy: String(localized: "Easy")
        case .justRight: String(localized: "Just right")
        case .hard: String(localized: "Hard")
        }
    }

    var symbol: String {
        switch self {
        case .easy: "face.smiling"
        case .justRight: "hand.thumbsup.fill"
        case .hard: "flame.fill"
        }
    }
}

enum Progression {
    enum Change: Equatable {
        case up, down, easeBack, easier, none
    }

    static let keptSessions = 6
    /// A break longer than this (days) drops one level.
    static let breakDays = 7
    /// Days on the easier level after something hurt.
    static let painDays = 7
    /// Rest between sets, in seconds (Otago: 1–2 minutes; 60–90 s here).
    static let setRest: Double = 60

    /// Adds a finished session and applies the rules.
    static func record(_ log: SessionLog, to progress: ExerciseProgress, levels: Int,
                       calendar: Calendar = .current) -> (ExerciseProgress, Change) {
        var p = progress
        var change = Change.none
        if let last = p.lastTrained, days(from: last, to: log.date, calendar: calendar) > breakDays {
            p.level = max(p.level - 1, 0)
            p.lastSessions = []
            change = .easeBack
        }
        p.lastSessions = Array((p.lastSessions + [log]).suffix(keptSessions))
        p.lastTrained = log.date
        let (next, rule) = evaluate(p, levels: levels, calendar: calendar)
        return (next, rule == .none ? change : rule)
    }

    /// Adds the "How hard was that?" answer to the latest session and applies the rules again.
    static func rate(_ progress: ExerciseProgress, effort: Effort?, hurt: Bool = false, levels: Int,
                     calendar: Calendar = .current) -> (ExerciseProgress, Change) {
        guard var last = progress.lastSessions.last else { return (progress, .none) }
        var p = progress
        if let effort { last.rpe = effort.rawValue }
        if hurt { last.hurt = true }
        p.lastSessions[p.lastSessions.count - 1] = last
        return evaluate(p, levels: levels, calendar: calendar)
    }

    static func evaluate(_ progress: ExerciseProgress, levels: Int, calendar: Calendar = .current) -> (ExerciseProgress, Change) {
        var p = progress
        guard let last = p.lastSessions.last else { return (p, .none) }
        if last.hurt == true {
            p.easierUntil = calendar.date(byAdding: .day, value: painDays, to: calendar.startOfDay(for: last.date))
            return (p, .easier)
        }
        let recent = p.lastSessions.suffix(2)
        guard recent.count == 2 else { return (p, .none) }
        if recent.allSatisfy(reachedTargetPlusTwo), p.level < levels - 1 {
            p.level += 1
            p.lastSessions = []
            return (p, .up)
        }
        if recent.allSatisfy({ $0.doneReps <= $0.targetReps - 3 }), p.level > 0 {
            p.level -= 1
            p.lastSessions = []
            return (p, .down)
        }
        return (p, .none)
    }

    /// Did 2 more than the target, or finished it and called it easy (2 or more in reserve).
    static func reachedTargetPlusTwo(_ log: SessionLog) -> Bool {
        log.doneReps >= log.targetReps + 2 || (log.doneReps >= log.targetReps && log.rpe == Effort.easy.rawValue)
    }

    /// "Hard" in both of the last two sessions: keep the level, one set fewer next time.
    static func dropsASet(_ progress: ExerciseProgress?) -> Bool {
        guard let recent = progress?.lastSessions.suffix(2), recent.count == 2 else { return false }
        return recent.allSatisfy { $0.rpe == Effort.hard.rawValue }
    }

    /// The level to play today: one lower while easing back in after a break or after something
    /// hurt (never more than one lower).
    static func level(_ progress: ExerciseProgress, on date: Date, calendar: Calendar = .current) -> Int {
        let hurt = progress.easierUntil.map { date < $0 } ?? false
        return max(progress.level - (hurt || isBreak(progress, on: date, calendar: calendar) ? 1 : 0), 0)
    }

    static func isBreak(_ progress: ExerciseProgress, on date: Date, calendar: Calendar = .current) -> Bool {
        guard let last = progress.lastTrained else { return false }
        return days(from: last, to: date, calendar: calendar) > breakDays
    }

    private static func days(from: Date, to: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)).day ?? 0
    }
}

/// Everyone's levels as the plan and the daily session see them: turns a family's anchor exercise
/// into the person's level, skips levels their limitations rule out, and writes the coach's note.
struct LevelBook {
    var progress: [String: ExerciseProgress] = [:]
    var limitations: Set<Limitation> = []
    /// Gentle plans start every family at level A.
    var gentle = false
    var date = Date()
    var library = ExerciseLibrary.shared

    /// The level to play today, capped at the highest level that's safe; nil if none is.
    func level(of family: ExerciseFamily) -> Int? {
        let wanted = progress[family.id].map { Progression.level($0, on: date) } ?? (gentle ? 0 : family.start)
        let unsafe = PlanBuilder.unsafe(for: limitations)
        return (0...min(wanted, family.levels.count - 1)).last { index in
            let level = family.levels[index]
            return !unsafe.contains(level.exercise) && limitations.isDisjoint(with: level.avoid ?? [])
        }
    }

    /// The plan item for an exercise: the person's level when it anchors a family.
    func item(_ exerciseID: String, reps: Int? = nil, seconds: Int? = nil) -> PlanItem? {
        guard let family = library.family(anchoredAt: exerciseID) else { return PlanItem(exerciseID, reps: reps, seconds: seconds) }
        guard let index = level(of: family) else { return nil }
        let level = family.levels[index]
        let exercise = family.exercise(at: index)
        // The level's own amount, else the plan's when it fits the kind, else the default.
        let planReps = exercise.kind == .reps ? reps : nil
        let planSeconds = exercise.kind == .reps ? nil : seconds
        var item = PlanItem(exercise: exercise, reps: level.reps ?? planReps, seconds: level.seconds ?? planSeconds)
        item.family = family.id
        item.level = index
        item.note = note(family: family, level: index, item: item)
        return item
    }

    /// Whether this exercise's family gets one set fewer next time.
    func dropsASet(_ exerciseID: String) -> Bool {
        library.family(anchoredAt: exerciseID).map { Progression.dropsASet(progress[$0.id]) } ?? false
    }

    /// "You did 10 last time. Try 10 again." Never "week 3".
    private func note(family: ExerciseFamily, level: Int, item: PlanItem) -> String? {
        guard let p = progress[family.id] else { return nil }
        if p.easierUntil.map({ date < $0 }) ?? false { return String(localized: "We're keeping this one easier for a few days.") }
        if Progression.isBreak(p, on: date) { return String(localized: "Let's ease back in.") }
        guard level == p.level, let last = p.lastSessions.last else { return nil }
        let target = item.reps ?? item.seconds ?? last.targetReps
        let tried = item.reps != nil
            ? String(localized: "You did \(last.doneReps) last time. Try \(target) again.")
            : String(localized: "You held \(last.doneReps) seconds last time. Try \(target) again.")
        guard level < family.levels.count - 1, Progression.reachedTargetPlusTwo(last) else { return tried }
        return tried + " " + String(localized: "If it feels easy again, we go up.")
    }
}

/// What one session did for one exercise family: the per-set target and the weakest set.
struct FamilyResult: Equatable {
    let family: String
    let level: Int
    let target: Int
    let done: Int
}
