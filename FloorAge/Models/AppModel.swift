import Foundation

enum Limitation: String, Codable, CaseIterable, Identifiable {
    case knee, hip, back, dizziness, medical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .knee: String(localized: "Knee pain or knee surgery")
        case .hip: String(localized: "Hip pain or hip replacement")
        case .back: String(localized: "Back pain")
        case .dizziness: String(localized: "Dizziness or balance problems")
        case .medical: String(localized: "A doctor has told me to limit exercise")
        }
    }
}

extension Limitation {
    /// "knee", "hip"… for short lists.
    var shortLabel: String {
        switch self {
        case .knee: String(localized: "knee")
        case .hip: String(localized: "hip")
        case .back: String(localized: "back")
        case .dizziness: String(localized: "dizziness")
        case .medical: String(localized: "doctor's advice")
        }
    }
}

enum Gender: String, Codable, CaseIterable, Identifiable {
    case female, male

    var id: String { rawValue }
    var label: String { self == .female ? String(localized: "Woman") : String(localized: "Man") }
}

struct Profile: Codable, Equatable {
    var name: String
    var age: Int
    var limitations: Set<Limitation>
    /// Used for calorie targets, and picks the coach unless one was chosen. Optional: nil means
    /// "prefer not to say".
    var gender: Gender? = nil
    /// The coach (and voice) chosen in onboarding or Settings; nil follows `gender`. Optional so
    /// profiles saved before the choice existed still load.
    var coach: CoachLook? = nil
    /// From the BMI screen. Optional so profiles saved before these existed still load.
    var heightCm: Double? = nil
    var weightKg: Double? = nil

    var coachLook: CoachLook { coach ?? CoachLook(matching: gender) }

    var bmi: Double? {
        guard let heightCm, let weightKg else { return nil }
        return BMI.value(weightKg: weightKg, heightCm: heightCm)
    }

    /// Calories a day to keep the current weight, once height and weight are known.
    var calorieTarget: Int? {
        guard let heightCm, let weightKg else { return nil }
        return Calories.dailyTarget(age: age, gender: gender, heightCm: heightCm, weightKg: weightKg)
    }
}

/// App state, stored as one JSON file on the device. Nothing leaves the phone.
final class AppModel: ObservableObject {
    @Published var profile: Profile? {
        didSet {
            save()
            syncCoachLook()
            updateActiveMember()
        }
    }
    @Published private(set) var results: [FloorAgeResult] = []
    @Published private(set) var sessionDays: [Date] = []
    @Published private(set) var foodLog: [FoodEntry] = []
    @Published private(set) var weights: [WeightEntry] = []
    /// The training plan: when it started, the chosen program, and the days marked done.
    @Published private(set) var planStart: Date?
    @Published private(set) var planProgram: TrainingPlan.Program?
    @Published private(set) var planDone: [Date] = []
    /// Average daily steps when the plan started; step goals build from here.
    @Published private(set) var planBaseSteps: Int?
    @Published private(set) var sleepLog: [SleepEntry] = []
    /// When the 30-day challenge started, if one is running (or finished and not cleared).
    @Published private(set) var challengeStart: Date?
    /// Each exercise family's level and recent sessions (see `Progression`).
    @Published private(set) var progress: [ExerciseProgress] = []
    /// Days the daily habit (LiFE) was ticked off.
    @Published private(set) var habitDays: [Date] = []
    /// Finished workouts, for the weekly dose dials.
    @Published private(set) var activityLog: [ActivityRecord] = []
    /// A challenge badge just earned, for the app to celebrate once. Not saved.
    @Published var newBadge: Challenge.Badge?

    private struct Stored: Codable {
        var profile: Profile?
        var results: [FloorAgeResult]
        var sessionDays: [Date]
        // Optional: files saved by earlier versions don't have them.
        var foodLog: [FoodEntry]?
        var weights: [WeightEntry]?
        var planStart: Date?
        var planProgram: String?
        var planDone: [Date]?
        var planBaseSteps: Int?
        var sleepLog: [SleepEntry]?
        var challengeStart: Date?
        var progress: [ExerciseProgress]?
        var habitDays: [Date]?
        var activityLog: [ActivityRecord]?
    }

    /// Everyone who uses this iPhone. The first is the phone's owner, whose data lives in the
    /// original file; each family member has a file of their own next to it.
    @Published private(set) var members: [FamilyMember] = []
    @Published private(set) var activeMemberID: UUID

