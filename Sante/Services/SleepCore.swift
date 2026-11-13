import Foundation

/// Une nuit de sommeil consolidée.
struct SleepNight: Identifiable {
    /// Jour du réveil (début de journée).
    let date: Date
    let bedtime: Date
    let wakeTime: Date
    /// Temps de sommeil réel (sans les doublons iPhone + Watch).
    let asleep: TimeInterval
    let inBed: TimeInterval
    let core: TimeInterval
    let deep: TimeInterval
    let rem: TimeInterval
    let awake: TimeInterval

    var id: Date { date }
    var hasStages: Bool { core + deep + rem > 0 }
    var hours: Double { asleep / 3600 }
}

enum SleepStage: String, CaseIterable {
    case deep = "Profond"
    case core = "Léger"
    case rem = "Paradoxal"
    case unspecified = "Endormi"
    case awake = "Éveillé"
}

/// Un échantillon de sommeil, indépendant de HealthKit (testable).
struct SleepSegment {
    enum Kind { case inBed, awake, core, deep, rem, unspecified }
    let start: Date
    let end: Date
    let kind: Kind
    /// Identifiant de la source (app ou appareil).
    let source: String
}

enum SleepCore {
    /// Regroupe les échantillons en nuits.
    /// Un échantillon commencé après 18 h compte pour la nuit du lendemain.
    static func nights(from segments: [SleepSegment], calendar: Calendar = .current) -> [SleepNight] {
        let groups = Dictionary(grouping: segments) { s in
            calendar.startOfDay(for: s.start.addingTimeInterval(6 * 3600))
        }
        return groups
            .compactMap { day, group in build(day: day, segments: group) }
            .sorted { $0.date < $1.date }
    }

    private static func build(day: Date, segments: [SleepSegment]) -> SleepNight? {
        // Si une source fournit les phases (Apple Watch), on ne garde qu'elle
        // pour éviter de compter deux fois la même nuit (iPhone + Watch).
        var used = segments
        let staged = segments.filter { $0.kind == .core || $0.kind == .deep || $0.kind == .rem }
        if !staged.isEmpty {
            let sources = Set(staged.map(\.source))
            used = segments.filter { sources.contains($0.source) || $0.kind == .inBed }
        }

        var asleepIntervals: [DateInterval] = []
        var inBedIntervals: [DateInterval] = []
        var core = 0.0, deep = 0.0, rem = 0.0, awake = 0.0

        for s in used where s.end > s.start {
            let interval = DateInterval(start: s.start, end: s.end)
            switch s.kind {
            case .inBed: inBedIntervals.append(interval)
            case .awake: awake += interval.duration
            case .core: core += interval.duration; asleepIntervals.append(interval)
            case .deep: deep += interval.duration; asleepIntervals.append(interval)
            case .rem: rem += interval.duration; asleepIntervals.append(interval)
            case .unspecified: asleepIntervals.append(interval)
            }
        }

        let asleep = unionDuration(asleepIntervals)
        guard asleep > 0,
              let bedtime = asleepIntervals.map(\.start).min(),
              let wake = asleepIntervals.map(\.end).max() else { return nil }

        return SleepNight(date: day, bedtime: bedtime, wakeTime: wake,
                          asleep: asleep, inBed: unionDuration(inBedIntervals),
                          core: core, deep: deep, rem: rem, awake: awake)
    }

    /// Durée totale d'intervalles en fusionnant les chevauchements.
    static func unionDuration(_ intervals: [DateInterval]) -> TimeInterval {
        let sorted = intervals.sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var current: DateInterval?
        for interval in sorted {
            if let c = current, interval.start <= c.end {
                current = DateInterval(start: c.start, end: max(c.end, interval.end))
            } else {
                if let c = current { total += c.duration }
                current = interval
            }
        }
        if let c = current { total += c.duration }
        return total
    }
}
