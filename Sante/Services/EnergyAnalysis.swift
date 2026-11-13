import Foundation

/// Assemble les données de l'app (repas, Santé, profil) et délègue le calcul à EnergyCore.
struct EnergyAnalysis {
    static let minDaysForVerdict = EnergyCore.minDaysForVerdict
    static let minCalibrationDays = EnergyCore.minCalibrationDays
    static let minWeighIns = EnergyCore.minWeighIns
    static let calibrationWindow = EnergyCore.calibrationWindow
    static let lowDayRatio = EnergyCore.lowDayRatio

    let weightKg: Double
    let bmr: Double
    let todayIntake: Macros
    let proteinTarget: Double
    let targetSurplus: Double
    let result: EnergyCore.Result

    @MainActor
    init(entries: [FoodEntry], completedDays: Set<Date>, health: HealthDataStore, profile: ProfileStore, now: Date = Date()) {
        let cal = Calendar.current
        let weight = profile.effectiveWeight(healthWeight: health.latestWeightKg)
        let bmr = profile.bmr(weightKg: weight)
        weightKg = weight
        self.bmr = bmr
        proteinTarget = weight * profile.proteinPerKg
        targetSurplus = profile.targetSurplus

        var macrosByDay: [Date: Macros] = [:]
        for e in entries {
            let d = cal.startOfDay(for: e.date)
            macrosByDay[d, default: .zero] = macrosByDay[d, default: .zero] + e.macros
        }
        todayIntake = macrosByDay[cal.startOfDay(for: now)] ?? .zero

        result = EnergyCore.compute(.init(
            intakeByDay: macrosByDay.mapValues(\.kcal),
            completedDays: completedDays,
            days: health.days,
            weights: health.weights,
            bmr: bmr,
            activityFactor: profile.activityFactor,
            surplus: profile.targetSurplus,
            now: now
        ))
    }

    var todayTarget: Double { result.todayTarget }
    var todayTargetSource: ExpenditureSource { result.todayTargetSource }
    var history: [DayBalance] { result.history }
    var last7: [DayBalance] { result.last7 }
    var averageBalance: Double? { result.averageBalance }
    var projectedKgPerWeek: Double? { result.projectedKgPerWeek }
    var verdict: Verdict { result.verdict }
    var weightTrendKgPerWeek: Double? { result.weightTrendKgPerWeek }
    var calibrated: CalibratedExpenditure? { result.calibrated }
    var calibrationProgress: CalibrationProgress { result.calibrationProgress }
    var remainingToday: Double { todayTarget - todayIntake.kcal }

    var targetExplanation: String {
        switch todayTargetSource {
        case .calibrated:
            let days = calibrated?.daysUsed ?? 0
            return "Objectif : ta dépense réelle, calibrée sur ta balance (\(days) journées sur \(Self.calibrationWindow)), + \(Fmt.kcal(targetSurplus)) kcal de surplus."
        case .measured, .partial:
            return "Objectif : dépense moyenne mesurée sur 7 jours + \(Fmt.kcal(targetSurplus)) kcal de surplus. Il se calibrera sur ta balance après \(Self.minCalibrationDays) journées validées."
        case .estimate:
            return "Objectif : dépense estimée depuis ton profil + \(Fmt.kcal(targetSurplus)) kcal de surplus."
        }
    }
}
