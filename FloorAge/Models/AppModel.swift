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
    /// Picks the coach (and voice) who demonstrates. Optional: nil means "prefer not to say".
    var gender: Gender? = nil
    /// From the BMI screen. Optional so profiles saved before these existed still load.
    var heightCm: Double? = nil
    var weightKg: Double? = nil

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
    }

    private let fileURL: URL
    private var loading = false

    init(fileURL: URL? = nil) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = fileURL ?? dir.appendingPathComponent("floorage.json")
        load()
    }

    var latestResult: FloorAgeResult? { results.last }

    func add(_ result: FloorAgeResult) {
        results.append(result)
        save()
    }

    func completeSession(on date: Date = Date()) {
        let day = Calendar.current.startOfDay(for: date)
        if !sessionDays.contains(day) {
            sessionDays.append(day)
            save()
        }
    }

    var didSessionToday: Bool {
        sessionDays.contains(Calendar.current.startOfDay(for: Date()))
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
        guard let profile, let program = planProgram, let position = planPosition(on: date) else {
            return String(localized: "Your 10-minute session with Coach is ready. Missing a day never resets your progress.")
        }
        let day = TrainingPlan.week(position.week, program: program, profile: profile, averageSteps: planBaseSteps).days[position.day]
        guard day.activities != [.rest] else { return nil }
        return String(localized: "Today: \(TrainingPlan.headline(day)). A little now keeps your streak going.")
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
        if done { planDone.append(day) }
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

    /// The coach matches the person's gender; the female coach is the default.
    private func syncCoachLook() {
        let look = profile?.gender == .male ? "male" : "female"
        guard UserDefaults.standard.string(forKey: "coachLook") != look else { return }
        UserDefaults.standard.set(look, forKey: "coachLook")
        NotificationCenter.default.post(name: Notification.Name("CoachLookChanged"), object: nil)
    }

    private func load() {
        loading = true
        defer { loading = false }
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
    }

    private func save() {
        guard !loading else { return }
        let stored = Stored(profile: profile, results: results, sessionDays: sessionDays, foodLog: foodLog, weights: weights,
                            planStart: planStart, planProgram: planProgram?.rawValue, planDone: planDone,
                            planBaseSteps: planBaseSteps, sleepLog: sleepLog)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}

struct PlanItem: Identifiable, Hashable {
    let id = UUID()
    let exercise: Exercise
    let reps: Int?
    let seconds: Int?

    init(_ exerciseID: String, reps: Int? = nil, seconds: Int? = nil) {
        let exercise = ExerciseLibrary.shared[exerciseID]
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
        .sitRise: ["deep_squat_hold", "squat", "sit_rise"],
        .balance: ["single_leg_balance", "side_leg_raise", "calf_raise"],
        .chairStand: ["squat", "chair_stand", "calf_raise"],
        .reach: ["toe_reach", "deep_squat_hold", "side_leg_raise"],
    ]

    static func unsafe(for limitations: Set<Limitation>) -> Set<String> {
        var ids = Set<String>()
        if limitations.contains(.knee) { ids.formUnion(["sit_rise", "deep_squat_hold", "squat"]) }
        if limitations.contains(.hip) { ids.formUnion(["sit_rise", "deep_squat_hold", "side_leg_raise"]) }
        if limitations.contains(.back) { ids.formUnion(["toe_reach", "sit_rise"]) }
        if limitations.contains(.dizziness) { ids.formUnion(["toe_reach"]) }
        return ids
    }

    /// Today's ~10 minute session: a warm-up, then work on the weakest areas from the last check,
    /// finishing with pelvic floor squeezes unless they're switched off in Settings.
    static func today(profile: Profile, latest: FloorAgeResult?, date: Date = Date(), pelvicFloor: Bool = true) -> [PlanItem] {
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
            plan.append(PlanItem(id, reps: reps))
        }
        if pelvicFloor { plan.append(PlanItem("kegel", reps: 8)) }
        return plan
    }

    /// A standalone pelvic floor session: about 2 minutes of guided squeezes.
    static let pelvicFloor = [PlanItem("kegel", reps: 12)]
}