    /// The owner's file. Family members' files and the family index sit beside it.
    private let mainURL: URL
    private var fileURL: URL
    private var loading = false
    /// Who was active before `addMember()`, so cancelling the new profile can go back.
    private var memberBeforeAdding: UUID?

    init(fileURL: URL? = nil) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        mainURL = fileURL ?? dir.appendingPathComponent("floorage.json")
        let owner = FamilyMember(file: mainURL.lastPathComponent)
        members = [owner]
        activeMemberID = owner.id
        self.fileURL = mainURL
        loadFamily()
        self.fileURL = url(for: activeMember)
        load()
        updateActiveMember()
    }

    var latestResult: FloorAgeResult? { results.last }

    func add(_ result: FloorAgeResult) {
        results.append(result)
        save()
        updateActiveMember()
    }

    func completeSession(on date: Date = Date()) {
        let day = Calendar.current.startOfDay(for: date)
        if !sessionDays.contains(day) {
            let before = challenge?.earned ?? []
            sessionDays.append(day)
            save()
            noticeNewBadge(since: before)
        }
    }

    // MARK: - 30-day challenge

    var challenge: Challenge? {
        challengeStart.map { Challenge(start: $0, trainedDays: Set(sessionDays).union(planDone)) }
    }

    func startChallenge(on date: Date = Date()) {
        challengeStart = Calendar.current.startOfDay(for: date)
        save()
    }

    func endChallenge() {
        challengeStart = nil
        save()
    }

    private func noticeNewBadge(since before: [Challenge.Badge]) {
        guard let challenge else { return }
        if let badge = challenge.earned.last(where: { !before.contains($0) }) { newBadge = badge }
    }

    var didSessionToday: Bool {
        sessionDays.contains(Calendar.current.startOfDay(for: Date()))
    }

    /// Days in a row with a session or a plan day done, counting back from today (or from
    /// yesterday before today's is done, so the streak never looks broken in the morning).
    func streak(on date: Date = Date()) -> Int {
        let cal = Calendar.current
        let trained = Set((sessionDays + planDone).map { cal.startOfDay(for: $0) })
        var day = cal.startOfDay(for: date)
        if !trained.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while trained.contains(day) {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    /// Which of the last 7 days (oldest first) had a session. Missing a day never resets progress.
    var lastSevenDays: [Bool] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            return sessionDays.contains(day)
        }
    }

    func resetAll() {
        if !isOwner {
            removeMember(activeMemberID)
            return
        }
        profile = nil
        results = []
        sessionDays = []
        foodLog = []
        weights = []
        planStart = nil
        planProgram = nil
        planBaseSteps = nil
        planDone = []
        sleepLog = []
        challengeStart = nil
        progress = []
        habitDays = []
        activityLog = []
        save()
    }

    // MARK: - Sleep

    /// Adds or replaces the night that ends on this entry's wake day.
    func logSleep(_ entry: SleepEntry) {
        sleepLog.removeAll { Calendar.current.isDate($0.day, inSameDayAs: entry.day) }
        sleepLog.append(entry)
        sleepLog.sort { $0.wake < $1.wake }
        save()
    }

    /// Adds nights from Apple Health, keeping any night the person logged themselves.
    func importSleep(_ nights: [SleepEntry]) {
        let manualDays = Set(sleepLog.filter { !$0.fromHealth }.map(\.day))
        sleepLog.removeAll { $0.fromHealth }
        sleepLog += nights.filter { !manualDays.contains($0.day) }
        sleepLog.sort { $0.wake < $1.wake }
        save()
    }

    func removeSleep(id: UUID) {
        sleepLog.removeAll { $0.id == id }
        save()
    }

    /// The nights of the last `days` days, oldest first.
    func recentSleep(days: Int = 7, now: Date = Date()) -> [SleepEntry] {
        let from = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: now)) ?? now
        return sleepLog.filter { $0.day >= from }
    }

    var averageSleep: Double? {
        let nights = recentSleep()
        return nights.isEmpty ? nil : nights.map(\.hours).reduce(0, +) / Double(nights.count)
    }

    // MARK: - Training plan

    /// What the evening reminder says on this date: the day's plan, the daily session when there's
    /// no plan, or nothing on a plan rest day.
    func reminderText(on date: Date) -> String? {
        guard let position = planPosition(on: date), let week = planWeek(position.week) else {
            return String(localized: "Your 10-minute session with Coach is ready. Missing a day never resets your progress.")
        }
        let day = week.days[position.day]
        // Rest days only carry the day's small habit (LiFE), never a workout.
        guard day.activities != [.rest] else {
            let habit = DailyHabit.today(area: planEmphasis?.area, on: date)
            return String(localized: "Rest day. Today's small habit: \(habit.text)")
        }
        return String(localized: "Today: \(TrainingPlan.headline(day)). A little now keeps your streak going.")
    }

    /// Where the plan puts its emphasis, from the Floor Age checks.
    var planEmphasis: TrainingPlan.Emphasis? { TrainingPlan.emphasis(from: results) }

    /// A week of the running plan, shaped by the latest checks.
    func planWeek(_ number: Int) -> TrainingPlan.Week? {
        guard let profile, let program = planProgram else { return nil }
        return TrainingPlan.week(number, program: program, profile: profile, averageSteps: planBaseSteps,
                                 focus: planEmphasis?.area, gentle: TrainingPlan.isGentle(profile, latest: latestResult))
    }

    /// This plan week's dose so far: logged workouts, plan days ticked off, and habits.
    func weeklyDose(on date: Date = Date()) -> WeeklyDose? {
        guard let profile, let start = planStart, let position = planPosition(on: date), let week = planWeek(position.week) else { return nil }
        let cal = Calendar.current
        let weekStart = cal.date(byAdding: .day, value: (position.week - 1) * 7, to: start) ?? start
        let interval = DateInterval(start: weekStart, end: cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart)
        let planDays = week.days.compactMap { day -> (date: Date, activities: [TrainingPlan.Activity])? in
            guard let date = cal.date(byAdding: .day, value: day.index, to: weekStart), isPlanDayDone(date) else { return nil }
            return (date, day.activities)
        }
        let area = planEmphasis?.area
        let habits = habitDays.map { (date: $0, kind: DailyHabit.today(area: area, on: $0).kind) }
        let balanceTarget: Int? = profile.age >= 65 || area == .balance ? 3 : nil
        return WeeklyDose.compute(week: interval, records: activityLog, planDays: planDays, habitDays: habits,
                                  moveTarget: week.targetMinutes, balanceTarget: balanceTarget)
    }

    func startPlan(_ program: TrainingPlan.Program, averageSteps: Int?, on date: Date = Date()) {
        planStart = Calendar.current.startOfDay(for: date)
        planProgram = program
        planBaseSteps = averageSteps
        planDone = []
        save()
    }

    func stopPlan() {
        planStart = nil
        planProgram = nil
        planBaseSteps = nil
        planDone = []
        save()
    }

    /// Week (from 1) and day (0...6) of the plan on this date, or nil before it starts.
    func planPosition(on date: Date = Date()) -> (week: Int, day: Int)? {
        guard let planStart else { return nil }
        let days = Calendar.current.dateComponents([.day], from: planStart, to: Calendar.current.startOfDay(for: date)).day ?? 0
        guard days >= 0 else { return nil }
        return (days / 7 + 1, days % 7)
    }

    func isPlanDayDone(_ date: Date) -> Bool {
        planDone.contains { Calendar.current.isDate($0, inSameDayAs: date) }
    }

    func setPlanDay(_ date: Date, done: Bool) {
        let day = Calendar.current.startOfDay(for: date)
        planDone.removeAll { Calendar.current.isDate($0, inSameDayAs: day) }
        let before = challenge?.earned ?? []
        if done { planDone.append(day) }
        save()
        if done { noticeNewBadge(since: before) }
    }

    // MARK: - Progression

    /// Levels as plans and sessions see them today.
    func levels(on date: Date = Date()) -> LevelBook {
        LevelBook(progress: Dictionary(progress.map { ($0.id, $0) }, uniquingKeysWith: { $1 }),
                  limitations: profile?.limitations ?? [],
                  gentle: profile.map { TrainingPlan.isGentle($0, latest: latestResult) } ?? false,
                  date: date)
    }

    func progress(for family: String) -> ExerciseProgress? {
        progress.first { $0.id == family }
    }

    /// Logs what a finished session did for each exercise family and applies the progression
    /// rules. Returns what changed, by family.
    @discardableResult
    func logSession(_ results: [FamilyResult], on date: Date = Date()) -> [String: Progression.Change] {
        var changes: [String: Progression.Change] = [:]
        for result in results {
            guard let family = ExerciseLibrary.shared.family(result.family) else { continue }
            let current = progress(for: result.family) ?? ExerciseProgress(id: result.family, level: result.level)
            let log = SessionLog(date: date, targetReps: result.target, doneReps: result.done)
            let (next, change) = Progression.record(log, to: current, levels: family.levels.count)
            store(next)
            changes[result.family] = change
        }
        save()
        return changes
    }

    /// Adds "How hard was that?" to today's logs. `hurt` names the families that hurt.
    @discardableResult
    func rateSession(_ effort: Effort?, hurt: Set<String> = [], families: [String], on date: Date = Date()) -> [String: Progression.Change] {
        var changes: [String: Progression.Change] = [:]
        for id in families {
            guard let family = ExerciseLibrary.shared.family(id), let current = progress(for: id),
                  let last = current.lastSessions.last, Calendar.current.isDate(last.date, inSameDayAs: date) else { continue }
            let (next, change) = Progression.rate(current, effort: hurt.contains(id) ? nil : effort, hurt: hurt.contains(id),
                                                  levels: family.levels.count)
            store(next)
            changes[id] = change
        }
        save()
        return changes
    }

    private func store(_ next: ExerciseProgress) {
        progress.removeAll { $0.id == next.id }
        progress.append(next)
    }

    // MARK: - Daily habit and weekly dose

    func isHabitDone(on date: Date = Date()) -> Bool {
        habitDays.contains { Calendar.current.isDate($0, inSameDayAs: date) }
    }

    func setHabit(done: Bool, on date: Date = Date()) {
        habitDays.removeAll { Calendar.current.isDate($0, inSameDayAs: date) }
        if done { habitDays.append(Calendar.current.startOfDay(for: date)) }
        save()
    }

    func logActivity(_ record: ActivityRecord) {
        activityLog.append(record)
        // A year is plenty for the weekly dials.
        let cutoff = Calendar.current.date(byAdding: .day, value: -366, to: record.date) ?? record.date
        activityLog.removeAll { $0.date < cutoff }
        save()
    }

    // MARK: - Food and weight

    func addFood(_ entry: FoodEntry) {
        foodLog.append(entry)
        save()
    }

    func removeFood(id: UUID) {
        foodLog.removeAll { $0.id == id }
        save()
    }

    func foods(on date: Date = Date()) -> [FoodEntry] {
        foodLog.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }.sorted { $0.date < $1.date }
    }

    func caloriesEaten(on date: Date = Date()) -> Int {
        foods(on: date).reduce(0) { $0 + $1.total }
    }

    /// Saves height and weight on the profile and adds the weight to the history (one per day).
    func updateBody(heightCm: Double, weightKg: Double, on date: Date = Date()) {
        profile?.heightCm = heightCm
        profile?.weightKg = weightKg
        weights.removeAll { Calendar.current.isDate($0.date, inSameDayAs: date) }
        weights.append(WeightEntry(date: date, kg: weightKg))
        weights.sort { $0.date < $1.date }
        save()
    }

    /// Shows the profile's coach (chosen, or matching their gender); the woman coach is the default.
    private func syncCoachLook() {
        CoachLook.preview(profile?.coachLook ?? .female)
    }

    private func load() {
        loading = true
        defer { loading = false }
        profile = nil
        results = []
        sessionDays = []
        foodLog = []
        weights = []
        planStart = nil
        planProgram = nil
        planDone = []
        planBaseSteps = nil
        sleepLog = []
        challengeStart = nil
        progress = []
        habitDays = []
        activityLog = []
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        profile = stored.profile
        results = stored.results
        sessionDays = stored.sessionDays
        foodLog = stored.foodLog ?? []
        weights = stored.weights ?? []
        planStart = stored.planStart
        planProgram = stored.planProgram.flatMap(TrainingPlan.Program.init(rawValue:))
        planDone = stored.planDone ?? []
        planBaseSteps = stored.planBaseSteps
        sleepLog = stored.sleepLog ?? []
        challengeStart = stored.challengeStart
        progress = stored.progress ?? []
        habitDays = stored.habitDays ?? []
        activityLog = stored.activityLog ?? []
    }

    private func save() {
        guard !loading else { return }
        let stored = Stored(profile: profile, results: results, sessionDays: sessionDays, foodLog: foodLog, weights: weights,
                            planStart: planStart, planProgram: planProgram?.rawValue, planDone: planDone,
                            planBaseSteps: planBaseSteps, sleepLog: sleepLog, challengeStart: challengeStart,
                            progress: progress, habitDays: habitDays, activityLog: activityLog)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

// MARK: - Family

/// One person using this iPhone. Name, age and Floor Age are copied here from their profile, so the
/// family list can show everyone without opening each file.
struct FamilyMember: Codable, Identifiable, Equatable {
    var id = UUID()
    var file: String
    var name = ""
    var age: Int?
    var floorAge: Int?
    var gender: Gender?
}

extension AppModel {
    private struct FamilyIndex: Codable {
        var members: [FamilyMember]
        var active: UUID
    }

    var activeMember: FamilyMember { members.first { $0.id == activeMemberID } ?? members[0] }

    /// The phone's owner. Steps, Apple Health sleep and reminders belong to this iPhone, so they
    /// only follow the owner.
    var isOwner: Bool { activeMemberID == members.first?.id }

    var owner: FamilyMember { members[0] }

    /// Opens someone else's data. Everything on screen follows.
    func switchMember(_ id: UUID) {
        guard id != activeMemberID, let member = members.first(where: { $0.id == id }) else { return }
        activeMemberID = id
        fileURL = url(for: member)
        load()
        syncCoachLook()
        saveFamily()
    }

    /// Starts a new, empty profile and switches to it; the app then shows onboarding for them.
    func addMember() {
        memberBeforeAdding = activeMemberID
        let id = UUID()
        members.append(FamilyMember(id: id, file: fileStem + "-" + id.uuidString + ".json"))
        saveFamily()
        switchMember(id)
    }

    /// True while a just-added member hasn't finished onboarding and can still be cancelled.
    var canCancelNewMember: Bool { profile == nil && !isOwner && memberBeforeAdding != nil }

    func cancelNewMember() {
        guard canCancelNewMember else { return }
        let back = memberBeforeAdding ?? owner.id
        memberBeforeAdding = nil
        removeMember(activeMemberID, switchingTo: back)
    }

    /// Removes a family member and their file. The owner can't be removed.
    func removeMember(_ id: UUID) {
        removeMember(id, switchingTo: owner.id)
    }

    private func removeMember(_ id: UUID, switchingTo next: UUID) {
        guard id != owner.id, let member = members.first(where: { $0.id == id }) else { return }
        if activeMemberID == id { switchMember(members.contains { $0.id == next } && next != id ? next : owner.id) }
        members.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: url(for: member))
        saveFamily()
    }

    fileprivate func updateActiveMember() {
        guard !loading, let index = members.firstIndex(where: { $0.id == activeMemberID }) else { return }
        var member = members[index]
        member.name = profile?.name ?? ""
        member.age = profile?.age
        member.gender = profile?.gender
        member.floorAge = results.last?.floorAge
        guard member != members[index] else { return }
        members[index] = member
        if profile != nil { memberBeforeAdding = nil }
        saveFamily()
    }

    private var fileStem: String { mainURL.deletingPathExtension().lastPathComponent }
    private var familyURL: URL { mainURL.deletingLastPathComponent().appendingPathComponent(fileStem + "-family.json") }

    fileprivate func url(for member: FamilyMember) -> URL {
        mainURL.deletingLastPathComponent().appendingPathComponent(member.file)
    }

    fileprivate func loadFamily() {
        guard let data = try? Data(contentsOf: familyURL),
              let index = try? JSONDecoder().decode(FamilyIndex.self, from: data),
              !index.members.isEmpty else { return }
        members = index.members
        activeMemberID = index.members.contains { $0.id == index.active } ? index.active : index.members[0].id
    }

    private func saveFamily() {
        // A single person needs no index; the app works exactly as before.
        guard members.count > 1 else {
            try? FileManager.default.removeItem(at: familyURL)
            return
        }
        guard let data = try? JSONEncoder().encode(FamilyIndex(members: members, active: activeMemberID)) else { return }
        try? data.write(to: familyURL, options: [.atomic, .completeFileProtection])
    }
}

