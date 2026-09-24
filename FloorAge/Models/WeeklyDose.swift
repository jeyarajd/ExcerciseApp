import Foundation

/// Small balance and strength moves folded into everyday tasks, from the LiFE programme (Clemson
/// et al., BMJ 2012;345:e4547): 31% fewer falls than a gentle control (IRR 0.69) and better
/// adherence at 12 months than a structured programme. One a day, drawn from the weakest area.
struct DailyHabit: Equatable {
    let text: String
    let symbol: String
    /// Which weekly dial ticking it off counts towards (flexibility habits have none).
    let kind: ActivityRecord.Kind?

    static func all(for area: FloorTest) -> [DailyHabit] {
        switch area {
        case .balance: [
            DailyHabit(text: String(localized: "Brush your teeth standing on one leg (swap halfway)."), symbol: "figure.stand", kind: .balance),
            DailyHabit(text: String(localized: "Walk heel-to-toe to the kitchen."), symbol: "shoeprints.fill", kind: .balance),
            DailyHabit(text: String(localized: "Walk sideways along the kitchen bench while the kettle boils."), symbol: "arrow.left.and.right", kind: .balance),
            DailyHabit(text: String(localized: "Stand with your feet together while you wait in a queue or on the phone."), symbol: "figure.stand", kind: .balance),
        ]
        case .chairStand: [
            DailyHabit(text: String(localized: "Sit down and stand up from the sofa 5 times without your hands."), symbol: "sofa.fill", kind: .strength),
            DailyHabit(text: String(localized: "Rise onto your toes 10 times while the kettle boils."), symbol: "arrow.up", kind: .strength),
            DailyHabit(text: String(localized: "Take the stairs, one step at a time with the rail, instead of the lift."), symbol: "figure.stairs", kind: .strength),
            DailyHabit(text: String(localized: "Squat, not bend, to close a low drawer or pick something up."), symbol: "arrow.down.to.line", kind: .strength),
        ]
        case .sitRise: [
            DailyHabit(text: String(localized: "Sit on the floor for a few minutes while you watch TV, then get up slowly."), symbol: "tv", kind: .strength),
            DailyHabit(text: String(localized: "Kneel down on a cushion to reach a low shelf, then stand back up."), symbol: "figure.cross.training", kind: .strength),
            DailyHabit(text: String(localized: "Squat, not bend, to close a low drawer or pick something up."), symbol: "arrow.down.to.line", kind: .strength),
        ]
        case .reach: [
            DailyHabit(text: String(localized: "Reach up to the top shelf and hold the stretch for 3 breaths."), symbol: "arrow.up.to.line", kind: nil),
            DailyHabit(text: String(localized: "Fold forward gently to touch your shins while you wait for the kettle."), symbol: "figure.flexibility", kind: nil),
            DailyHabit(text: String(localized: "Put your socks on standing up, holding the counter if you need to."), symbol: "shoeprints.fill", kind: nil),
        ]
        }
    }

    /// Today's habit: the area's list, one a day in turn. Balance when there's no check yet.
    static func today(area: FloorTest?, on date: Date = Date(), calendar: Calendar = .current) -> DailyHabit {
        let habits = all(for: area ?? .balance)
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return habits[day % habits.count]
    }
}

/// A finished workout, for the weekly dose dials.
struct ActivityRecord: Codable, Equatable {
    enum Kind: String, Codable {
        /// Moderate aerobic activity (walking, running: running counts double, as WHO does).
        case move
        /// Muscle strengthening.
        case strength
        case balance
    }

    var date: Date
    /// Moderate-equivalent minutes.
    var minutes: Int
    var kinds: [Kind]
}

/// This week's dose against the guidelines, filled from what was actually done:
/// - Move: 150 moderate minutes a week, 250 when losing weight helps (WHO 2020; ACSM 2009).
/// - Strength: 2 days a week at least (WHO), with the most benefit at about 30–60 minutes a week
///   and none extra above that (Momma et al., Br J Sports Med 2022).
/// - Balance: 3 days a week from 65 (WHO), or while balance is the plan's focus.
struct WeeklyDose: Equatable {
    var moveMinutes = 0
    var moveTarget = 150
    var strengthDays = 0
    var strengthMinutes = 0
    var balanceDays = 0
    /// Nil when balance isn't a weekly target for this person.
    var balanceTarget: Int?

    static let strengthDaysTarget = 2
    static let strengthSweetSpot = 30...60

    /// Workouts logged in the week, plus plan days ticked off by hand (their planned activities
    /// count, unless a logged workout of that kind already covers the day) and the daily habit.
    static func compute(week: DateInterval, records: [ActivityRecord], planDays: [(date: Date, activities: [TrainingPlan.Activity])],
                        habitDays: [(date: Date, kind: ActivityRecord.Kind?)], moveTarget: Int, balanceTarget: Int?,
                        calendar: Calendar = .current) -> WeeklyDose {
        var dose = WeeklyDose(moveTarget: moveTarget, balanceTarget: balanceTarget)
        var strengthDays = Set<Date>(), balanceDays = Set<Date>()
        var logged: [Date: Set<ActivityRecord.Kind>] = [:]
        func add(_ kind: ActivityRecord.Kind, minutes: Int, on date: Date) {
            let day = calendar.startOfDay(for: date)
            switch kind {
            case .move: dose.moveMinutes += minutes
            case .strength:
                dose.strengthMinutes += minutes
                strengthDays.insert(day)
            case .balance: balanceDays.insert(day)
            }
        }
        for record in records where week.contains(record.date) {
            logged[calendar.startOfDay(for: record.date), default: []].formUnion(record.kinds)
            for kind in record.kinds { add(kind, minutes: record.minutes, on: record.date) }
        }
        for day in planDays where week.contains(day.date) {
            let covered = logged[calendar.startOfDay(for: day.date)] ?? []
            for activity in day.activities {
                guard let kind = activity.doseKind, !covered.contains(kind) else { continue }
                add(kind, minutes: activity.moderateMinutes, on: day.date)
            }
        }
        for habit in habitDays where week.contains(habit.date) {
            // A habit counts as a day of balance or strength, not as minutes.
            let day = calendar.startOfDay(for: habit.date)
            if habit.kind == .balance { balanceDays.insert(day) } else if habit.kind == .strength { strengthDays.insert(day) }
        }
        dose.strengthDays = strengthDays.count
        dose.balanceDays = balanceDays.count
        return dose
    }
}

extension TrainingPlan.Activity {
    /// Which dial a planned activity fills.
    var doseKind: ActivityRecord.Kind? {
        switch self {
        case .cardio: .move
        case .strength: .strength
        case .balance: .balance
        case .mobility(let kind, _, _): kind == .floor ? .strength : nil
        case .check, .rest: nil
        }
    }

    /// Minutes as WHO counts them: vigorous running counts double.
    var moderateMinutes: Int {
        guard case .cardio(_, let intervals) = self else { return minutes }
        return intervals.reduce(0) { $0 + ($1.kind == .run ? 2 : 1) * $1.seconds } / 60
    }
}
