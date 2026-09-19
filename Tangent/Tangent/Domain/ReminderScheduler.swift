import Foundation

@MainActor
protocol ReminderScheduler {
    func scheduleDailyReminder(at time: Date) async throws
    func cancelDailyReminder()
}
