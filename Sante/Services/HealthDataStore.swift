import Foundation
import HealthKit

/// Accès en lecture seule à HealthKit.
@MainActor
final class HealthDataStore: ObservableObject {
    private let store = HKHealthStore()

    @Published private(set) var days: [DayHealth] = []
    @Published private(set) var nights: [SleepNight] = []
    @Published private(set) var workouts: [WorkoutSummary] = []
    @Published private(set) var weights: [WeightPoint] = []
    @Published private(set) var latestWeightKg: Double?
    @Published private(set) var heightCm: Double?
    @Published private(set) var birthYear: Int?
    @Published private(set) var isMale: Bool?
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdate: Date?
    @Published var errorMessage: String?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static let historyDays = 30

    /// Seule donnée écrite par l'app : les pesées saisies dans l'app.
    private static var shareTypes: Set<HKSampleType> {
        [HKQuantityType(.bodyMass)]
    }

    private static var readTypes: Set<HKObjectType> {
        [
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.stepCount),
            HKQuantityType(.appleExerciseTime),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.distanceSwimming),
            HKQuantityType(.bodyMass),
            HKQuantityType(.height),
            HKObjectType.workoutType(),
            HKCharacteristicType(.dateOfBirth),
            HKCharacteristicType(.biologicalSex),
        ]
    }

    // MARK: - Accès pratique

    func day(_ date: Date) -> DayHealth? {
        days.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    var today: DayHealth? { day(Date()) }

    /// Nuit la plus récente disponible.
    var lastNight: SleepNight? { nights.last }

    // MARK: - Chargement

    func requestAuthorizationAndLoad() async {
        guard isAvailable else {
            errorMessage = "Les données Santé ne sont pas disponibles sur cet appareil."
            return
        }
        do {
            try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
        } catch {
            errorMessage = "Autorisation Santé impossible : \(error.localizedDescription)"
            return
        }
        await reload()
    }

    func reload() async {
        guard isAvailable, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let n = Self.historyDays
        async let active = dailySums(.activeEnergyBurned, unit: .kilocalorie(), days: n)
        async let basal = dailySums(.basalEnergyBurned, unit: .kilocalorie(), days: n)
        async let steps = dailySums(.stepCount, unit: .count(), days: n)
        async let exercise = dailySums(.appleExerciseTime, unit: .minute(), days: n)
        async let sleep = sleepSamples(days: n + 1)
        async let sport = loadWorkouts(days: n)
        async let weightHistory = quantitySamples(.bodyMass, days: 90)
        async let lastWeight = latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo))
        async let lastHeight = latestQuantity(.height, unit: .meterUnit(with: .centi))

        let (a, b, s, e) = await (active, basal, steps, exercise)
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -(n - 1), to: cal.startOfDay(for: Date()))!
        days = (0..<n).compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: offset, to: start) else { return nil }
            return DayHealth(date: d,
                             activeKcal: a[d] ?? 0,
                             basalKcal: b[d] ?? 0,
                             steps: s[d] ?? 0,
                             exerciseMinutes: e[d] ?? 0)
        }

        let limit = cal.date(byAdding: .day, value: -n, to: Date())!
        nights = SleepBuilder.nights(from: await sleep).filter { $0.date >= limit }
        workouts = await sport
        weights = (await weightHistory).map {
            WeightPoint(date: $0.startDate, kg: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)))
        }
        latestWeightKg = await lastWeight
        heightCm = await lastHeight

        if let comps = try? store.dateOfBirthComponents(), let year = comps.year {
            birthYear = year
        }
        if let sex = try? store.biologicalSex().biologicalSex {
            switch sex {
            case .male: isMale = true
            case .female: isMale = false
            default: break
            }
        }
        lastUpdate = Date()
    }

    // MARK: - Écriture

    /// Enregistre une pesée dans l'app Santé, puis recharge les données.
    func saveWeight(_ kg: Double, date: Date = Date()) async throws {
        let type = HKQuantityType(.bodyMass)
        guard store.authorizationStatus(for: type) == .sharingAuthorized else {
            throw NSError(domain: "Sante", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "L'app n'a pas le droit d'enregistrer ton poids. Autorise-le dans Réglages › Santé › Accès aux données et appareils."])
        }
        let sample = HKQuantitySample(type: type,
                                      quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg),
                                      start: date, end: date)
        try await store.save(sample)
        await reload()
    }

    // MARK: - Requêtes

    /// Somme par jour d'une donnée cumulative (calories, pas…), indexée par début de journée.
    private func dailySums(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async -> [Date: Double] {
        let cal = Calendar.current
        let end = Date()
        let start = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: end))!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: predicate),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        do {
            let collection = try await descriptor.result(for: store)
            var out: [Date: Double] = [:]
            collection.enumerateStatistics(from: start, to: end) { stats, _ in
                out[cal.startOfDay(for: stats.startDate)] = stats.sumQuantity()?.doubleValue(for: unit) ?? 0
            }
            return out
        } catch {
            return [:]
        }
    }

    private func quantitySamples(_ id: HKQuantityTypeIdentifier, days: Int) async -> [HKQuantitySample] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id),
                                         predicate: HKQuery.predicateForSamples(withStart: start, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        return (try? await descriptor.result(for: store)) ?? []
    }

    private func latestQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id), predicate: nil)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        guard let sample = try? await descriptor.result(for: store).first else { return nil }
        return sample.quantity.doubleValue(for: unit)
    }

    private func sleepSamples(days: Int) async -> [HKCategorySample] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis),
                                         predicate: HKQuery.predicateForSamples(withStart: start, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        return (try? await descriptor.result(for: store)) ?? []
    }

    private func loadWorkouts(days: Int) async -> [WorkoutSummary] {
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 100
        )
        let results = (try? await descriptor.result(for: store)) ?? []
        return results.map(WorkoutSummary.init(workout:))
    }
}
