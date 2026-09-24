import Foundation

enum Limitation: String, Codable, CaseIterable, Identifiable {
    case knee, hip, back, dizziness, medical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .knee: "Knee pain or knee surgery"
        case .hip: "Hip pain or hip replacement"
        case .back: "Back pain"
        case .dizziness: "Dizziness or balance problems"
        case .medical: "A doctor has told me to limit exercise"
        }
    }
}

struct Profile: Codable, Equatable {
    var name: String
    var age: Int
    var limitations: Set<Limitation>
}

/// App state, stored as one JSON file on the device. Nothing leaves the phone except what the
/// user sends to the coach chat.
final class AppModel: ObservableObject {
    @Published var profile: Profile? { didSet { save() } }
    @Published private(set) var results: [FloorAgeResult] = []
    @Published private(set) var sessionDays: [Date] = []

    private struct Stored: Codable {
        var profile: Profile?
        var results: [FloorAgeResult]
        var sessionDays: [Date]
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
        save()
    }

    private func load() {
        loading = true
        defer { loading = false }
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        profile = stored.profile
        results = stored.results
        sessionDays = stored.sessionDays
    }

    private func save() {
        guard !loading else { return }
        let stored = Stored(profile: profile, results: results, sessionDays: sessionDays)
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
        if let reps { return "\(reps) reps" }
        return "\(seconds ?? 0) sec"
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

    /// Today's ~10 minute session: a warm-up, then work on the weakest areas from the last check.
    static func today(profile: Profile, latest: FloorAgeResult?, date: Date = Date()) -> [PlanItem] {
        let skip = unsafe(for: profile.limitations)
        let dayIndex = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        let gentle = profile.limitations.contains(.medical) || profile.age >= 70

        var ids: [String] = []
        let focus = latest?.rankedWeakest ?? [.chairStand, .balance, .reach]
        // Three exercises for the weakest area, one each for the next two, rotated daily.
        for (rank, test) in focus.prefix(3).enumerated() {
            let options = (trainers[test] ?? []).filter { !skip.contains($0) && !ids.contains($0) }
            guard !options.isEmpty else { continue }
            let count = rank == 0 ? min(2, options.count) : 1
            for i in 0..<count {
                ids.append(options[(dayIndex + i) % options.count])
            }
        }
        if ids.isEmpty { ids = ["calf_raise", "arm_raise"] }

        var plan = [PlanItem("march", seconds: gentle ? 30 : 45), PlanItem("arm_raise", seconds: 30)]
        for id in ids {
            let exercise = ExerciseLibrary.shared[id]
            let reps = exercise.defaultReps.map { gentle ? max(4, $0 * 2 / 3) : $0 }
            plan.append(PlanItem(id, reps: reps))
        }
        return plan
    }
}
