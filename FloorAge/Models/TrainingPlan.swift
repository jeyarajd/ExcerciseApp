import Foundation

/// A weekly training plan chosen from the person's BMI, age and limitations, following published
/// guidelines rather than invented numbers:
/// - WHO 2020 guidelines (Bull et al., Br J Sports Med 2020): 150–300 min a week of moderate
///   aerobic activity, muscle strengthening on 2+ days, and for older adults balance and strength
///   on 3+ days.
/// - ACSM position stand on weight management (Donnelly et al., Med Sci Sports Exerc 2009):
///   150–250 min a week prevents weight gain; more than 250 min for significant weight loss.
/// - ACSM progression models in resistance training (Med Sci Sports Exerc 2009): beginners train
///   2–3 days a week at 8–12 repetitions, building from 1 to 3 sets.
/// - Paluch et al., Lancet Public Health 2022 (15 cohorts, 47,471 adults): the benefit of daily
///   steps levels off at 8,000–10,000 under 60 and 6,000–8,000 at 60 and over.
/// - NHS Couch to 5K: 9 weeks, 3 runs a week with rest days between, run/walk intervals that build
///   to 30 minutes of running, each run with a 5-minute walk before and after.
/// - Otago Exercise Programme manual (Campbell & Robertson): strength and balance three times a
///   week with walking on the days between; exercises progress through levels (see `Progression`).
///   The plan's emphasis follows the weakest area of the last Floor Age check, and the other
///   areas keep one session a week.
/// - Every 4th week is a check week: one set fewer (deload), two strength sessions, and a Floor
///   Age check to see what changed. If the focus area didn't improve, the next check's plan
///   moves the emphasis on and says why.
/// - Gentle plans (70+, a doctor's limit, or a Floor Age 15+ years above real age) cap strength at
///   2 sets and start every exercise at level A.
enum TrainingPlan {
    enum Program: String, CaseIterable, Identifiable {
        case runWalk, briskWalk, gentleWalk

        var id: String { rawValue }

        var title: String {
            switch self {
            case .runWalk: String(localized: "Couch to 5K run/walk")
            case .briskWalk: String(localized: "Brisk walking plan")
            case .gentleWalk: String(localized: "Gentle walking plan")
            }
        }

        var weeks: Int { self == .runWalk ? 9 : 12 }
    }

    struct Interval: Equatable {
        enum Kind: String {
            case warmUp = "Warm-up walk", run = "Run", walk = "Walk", brisk = "Brisk walk", easy = "Easy walk", coolDown = "Cool-down walk"
        }
        let kind: Kind
        let seconds: Int

        /// Compendium MET values: running about 5 mph, brisk walking about 3.5 mph, and an easy
        /// walk about 2.5–3 mph.
        var met: Double {
            switch kind {
            case .run: 8.3
            case .brisk: 4.3
            case .walk, .warmUp, .coolDown: 3.5
            case .easy: 3.0
            }
        }

        /// The interval's name in the person's language ("Run", "Brisk walk").
        var title: String {
            switch kind {
            case .warmUp: String(localized: "Warm-up walk")
            case .run: String(localized: "Run")
            case .walk: String(localized: "Walk")
            case .brisk: String(localized: "Brisk walk")
            case .easy: String(localized: "Easy walk")
            case .coolDown: String(localized: "Cool-down walk")
            }
        }

        /// Typical cadence: brisk walking is about 100+ steps a minute, running about 160.
        var steps: Int {
            let perMinute = switch kind {
            case .run: 160
            case .brisk: 110
            case .walk, .warmUp, .coolDown: 95
            case .easy: 85
            }
            return seconds * perMinute / 60
        }
    }

    struct StrengthMove: Equatable {
        let exerciseID: String
        let reps: Int?
        let seconds: Int?
    }

    /// Extra blocks from the Floor Age emphasis.
    enum Mobility: String, Equatable {
        /// Getting down to and up from the floor (weakest area: sit to rise).
        case floor
        /// Toe reach and hips (weakest area: toe reach).
        case flexibility
        /// One maintenance session for the areas that aren't the focus.
        case allRound
    }

    enum Activity: Equatable {
        case cardio(Program, [Interval])
        case strength(sets: Int, moves: [StrengthMove])
        case balance(sets: Int, moves: [StrengthMove])
        case mobility(Mobility, sets: Int, moves: [StrengthMove])
        /// The Floor Age re-test at the end of a check week.
        case check
        case rest
    }

