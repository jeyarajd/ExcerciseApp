import Foundation

extension AppModel {
    /// Reschedules the evening reminder: once a day, only while today's training isn't done, and
    /// saying what the day's plan is. Call after anything that changes what's done or planned.
    @MainActor func refreshReminders() async {
        // Reminders belong to the phone's owner; a family member's day doesn't change them.
        guard isOwner else { return }
        let trainedToday = didSessionToday || isPlanDayDone(Date())
        await Reminders.refresh(trainedToday: trainedToday) { [weak self] date in self?.reminderText(on: date) }
        await Reminders.scheduleRetest(lastCheck: latestResult?.date)
    }
}
