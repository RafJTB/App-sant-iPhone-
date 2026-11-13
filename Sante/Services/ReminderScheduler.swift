import Foundation
import SwiftData
import UserNotifications

/// Rappel du soir : « Ta journée est complète ? ».
/// On programme une notification ponctuelle pour chacun des 7 prochains jours,
/// en sautant les journées déjà validées (une notification répétitive ne permet pas de sauter un jour).
enum ReminderScheduler {
    private static let prefix = "rappel-soir-"

    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    @MainActor
    static func reschedule(profile: ProfileStore, context: ModelContext) async {
        let logs = (try? context.fetch(FetchDescriptor<DayLog>())) ?? []
        await reschedule(enabled: profile.reminderEnabled,
                         hour: profile.reminderHour,
                         minute: profile.reminderMinute,
                         completedDays: logs.completedDays)
    }

    static func reschedule(enabled: Bool, hour: Int, minute: Int, completedDays: Set<Date>) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        guard enabled else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today),
                  !completedDays.contains(day),
                  let fire = cal.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  fire > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Ta journée est complète ?"
            content.body = "Ajoute ce qui manque puis valide ta journée : seules les journées complètes comptent dans le verdict."
            content.sound = .default

            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let request = UNNotificationRequest(
                identifier: prefix + String(Int(day.timeIntervalSince1970)),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            )
            try? await center.add(request)
        }
    }
}