    struct Day: Equatable {
        /// 0...6 from the plan's start weekday.
        let index: Int
        let activities: [Activity]
        let stepGoal: Int
    }

    struct Week: Equatable {
        let program: Program
        let number: Int
        let days: [Day]
        let stepGoal: Int
        /// Moderate-intensity minutes this week (running counts double, as WHO does for vigorous).
        let aerobicMinutes: Int
        let targetMinutes: Int
        let sets: Int
        let reps: Int
        /// The area the week emphasises (from the last Floor Age check), if any.
        var focus: FloorTest? = nil
        /// Every 4th week: lighter, with a Floor Age check.
        var isCheckWeek = false
    }

    /// The plan's focus area, and the area it moved on from when that didn't improve.
    struct Emphasis: Equatable {
        let area: FloorTest
        /// Set when the last focus didn't improve at the latest check, so the plan moved on.
        var unchanged: FloorTest? = nil
    }

    // MARK: - Choosing the plan

    /// Running only for a healthy weight, under 60 and without joint limits; otherwise walking,
    /// gentler for obesity, 70+ or a doctor's limit.
    static func recommendedProgram(for profile: Profile, scale: BMIScale = .current) -> Program {
        let limits = profile.limitations
        if limits.contains(.medical) || profile.age >= 70 { return .gentleWalk }
        if let bmi = profile.bmi, BMI.category(bmi, scale: scale) == .obese { return .gentleWalk }
        let jointLimits = !limits.isDisjoint(with: [.knee, .hip, .dizziness])
        // Overweight: walking protects the joints. Underweight: no extra calorie burn from running.
        if let bmi = profile.bmi, [.overweight, .underweight].contains(BMI.category(bmi, scale: scale)) { return .briskWalk }
        if profile.age >= 60 || jointLimits { return .briskWalk }
        return .runWalk
    }

    /// Whether the person's BMI says losing weight would help, which lifts the weekly target above
    /// 250 minutes (ACSM).
    static func aimsForWeightLoss(_ profile: Profile, scale: BMIScale = .current) -> Bool {
        guard let bmi = profile.bmi else { return false }
        let category = BMI.category(bmi, scale: scale)
        return category == .overweight || category == .obese
    }

    /// 70+, a doctor's limit, or a Floor Age 15 or more years above their age.
    static func isGentle(_ profile: Profile, latest: FloorAgeResult?) -> Bool {
        if profile.limitations.contains(.medical) || profile.age >= 70 { return true }
        guard let latest else { return false }
        return latest.floorAge - latest.age >= 15
    }

    /// Every 4th week is a check week.
    static func isCheckWeek(_ number: Int) -> Bool { number % 4 == 0 }

    /// Where the plan puts its emphasis: the weakest area of the latest check. If the area the
    /// plan focused on didn't improve since the check before, the next weakest takes over.
    static func emphasis(from results: [FloorAgeResult]) -> Emphasis? {
        guard let latest = results.last, let weakest = latest.rankedWeakest.first else { return nil }
        guard results.count >= 2, let before = emphasis(from: Array(results.dropLast())) else { return Emphasis(area: weakest) }
        let focus = before.area
        guard weakest == focus,
              let now = latest.equivalentAge(focus), let then = results[results.count - 2].equivalentAge(focus),
              now >= then,
              let next = latest.rankedWeakest.dropFirst().first
        else { return Emphasis(area: weakest) }
        return Emphasis(area: next, unchanged: focus)
    }

    // MARK: - Building a week

