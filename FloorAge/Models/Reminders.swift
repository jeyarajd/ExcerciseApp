import Foundation
import UserNotifications

/// One evening nudge a day to finish the day's training, scheduled on the device. Instead of one
/// repeating notification, the coming days are scheduled one by one: a day you've already trained
/// (or a plan rest day) is skipped, and each says what that day's plan is.
enum Reminders {
    /// How far ahead to schedule. Refreshed on every launch, and well under iOS's 64 pending limit,
    /// so someone who stays away for weeks still gets nudged.
    static let days = 30
    private static let prefix = "daily-session-"
    private static let defaults = UserDefaults.standard
    /// Refreshes run one after another so two overlapping ones can't leave both sets scheduled.
    @MainActor private static var lastRefresh: Task<Void, Never>?

    static var isOn: Bool {
        get { defaults.bool(forKey: "reminderOn") }
        set { defaults.set(newValue, forKey: "reminderOn") }
    }

    /// Minutes after midnight. Defaults to 18:00: late enough to know the day's training is still
    /// to do, early enough to fit it in.
    static var minuteOfDay: Int {
        get { defaults.object(forKey: "reminderMinute") as? Int ?? 18 * 60 }
        set { defaults.set(newValue, forKey: "reminderMinute") }
    }

    /// Asks for permission if needed and turns reminders on. Returns false if notifications are
    /// denied. Schedule them afterwards with `AppModel.refreshReminders()`.
    @MainActor static func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        isOn = granted
        return granted
    }

    @MainActor static func disable() async {
        isOn = false
        await refresh(trainedToday: false) { _ in nil }
    }

    /// Reschedules the coming reminders. `text` gives each day's message, or nil to skip that day.
    @MainActor static func refresh(trainedToday: Bool, now: Date = Date(), text: @escaping (Date) -> String?) async {
        let previous = lastRefresh
        let task = Task { @MainActor in
            await previous?.value
            await reschedule(trainedToday: trainedToday, now: now, text: text)
        }
        lastRefresh = task
        await task.value
    }

    @MainActor private static func reschedule(trainedToday: Bool, now: Date, text: (Date) -> String?) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard isOn else { return }

        for date in fireDates(minuteOfDay: minuteOfDay, trainedToday: trainedToday, now: now) {
            guard let body = text(date) else { continue }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Still time for today's training")
            content.body = body
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            // One ID per day, so adding a day again replaces it rather than duplicating it.
            let request = UNNotificationRequest(
                identifier: prefix + "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            )
            try? await center.add(request)
        }
    }

    /// One reminder when the next Floor Age check is due, in the evening at the reminder time
    /// (the next evening if it's already overdue). Replaces any earlier one.
    @MainActor static func scheduleRetest(lastCheck: Date?, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [retestID])
        guard isOn, let lastCheck else { return }
        let date = retestDate(lastCheck: lastCheck, minuteOfDay: minuteOfDay, now: now)
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Time to retest your Floor Age")
        content.body = String(localized: "It's been 4 weeks. Take the 10-minute check and see how far you've come.")
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        try? await center.add(UNNotificationRequest(identifier: retestID, content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
    }

    private static let retestID = "floor-age-retest"

    static func retestDate(lastCheck: Date, minuteOfDay: Int, now: Date, calendar: Calendar = .current) -> Date {
        func evening(_ day: Date) -> Date {
            calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: day) ?? day
        }
        let due = evening(Retest.due(after: lastCheck, calendar: calendar))
        guard due <= now else { return due }
        let today = evening(now)
        return today > now ? today : evening(calendar.date(byAdding: .day, value: 1, to: now) ?? now)
    }

    /// The reminder times for the coming `days` days, skipping today if it's past or already done.
    static func fireDates(minuteOfDay: Int, trainedToday: Bool, now: Date, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0...days).compactMap { offset -> Date? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let date = calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: day)
            else { return nil }
            if offset == 0 && (trainedToday || date <= now) { return nil }
            return date
        }
        .prefix(days)
        .map { $0 }
    }
}