struct PlanItem: Identifiable, Hashable {
    let id = UUID()
    let exercise: Exercise
    let reps: Int?
    let seconds: Int?
    /// The exercise family (and its level) this trains, so the session can log it for progression.
    var family: String?
    var level: Int?
    /// Said after the intro, e.g. "You did 10 last time. Try 10 again."
    var note: String?
    /// Rest before this item when it starts the next set (longer than between exercises).
    var restBefore: Double?

    init(_ exerciseID: String, reps: Int? = nil, seconds: Int? = nil) {
        self.init(exercise: ExerciseLibrary.shared[exerciseID], reps: reps, seconds: seconds)
    }

    init(exercise: Exercise, reps: Int? = nil, seconds: Int? = nil) {
        self.exercise = exercise
        self.reps = exercise.kind == .reps ? (reps ?? exercise.defaultReps ?? 10) : nil
        self.seconds = exercise.kind == .reps ? nil : (seconds ?? exercise.defaultSeconds ?? 30)
    }

    var amountLabel: String {
        if let reps { return String(localized: "\(reps) reps") }
        return String(localized: "\(seconds ?? 0) sec")
    }

    /// Rough duration, for the plan summary.
    var estimatedSeconds: Double {
        if let reps { return Double(reps) * (exercise.keyframes.last?.t ?? 3) + 15 }
        return Double(seconds ?? 30) + 15
    }
}