    static func week(_ number: Int, program: Program, profile: Profile, averageSteps: Int?,
                     focus: FloorTest? = nil, gentle: Bool = false, scale: BMIScale = .current) -> Week {
        let week = min(max(number, 1), program.weeks)
        let weightLoss = aimsForWeightLoss(profile, scale: scale)
        let older = profile.age >= 65
        // Weeks past the end repeat the final week, but the 4-weekly check keeps its rhythm.
        let checkWeek = isCheckWeek(number)

        // Strength: 1 set in weeks 1–2, 2 sets in weeks 3–5, then 3 (at most 2 on gentle plans).
        // Check weeks drop a set: bodies adapt on rest.
        let fullSets = min(week <= 2 ? 1 : week <= 5 ? 2 : 3, program == .gentleWalk || gentle ? 2 : 3)
        let sets = checkWeek ? max(fullSets - 1, 1) : fullSets
        let reps = 10
        let strength = strengthMoves(for: profile, reps: reps, week: week)
        let balance = balanceMoves(for: profile, week: week, otago: focus == .balance)

        // Daily steps: from their own average, 1,000 more each week, up to the level where the
        // benefit levels off for their age.
        let cap = profile.age >= 60 ? 8000 : 10000
        let base = max(averageSteps ?? 4000, 3000)
        let stepGoal = min(cap, roundTo500(base + 1000 * (week - 1)))

        var days: [[Activity]] = Array(repeating: [], count: 7)
        switch program {
        case .runWalk:
            // Couch to 5K: runs on days 1, 3 and 5 with rest between, strength on days 2 and 6, a
            // brisk walk on day 4, rest on day 7.
            for (run, day) in [0, 2, 4].enumerated() {
                days[day].append(.cardio(.runWalk, couchTo5K(week: week, run: run)))
            }
            days[1].append(.strength(sets: sets, moves: strength))
            days[5].append(.strength(sets: sets, moves: strength))
            days[3].append(.cardio(.briskWalk, walk(briskMinutes: 20)))
        case .briskWalk, .gentleWalk:
            // Walking on 5 days, strength on days 1 and 4, rest on days 3 and 7.
            let minutes = walkingMinutes(program: program, week: week, weightLoss: weightLoss)
            for day in [0, 1, 3, 4, 5] {
                days[day].append(.cardio(program, walk(briskMinutes: minutes, gentle: program == .gentleWalk)))
            }
            days[0].append(.strength(sets: sets, moves: strength))
            days[3].append(.strength(sets: sets, moves: strength))
        }
        // Leg strength focus: a third strength day (Otago: three a week), but only two in a check week.
        if focus == .chairStand, !checkWeek {
            let third = program == .runWalk ? 3 : 5
            days[third].append(.strength(sets: sets, moves: strength))
        }
        // Older adults: balance and strength on 3 or more days (WHO). Balance focus: the Otago
        // balance block three times a week for everyone.
        if older || focus == .balance, !balance.isEmpty {
            for day in [1, 3, 5] { days[day].append(.balance(sets: min(sets, 2), moves: balance)) }
        }
        // Floor focus: a floor mobility block 3 times a week. Reach focus: flexibility 4 times.
        if focus == .sitRise {
            let moves = mobilityMoves(.floor, profile: profile, week: week)
            if !moves.isEmpty { for day in [1, 3, 5] { days[day].append(.mobility(.floor, sets: min(sets, 2), moves: moves)) } }
        }
        if focus == .reach {
            let moves = mobilityMoves(.flexibility, profile: profile, week: week)
            if !moves.isEmpty { for day in [0, 1, 3, 5] { days[day].append(.mobility(.flexibility, sets: 2, moves: moves)) } }
        }
        // The other areas keep one maintenance session a week.
        if let focus {
            let moves = maintenanceMoves(profile: profile, focus: focus, older: older, week: week)
            if !moves.isEmpty { days[4].append(.mobility(.allRound, sets: 1, moves: moves)) }
        }
        // Check week: the Floor Age check on the last day.
        if checkWeek { days[6].append(.check) }
        let plannedDays = days.enumerated().map { index, activities in
            Day(index: index, activities: activities.isEmpty ? [.rest] : activities, stepGoal: stepGoal)
        }
        let minutes = plannedDays.flatMap(\.activities).reduce(0) { total, activity in
            guard case .cardio(_, let intervals) = activity else { return total }
            return total + intervals.reduce(0) { $0 + ($1.kind == .run ? 2 : 1) * $1.seconds } / 60
        }
        let target = weightLoss ? 250 : 150
        return Week(program: program, number: week, days: plannedDays, stepGoal: stepGoal,
                    aerobicMinutes: minutes, targetMinutes: target, sets: sets, reps: reps,
                    focus: focus, isCheckWeek: checkWeek)
    }

    /// Brisk walking minutes per session: brisk starts at 20 and adds 5 a week; gentle starts at 10
    /// and adds 4. The cap reaches 250 min a week (5 × 50) when losing weight helps, otherwise 150.
    static func walkingMinutes(program: Program, week: Int, weightLoss: Bool) -> Int {
        let (start, step) = program == .gentleWalk ? (10, 4) : (20, 5)
        let cap = weightLoss ? 50 : 30
        return min(start + step * (week - 1), cap)
    }

    static func walk(briskMinutes: Int, gentle: Bool = false) -> [Interval] {
        let easy = gentle ? 3 : 5
        return [Interval(kind: .warmUp, seconds: easy * 60),
                Interval(kind: gentle ? .walk : .brisk, seconds: max(briskMinutes - 2 * easy, 5) * 60),
                Interval(kind: .coolDown, seconds: easy * 60)]
    }

