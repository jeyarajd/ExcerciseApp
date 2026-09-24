import Foundation

extension AppModel {
    /// Reschedules the evening reminder: once a day, only while today's training isn't done, and
    /// saying what the day's plan is. Call after anything that changes what's done or planned.
    @MainActor func refreshReminders() async {
        let trainedToday = didSessionToday || isPlanDayDone(Date())
        await Reminders.refresh(trainedToday: trainedToday) { [weak self] date in self?.reminderText(on: date) }
    }
}
