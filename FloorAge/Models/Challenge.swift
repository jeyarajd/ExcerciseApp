import Foundation

/// The 30-day "Get off the floor" challenge: train on as many of the 30 days as you can. Any
/// session counts (the daily session, the pelvic floor session or a plan day). Badges mark 3, 7,
/// 14, 21 and 30 days trained; missing a day never takes one away.
struct Challenge: Equatable {
    static let length = 30

    enum Badge: Int, CaseIterable, Identifiable, Codable {
        case three = 3, seven = 7, fourteen = 14, twentyOne = 21, thirty = 30

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .three: String(localized: "Off the floor")
            case .seven: String(localized: "One week strong")
            case .fourteen: String(localized: "Two weeks steady")
            case .twentyOne: String(localized: "Habit formed")
            case .thirty: String(localized: "Floor champion")
            }
        }

        var detail: String { String(localized: "Trained on \(rawValue) days of the challenge") }

        var symbol: String {
            switch self {
            case .three: "flame.fill"
            case .seven: "star.fill"
            case .fourteen: "bolt.heart.fill"
            case .twentyOne: "leaf.fill"
            case .thirty: "trophy.fill"
            }
        }
    }

    let start: Date
    /// Days with any training, at the start of the day.
    let trainedDays: Set<Date>
    var calendar = Calendar.current

    /// The 30 days of the challenge.
    var days: [Date] {
        (0..<Self.length).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: start)) }
    }

    func trained(_ day: Date) -> Bool { trainedDays.contains(calendar.startOfDay(for: day)) }

    var completed: Int { days.filter(trained).count }

    /// 1 on the first day, capped at 30.
    func dayNumber(on date: Date = Date()) -> Int {
        let elapsed = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: date)).day ?? 0
        return min(max(elapsed + 1, 1), Self.length)
    }

    func isOver(on date: Date = Date()) -> Bool {
        guard let end = calendar.date(byAdding: .day, value: Self.length, to: calendar.startOfDay(for: start)) else { return false }
        return date >= end
    }

    var earned: [Badge] { Badge.allCases.filter { completed >= $0.rawValue } }

    var nextBadge: Badge? { Badge.allCases.first { completed < $0.rawValue } }
}

/// When the next Floor Age check is due: about 4 weeks after the last one, long enough for
/// training to show.
enum Retest {
    static let interval = 28

    static func due(after lastCheck: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: interval, to: calendar.startOfDay(for: lastCheck)) ?? lastCheck
    }

    static func isDue(lastCheck: Date, on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        date >= due(after: lastCheck, calendar: calendar)
    }
}