    /// The Couch to 5K run for this week (0-based run number), between 5-minute walks.
    static func couchTo5K(week: Int, run: Int) -> [Interval] {
        func r(_ s: Int) -> Interval { Interval(kind: .run, seconds: s) }
        func w(_ s: Int) -> Interval { Interval(kind: .walk, seconds: s) }
        func repeated(_ runS: Int, _ walkS: Int, times: Int) -> [Interval] {
            Array((0..<times).map { _ in [r(runS), w(walkS)] }.joined()) + [r(runS)]
        }
        let main: [Interval] = switch (week, run) {
        case (1, _): repeated(60, 90, times: 7)
        case (2, _): repeated(90, 120, times: 5)
        case (3, _): [r(90), w(90), r(180), w(180), r(90), w(90), r(180)]
        case (4, _): [r(180), w(90), r(300), w(150), r(180), w(90), r(300)]
        case (5, 0): [r(300), w(180), r(300), w(180), r(300)]
        case (5, 1): [r(480), w(300), r(480)]
        case (5, _): [r(1200)]
        case (6, 0): [r(300), w(180), r(480), w(180), r(300)]
        case (6, 1): [r(600), w(180), r(600)]
        case (6, _): [r(1500)]
        case (7, _): [r(1500)]
        case (8, _): [r(1680)]
        default: [r(1800)]
        }
        return [Interval(kind: .warmUp, seconds: 300)] + main + [Interval(kind: .coolDown, seconds: 300)]
    }

    private static func strengthMoves(for profile: Profile, reps: Int, week: Int) -> [StrengthMove] {
        let unsafe = PlanBuilder.unsafe(for: profile.limitations)
        let gentle = profile.limitations.contains(.medical) || profile.age >= 70
        let candidates = gentle
            ? ["chair_stand", "calf_raise", "side_leg_raise", "arm_raise"]
            : ["squat", "chair_stand", "calf_raise", "side_leg_raise", "arm_raise"]
        return candidates.filter { !unsafe.contains($0) }.prefix(4).map { id in
            ExerciseLibrary.shared[id].kind == .reps
                ? StrengthMove(exerciseID: id, reps: reps, seconds: nil)
                : StrengthMove(exerciseID: id, reps: nil, seconds: min(30 + 5 * (week - 1), 60))
        }
    }

    /// The balance block; the Otago version adds calf raises (on the toes, the balance family's
    /// partner in the manual).
    private static func balanceMoves(for profile: Profile, week: Int, otago: Bool = false) -> [StrengthMove] {
        let ids = otago ? ["single_leg_balance", "calf_raise", "side_leg_raise"] : ["single_leg_balance", "side_leg_raise"]
        return moves(ids, profile: profile, reps: 8, seconds: min(20 + 5 * (week - 1), 45))
    }

    /// Floor: kneel to stand, squat and the deep squat hold. Flexibility: toe reach, the
    /// half-kneel hip stretch, the deep squat hold and arm raises, about 10 minutes over 2 sets.
    private static func mobilityMoves(_ kind: Mobility, profile: Profile, week: Int) -> [StrengthMove] {
        switch kind {
        case .floor: moves(["kneel_to_stand", "squat", "deep_squat_hold"], profile: profile, reps: 8, seconds: 30)
        case .flexibility: moves(["toe_reach", "half_kneel", "deep_squat_hold", "arm_raise"], profile: profile, reps: 6, seconds: 30)
        case .allRound: []
        }
    }

    /// One move for each area that isn't the focus. Leg strength is already covered by the
    /// strength days, and balance by the balance days from 65.
    private static func maintenanceMoves(profile: Profile, focus: FloorTest, older: Bool, week: Int) -> [StrengthMove] {
        let byArea: [(FloorTest, String)] = [(.sitRise, "kneel_to_stand"), (.balance, "single_leg_balance"), (.reach, "toe_reach")]
        let ids = byArea.filter { $0.0 != focus && !($0.0 == .balance && older) }.map(\.1)
        return moves(ids, profile: profile, reps: 8, seconds: 30)
    }

    private static func moves(_ ids: [String], profile: Profile, reps: Int, seconds: Int) -> [StrengthMove] {
        let unsafe = PlanBuilder.unsafe(for: profile.limitations)
        return ids.filter { !unsafe.contains($0) }.map { id in
            ExerciseLibrary.shared[id].kind == .reps
                ? StrengthMove(exerciseID: id, reps: reps, seconds: nil)
                : StrengthMove(exerciseID: id, reps: nil, seconds: seconds)
        }
    }