enum PlanBuilder {
    /// Exercises that train each test area, most specific first.
    static let trainers: [FloorTest: [String]] = [
        .sitRise: ["kneel_to_stand", "deep_squat_hold", "squat", "sit_rise"],
        .balance: ["single_leg_balance", "side_leg_raise", "calf_raise"],
        .chairStand: ["squat", "chair_stand", "calf_raise"],
        .reach: ["toe_reach", "deep_squat_hold", "side_leg_raise"],
    ]

    static func unsafe(for limitations: Set<Limitation>) -> Set<String> {
        var ids = Set<String>()
        if limitations.contains(.knee) {
            ids.formUnion(["sit_rise", "deep_squat_hold", "squat", "chair_squat", "low_chair_stand", "wall_sit", "kneel_to_stand", "kneel_to_stand_free", "half_kneel"])
        }
        if limitations.contains(.hip) { ids.formUnion(["sit_rise", "deep_squat_hold", "side_leg_raise", "kneel_to_stand", "kneel_to_stand_free", "half_kneel"]) }
        if limitations.contains(.back) { ids.formUnion(["toe_reach", "sit_rise"]) }
        if limitations.contains(.dizziness) { ids.formUnion(["toe_reach", "single_leg_balance_eyes_closed"]) }
        return ids
    }

