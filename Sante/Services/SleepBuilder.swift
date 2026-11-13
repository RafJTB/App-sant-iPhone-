import Foundation
import HealthKit

/// Adaptateur HealthKit → SleepCore (la logique est dans SleepCore, testée en CI).
enum SleepBuilder {
    static func nights(from samples: [HKCategorySample], calendar: Calendar = .current) -> [SleepNight] {
        let segments: [SleepSegment] = samples.compactMap { s in
            guard let value = HKCategoryValueSleepAnalysis(rawValue: s.value) else { return nil }
            let kind: SleepSegment.Kind
            switch value {
            case .inBed: kind = .inBed
            case .awake: kind = .awake
            case .asleepCore: kind = .core
            case .asleepDeep: kind = .deep
            case .asleepREM: kind = .rem
            case .asleepUnspecified: kind = .unspecified
            @unknown default: return nil
            }
            return SleepSegment(start: s.startDate, end: s.endDate, kind: kind,
                                source: s.sourceRevision.source.bundleIdentifier)
        }
        return SleepCore.nights(from: segments, calendar: calendar)
    }
}