    private static func roundTo500(_ steps: Int) -> Int { Int((Double(steps) / 500).rounded()) * 500 }

    /// The coach-led session for a block: the moves repeated once per set, at the person's levels
    /// when given. A move rated "Hard" twice gets one set fewer, and each new set starts after a
    /// longer rest.
    static func sessionItems(sets: Int, moves: [StrengthMove], levels: LevelBook? = nil) -> [PlanItem] {
        let sets = max(sets, 1)
        return (0..<sets).flatMap { set -> [PlanItem] in
            let items = moves.compactMap { move -> PlanItem? in
                if set == sets - 1, sets > 1, levels?.dropsASet(move.exerciseID) == true { return nil }
                return levels.map { $0.item(move.exerciseID, reps: move.reps, seconds: move.seconds) }
                    ?? PlanItem(move.exerciseID, reps: move.reps, seconds: move.seconds)
            }
            guard set > 0, var first = items.first else { return items }
            first.restBefore = Progression.setRest
            return [first] + items.dropFirst()
        }
    }
}

extension TrainingPlan.Activity {
    var minutes: Int {
        switch self {
        case .cardio(_, let intervals): intervals.reduce(0) { $0 + $1.seconds } / 60
        case .strength(let sets, let moves), .balance(let sets, let moves), .mobility(_, let sets, let moves):
            // About 40 s per move per set plus rest.
            max(1, sets * moves.count * 40 / 60 + sets)
        case .check: 10
        case .rest: 0
        }
    }

    var steps: Int {
        guard case .cardio(_, let intervals) = self else { return 0 }
        return intervals.reduce(0) { $0 + $1.steps }
    }
}

extension TrainingPlan {
    /// "5 min walk, (run 1 min, walk 1½ min) × 7, run 1 min, 5 min walk".
    static func describe(_ intervals: [TrainingPlan.Interval]) -> String {
        func time(_ s: Int) -> String {
            if s % 60 == 0 { return String(localized: "\(s / 60) min") }
            if s % 60 == 30 { return s < 60 ? String(localized: "30 s") : String(localized: "\(s / 60)½ min") }
            return String(localized: "\(s) s")
        }
        func name(_ i: TrainingPlan.Interval) -> String {
            switch i.kind {
            case .warmUp, .coolDown: String(localized: "\(time(i.seconds)) walk")
            default: String(localized: "\(i.title.lowercased()) \(time(i.seconds))")
            }
        }
        var parts: [String] = []
        var i = 0
        while i < intervals.count {
            var repeats = 1
            while i + 2 * repeats + 1 < intervals.count,
                  intervals[i + 2 * repeats] == intervals[i], intervals[i + 2 * repeats + 1] == intervals[i + 1] {
                repeats += 1
            }
            if repeats > 1 {
                parts.append(String(localized: "(\(name(intervals[i])), \(name(intervals[i + 1]))) × \(repeats)"))
                i += 2 * repeats
            } else {
                parts.append(name(intervals[i]))
                i += 1
            }
        }
        return parts.joined(separator: ", ")
    }
}

extension TrainingPlan {
    /// "Run/walk", "Brisk walk" or "Walk".
    static func cardioName(_ program: Program, _ intervals: [Interval]) -> String {
        if program == .runWalk { return String(localized: "Run/walk") }
        return intervals.contains { $0.kind == .brisk } ? String(localized: "Brisk walk") : String(localized: "Walk")
    }

    /// "Brisk walk 30 min + strength 2 sets", for the plan card and reminders.
    static func headline(_ day: Day) -> String {
        let parts = day.activities.compactMap { activity -> String? in
            switch activity {
            case .cardio(let program, let intervals):
                return String(localized: "\(cardioName(program, intervals)) \(activity.minutes) min")
            case .strength(let sets, _):
                return sets == 1 ? String(localized: "strength 1 set") : String(localized: "strength \(sets) sets")
            case .balance: return String(localized: "balance")
            case .mobility(let kind, _, _): return kind.title.lowercased()
            case .check: return String(localized: "Floor Age check")
            case .rest: return nil
            }
        }
        guard let first = parts.first else { return String(localized: "Rest day") }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + parts.dropFirst()).joined(separator: " + ")
    }
}

extension TrainingPlan.Mobility {
    var title: String {
        switch self {
        case .floor: String(localized: "Floor mobility")
        case .flexibility: String(localized: "Flexibility")
        case .allRound: String(localized: "All-round")
        }
    }
}
