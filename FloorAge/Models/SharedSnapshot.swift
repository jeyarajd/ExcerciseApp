import Foundation

/// A small summary of the phone owner's progress, shared with the widgets (through the App Group)
/// and the Apple Watch (through WatchConnectivity). It stays on the person's own devices.
struct FloorAgeSnapshot: Codable, Equatable {
    var name = ""
    var floorAge: Int?
    var age: Int?
    /// Which of the last 7 days (oldest first) had training.
    var week: [Bool] = Array(repeating: false, count: 7)
    var stepsToday = 0
    var stepGoal = 8000
    var challengeDay: Int?
    var challengeDone: Int?
    /// Today's training plan in a few words ("Brisk walk · 25 min"), if there's a plan.
    var planToday: String?
    var trainedToday = false
    var updated = Date()

    static let appGroup = "group.com.jeyaraj.floorage"
    private static let key = "snapshot"

    var daysThisWeek: Int { week.filter { $0 }.count }
    var stepProgress: Double { stepGoal > 0 ? min(Double(stepsToday) / Double(stepGoal), 1) : 0 }

    /// Years younger (negative) or older (positive) than the person's age.
    var difference: Int? { floorAge.flatMap { f in age.map { f - $0 } } }

    static func load(from defaults: UserDefaults? = UserDefaults(suiteName: appGroup)) -> FloorAgeSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FloorAgeSnapshot.self, from: data)
    }

    func save(to defaults: UserDefaults? = UserDefaults(suiteName: appGroup)) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults?.set(data, forKey: Self.key)
    }

    /// The same summary seen on a later day: the week shifts along (days since are untrained, as far
    /// as the widget knows) and today's steps and training start from zero.
    func rolledForward(to date: Date, calendar: Calendar = .current) -> FloorAgeSnapshot {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: updated), to: calendar.startOfDay(for: date)).day ?? 0
        guard days > 0 else { return self }
        var copy = self
        let shift = min(days, week.count)
        copy.week = Array(week.dropFirst(shift)) + Array(repeating: false, count: shift)
        copy.stepsToday = 0
        copy.trainedToday = false
        copy.planToday = nil
        copy.challengeDay = challengeDay.map { $0 + days }.flatMap { $0 <= 30 ? $0 : nil }  // Challenge.length
        if copy.challengeDay == nil { copy.challengeDone = nil }
        copy.updated = date
        return copy
    }

    /// For widget previews, the gallery and screenshots.
    static let sample = FloorAgeSnapshot(name: "Priya", floorAge: 56, age: 52, week: [false, true, true, false, true, true, false],
                                         stepsToday: 6240, stepGoal: 8000, challengeDay: 12, challengeDone: 9,
                                         planToday: "Brisk walk · 25 min", trainedToday: false)
}
