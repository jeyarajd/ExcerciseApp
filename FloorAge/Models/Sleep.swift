import Foundation

/// One night's sleep, logged by the person or read from Apple Health.
struct SleepEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var bedtime: Date
    var wake: Date
    /// Time actually asleep, when Apple Health knows it; otherwise bedtime to wake.
    var minutesAsleep: Int?
    /// 1 poor, 2 okay, 3 good (manual entries only).
    var quality: Int?
    var fromHealth = false

    var hours: Double { Double(minutesAsleep ?? Int(wake.timeIntervalSince(bedtime) / 60)) / 60 }
    /// A night belongs to the day you woke up.
    var day: Date { Calendar.current.startOfDay(for: wake) }
}

/// Sleep targets and helpers. Recommended durations are from the National Sleep Foundation
/// (Hirshkowitz et al., Sleep Health 2015): 7–9 hours for adults, 7–8 hours from 65.
enum SleepGuide {
    static func recommended(age: Int) -> ClosedRange<Double> { age >= 65 ? 7...8 : 7...9 }

    static func assessment(hours: Double, age: Int) -> String {
        let range = recommended(age: age)
        if hours < range.lowerBound - 1 { return "Well short of the \(label(range)) most adults need. Try an earlier, regular bedtime." }
        if hours < range.lowerBound { return "A little under the recommended \(label(range))." }
        if hours > range.upperBound + 1 { return "Longer than usual. If you often need this much, it's worth mentioning to your doctor." }
        return "Right in the recommended \(label(range)). Well done."
    }

    static func label(_ range: ClosedRange<Double>) -> String {
        "\(Int(range.lowerBound))–\(Int(range.upperBound)) hours"
    }

    static func duration(_ hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60)) min"
    }

    /// A sleep record from Apple Health: a stretch of time asleep, or only in bed.
    struct Sample {
        let start: Date
        let end: Date
        let asleep: Bool
    }

    /// Groups Health samples into nights (by the day you woke; anything ending before 6 pm counts
    /// for that day), merging overlaps so an iPhone and a Watch recording the same night aren't
    /// counted twice. Uses time asleep when there is any, otherwise time in bed.
    static func nights(from samples: [Sample], calendar: Calendar = .current) -> [SleepEntry] {
        let byNight = Dictionary(grouping: samples) { sample in
            calendar.startOfDay(for: sample.end.addingTimeInterval(6 * 3600))
        }
        return byNight.values.compactMap { group -> SleepEntry? in
            let asleep = group.filter(\.asleep)
            let used = asleep.isEmpty ? group : asleep
            let minutes = Int(mergedDuration(used.map { ($0.start, $0.end) }) / 60)
            guard minutes >= 60, let bed = used.map(\.start).min(), let wake = used.map(\.end).max() else { return nil }
            return SleepEntry(bedtime: bed, wake: wake, minutesAsleep: minutes, fromHealth: true)
        }
        .sorted { $0.wake < $1.wake }
    }

    /// Total length of a set of intervals, counting overlaps once.
    static func mergedDuration(_ intervals: [(Date, Date)]) -> TimeInterval {
        var total: TimeInterval = 0
        var current: (Date, Date)?
        for (start, end) in intervals.sorted(by: { $0.0 < $1.0 }) where end > start {
            if let c = current, start <= c.1 {
                current = (c.0, max(c.1, end))
            } else {
                if let c = current { total += c.1.timeIntervalSince(c.0) }
                current = (start, end)
            }
        }
        if let c = current { total += c.1.timeIntervalSince(c.0) }
        return total
    }
}