    /// Today's ~10 minute session: a warm-up, then work on the weakest areas from the last check,
    /// finishing with pelvic floor squeezes unless they're switched off in Settings. With `levels`,
    /// exercises that progress are played at the person's level (see `Progression`).
    static func today(profile: Profile, latest: FloorAgeResult?, date: Date = Date(), pelvicFloor: Bool = true,
                      levels: LevelBook? = nil) -> [PlanItem] {
        let skip = unsafe(for: profile.limitations)
        let dayIndex = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        let gentle = profile.limitations.contains(.medical) || profile.age >= 70

        var ids: [String] = []
        // Weakest tested areas first, then untested ones, so a partial check still gets a full plan.
        let ranked = latest?.rankedWeakest ?? []
        let focus = ranked + [FloorTest.chairStand, .balance, .reach, .sitRise].filter { !ranked.contains($0) }
        // Two exercises for the weakest area, one each for the next two, rotated daily. Areas with
        // nothing safe to offer are passed over rather than using up a slot.
        var areas = 0
        for test in focus where areas < 3 {
            let options = (trainers[test] ?? []).filter { !skip.contains($0) && !ids.contains($0) }
            guard !options.isEmpty else { continue }
            let count = areas == 0 ? min(2, options.count) : 1
            for i in 0..<count {
                ids.append(options[(dayIndex + i) % options.count])
            }
            areas += 1
        }
        if ids.isEmpty { ids = ["calf_raise", "chair_stand"] }

        var plan = [PlanItem("march", seconds: gentle ? 30 : 45), PlanItem("arm_raise", seconds: 30)]
        for id in ids {
            let exercise = ExerciseLibrary.shared[id]
            let reps = exercise.defaultReps.map { gentle ? max(4, $0 * 2 / 3) : $0 }
            guard let levels else {
                plan.append(PlanItem(id, reps: reps))
                continue
            }
            // Two anchors can land on the same level's exercise; play it once.
            if let item = levels.item(id, reps: reps), !plan.contains(where: { $0.exercise.id == item.exercise.id }) {
                plan.append(item)
            }
        }
        if pelvicFloor { plan.append(PlanItem("kegel", reps: 8)) }
        return plan
    }

    /// A standalone pelvic floor session: about 2 minutes of guided squeezes.
    static let pelvicFloor = [PlanItem("kegel", reps: 12)]
}
