import Foundation
import HealthKit

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

enum SleepBuilder {
    /// Regroupe les échantillons HealthKit en nuits.
    /// Un échantillon commencé après 18 h compte pour la nuit du lendemain.
    static func nights(from samples: [HKCategorySample], calendar: Calendar = .current) -> [SleepNight] {
        let groups = Dictionary(grouping: samples) { sample in
            calendar.startOfDay(for: sample.startDate.addingTimeInterval(6 * 3600))
        }
        return groups
            .compactMap { day, group in build(day: day, samples: group) }
            .sorted { $0.date < $1.date }
    }

    private static func value(_ s: HKCategorySample) -> HKCategoryValueSleepAnalysis? {
        HKCategoryValueSleepAnalysis(rawValue: s.value)
    }

    private static func build(day: Date, samples: [HKCategorySample]) -> SleepNight? {
        let stageValues: Set<HKCategoryValueSleepAnalysis> = [.asleepCore, .asleepDeep, .asleepREM]

        // Si une source fournit les phases (Apple Watch), on ne garde qu'elle
        // pour éviter de compter deux fois la même nuit (iPhone + Watch).
        var used = samples
        let staged = samples.filter { s in
            guard let v = value(s) else { return false }
            return stageValues.contains(v)
        }
        if !staged.isEmpty {
            let sources = Set(staged.map { $0.sourceRevision.source.bundleIdentifier })
            used = samples.filter { s in
                sources.contains(s.sourceRevision.source.bundleIdentifier) || value(s) == .inBed
            }
        }

        var asleepIntervals: [DateInterval] = []
        var inBedIntervals: [DateInterval] = []
        var core = 0.0, deep = 0.0, rem = 0.0, awake = 0.0

        for s in used {
            guard let v = value(s), s.endDate > s.startDate else { continue }
            let interval = DateInterval(start: s.startDate, end: s.endDate)
            switch v {
            case .inBed:
                inBedIntervals.append(interval)
            case .awake:
                awake += interval.duration
            case .asleepCore:
                core += interval.duration
                asleepIntervals.append(interval)
            case .asleepDeep:
                deep += interval.duration
                asleepIntervals.append(interval)
            case .asleepREM:
                rem += interval.duration
                asleepIntervals.append(interval)
            case .asleepUnspecified:
                asleepIntervals.append(interval)
            @unknown default:
                break
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
