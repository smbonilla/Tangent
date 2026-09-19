import Foundation
import UserNotifications

enum ReminderSchedulerError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        "Notifications are disabled. You can enable them in system Settings."
    }
}

@MainActor
final class LocalReminderScheduler: ReminderScheduler {
    static let requestIdentifier = "tangent.daily-reminder"

    private let center: UNUserNotificationCenter
    private let calendar: Calendar

    init(
        center: UNUserNotificationCenter = .current(),
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.center = center
        self.calendar = calendar
    }

    func scheduleDailyReminder(at time: Date) async throws {
        let granted = try await center.requestAuthorization(
            options: [.alert, .sound]
        )
        guard granted else {
            throw ReminderSchedulerError.permissionDenied
        }

        let content = UNMutableNotificationContent()
        content.title = "Tangent"
        content.body = "Do you have a few minutes to talk?"
        content.sound = .default

        let components = calendar.dateComponents([.hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: true
        )
        let request = UNNotificationRequest(
            identifier: Self.requestIdentifier,
            content: content,
            trigger: trigger
        )

        center.removePendingNotificationRequests(
            withIdentifiers: [Self.requestIdentifier]
        )
        try await center.add(request)
    }

    func cancelDailyReminder() {
        center.removePendingNotificationRequests(
            withIdentifiers: [Self.requestIdentifier]
        )
    }
}
