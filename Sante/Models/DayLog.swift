import Foundation
import SwiftData

/// Statut d'une journée de saisie. Seules les journées validées comptent dans le verdict :
/// une journée à moitié saisie ferait croire à un déficit qui n'existe pas.
@Model
final class DayLog {
    /// Début de la journée (Calendar.startOfDay).
    @Attribute(.unique) var day: Date
    var isComplete: Bool

    init(day: Date, isComplete: Bool = true) {
        self.day = Calendar.current.startOfDay(for: day)
        self.isComplete = isComplete
    }
}

extension Array where Element == DayLog {
    var completedDays: Set<Date> {
        Set(filter(\.isComplete).map { Calendar.current.startOfDay(for: $0.day) })
    }
}

enum DayCompletion {
    /// Marque une journée comme terminée ou la rouvre.
    static func set(_ complete: Bool, day: Date, logs: [DayLog], context: ModelContext) {
        let start = Calendar.current.startOfDay(for: day)
        if let log = logs.first(where: { Calendar.current.isDate($0.day, inSameDayAs: start) }) {
            log.isComplete = complete
        } else if complete {
            context.insert(DayLog(day: start, isComplete: true))
        }
        try? context.save()
    }
}
