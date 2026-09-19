import Foundation

@MainActor
final class UnavailableReminderScheduler: ReminderScheduler {
    func scheduleDailyReminder(at time: Date) async throws {}
    func cancelDailyReminder() {}
}
