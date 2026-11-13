import Foundation

/// D'où vient l'estimation de la dépense.
enum ExpenditureSource {
    /// Calibrée sur la balance : apports réels − variation de poids réelle (la plus fiable).
    case calibrated
    /// Métabolisme de repos + énergie active mesurés (Apple Watch).
    case measured
    /// Métabolisme calculé (formule) + énergie active mesurée (iPhone).
    case partial
    /// Formule × niveau d'activité, aucune donnée mesurée.
    case estimate
}

struct DayBalance: Identifiable {
    let date: Date
    let intake: Double
    let expenditure: Double
    let source: ExpenditureSource
    var balance: Double { intake - expenditure }
    var id: Date { date }
}

enum Verdict {
    case notEnoughData(daysLogged: Int)
    case gaining(kgPerWeek: Double)
    case maintaining
    case losing(kgPerWeek: Double)
}

/// Dépense réelle déduite de la balance (principe des apps à objectif adaptatif).
/// Si tu as mangé en moyenne A kcal/jour et que ton poids a varié de P kg/jour,
/// ta dépense réelle ≈ A − P × 7 700.
struct CalibratedExpenditure {
    let kcalPerDay: Double
    let daysUsed: Int
    let weighIns: Int
    /// Ce qu'annonçait la montre sur les mêmes jours (pour comparaison).
    let watchEstimate: Double?
}

/// Progression vers la calibration.
struct CalibrationProgress {
    let completeDays: Int
    let weighIns: Int
    let spanDays: Int
}

/// Moteur de calcul : apports vs dépense → tendance de poids.
///
/// Hypothèses (ce sont des estimations) :
/// - ~7 700 kcal de surplus cumulé ≈ +1 kg.
/// - Sans calibration : dépense = énergie de repos + active (Santé) + ~10 % des apports (digestion).
/// - Seules les journées **validées** comptent : une journée à moitié saisie fausserait tout.
struct EnergyAnalysis {
    static let kcalPerKg = 7700.0
    static let neutralZone = 150.0
    static let minDaysForVerdict = 3
    static let calibrationWindow = 28
    static let minCalibrationDays = 14
    static let minWeighIns = 4
    static let lowDayRatio = 0.6

    let weightKg: Double
    let bmr: Double
    let todayIntake: Macros
    let todayTarget: Double
    let todayTargetSource: ExpenditureSource
    let proteinTarget: Double
    let targetSurplus: Double
    /// Journées validées des 14 derniers jours.
    let history: [DayBalance]
    let weightTrendKgPerWeek: Double?
    let calibrated: CalibratedExpenditure?
    let calibrationProgress: CalibrationProgress
    /// Apport typique d'une journée complète (médiane), pour repérer les journées incomplètes.
    let typicalIntake: Double?
    let isTodayComplete: Bool

    @MainActor
    init(entries: [FoodEntry], completedDays: Set<Date>, health: HealthDataStore, profile: ProfileStore, now: Date = Date()) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        let weight = profile.effectiveWeight(healthWeight: health.latestWeightKg)
        let bmr = profile.bmr(weightKg: weight)
        let activityFactor = profile.activityFactor
        let surplus = profile.targetSurplus
        weightKg = weight
        self.bmr = bmr
        proteinTarget = weight * profile.proteinPerKg
        targetSurplus = surplus
        isTodayComplete = completedDays.contains(today)

        var intakeByDay: [Date: Macros] = [:]
        for e in entries {
            let d = cal.startOfDay(for: e.date)
            intakeByDay[d, default: .zero] = intakeByDay[d, default: .zero] + e.macros
        }
        todayIntake = intakeByDay[today] ?? .zero

        // Journées complètes passées avec des apports
        func completeIntake(_ d: Date) -> Double? {
            guard completedDays.contains(d), let i = intakeByDay[d], i.kcal > 0 else { return nil }
            return i.kcal
        }

        let recentComplete = (1...28).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }.compactMap(completeIntake)
        if recentComplete.count >= 3 {
            let sorted = recentComplete.sorted()
            typicalIntake = sorted[sorted.count / 2]
        } else {
            typicalIntake = nil
        }

        // --- Calibration sur la balance ---
        let windowStart = cal.date(byAdding: .day, value: -Self.calibrationWindow, to: today)!
        let windowDays = (1...Self.calibrationWindow).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        let windowIntakes = windowDays.compactMap { d in completeIntake(d).map { (d, $0) } }
        let windowWeights = health.weights.filter { $0.date >= windowStart && $0.date < today }
        let span: Int = {
            guard let a = windowWeights.map(\.date).min(), let b = windowWeights.map(\.date).max() else { return 0 }
            return Int(b.timeIntervalSince(a) / 86400)
        }()
        calibrationProgress = CalibrationProgress(completeDays: windowIntakes.count, weighIns: windowWeights.count, spanDays: span)

        var calibrated: CalibratedExpenditure?
        if windowIntakes.count >= Self.minCalibrationDays,
           windowWeights.count >= Self.minWeighIns, span >= 14,
           let slope = WeightTrend.slopePerDay(windowWeights) {
            let avgIntake = windowIntakes.map(\.1).reduce(0, +) / Double(windowIntakes.count)
            let tdee = avgIntake - slope * Self.kcalPerKg
            // Garde-fou : résultat physiologiquement plausible uniquement
            if tdee > bmr * 1.05 && tdee < bmr * 2.6 {
                let watch: [Double] = windowIntakes.compactMap { d, intake in
                    Self.baseExpenditure(day: health.day(d), bmr: bmr).map { $0 + 0.1 * intake }
                }
                calibrated = CalibratedExpenditure(
                    kcalPerDay: tdee,
                    daysUsed: windowIntakes.count,
                    weighIns: windowWeights.count,
                    watchEstimate: watch.count >= 7 ? watch.reduce(0, +) / Double(watch.count) : nil
                )
            }
        }
        self.calibrated = calibrated

        // --- Historique des balances (14 jours validés) ---
        var history: [DayBalance] = []
        for offset in (1...14).reversed() {
            guard let d = cal.date(byAdding: .day, value: -offset, to: today), let intake = completeIntake(d) else { continue }
            if let c = calibrated {
                history.append(DayBalance(date: d, intake: intake, expenditure: c.kcalPerDay, source: .calibrated))
            } else {
                let (exp, src) = Self.expenditure(day: health.day(d), bmr: bmr, activityFactor: activityFactor, intake: intake)
                history.append(DayBalance(date: d, intake: intake, expenditure: exp, source: src))
            }
        }
        self.history = history

        // --- Objectif du jour ---
        if let c = calibrated {
            todayTarget = c.kcalPerDay + surplus
            todayTargetSource = .calibrated
        } else {
            let recentBases: [Double] = (1...7).compactMap { offset in
                guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
                return Self.baseExpenditure(day: health.day(d), bmr: bmr)
            }
            if recentBases.count >= 3 {
                let avg = recentBases.reduce(0, +) / Double(recentBases.count)
                // A − (base + 10 % A) = surplus  →  A = (base + surplus) / 0,9
                todayTarget = (avg + surplus) / 0.9
                todayTargetSource = .measured
            } else {
                todayTarget = bmr * activityFactor + surplus
                todayTargetSource = .estimate
            }
        }

        weightTrendKgPerWeek = Self.weightTrend(health.weights, now: now)
    }

    // MARK: - Résultats

    var last7: [DayBalance] {
        guard let limit = Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: Date())) else { return [] }
        return history.filter { $0.date >= limit }
    }

    var averageBalance: Double? {
        let days = last7
        guard days.count >= Self.minDaysForVerdict else { return nil }
        return days.map(\.balance).reduce(0, +) / Double(days.count)
    }

    var projectedKgPerWeek: Double? {
        averageBalance.map { $0 * 7 / Self.kcalPerKg }
    }

    var verdict: Verdict {
        guard let avg = averageBalance, let kg = projectedKgPerWeek else {
            return .notEnoughData(daysLogged: last7.count)
        }
        if avg > Self.neutralZone { return .gaining(kgPerWeek: kg) }
        if avg < -Self.neutralZone { return .losing(kgPerWeek: kg) }
        return .maintaining
    }

    var remainingToday: Double { todayTarget - todayIntake.kcal }

    /// Vrai si un total paraît trop bas pour une journée complète.
    func looksIncomplete(_ kcal: Double) -> Bool {
        guard let typical = typicalIntake else { return kcal < bmr }
        return kcal < typical * Self.lowDayRatio
    }

    var targetExplanation: String {
        switch todayTargetSource {
        case .calibrated:
            let days = calibrated?.daysUsed ?? 0
            return "Objectif : ta dépense réelle, calibrée sur ta balance (\(days) jours), + \(Fmt.kcal(targetSurplus)) kcal de surplus."
        case .measured, .partial:
            return "Objectif : dépense moyenne mesurée sur 7 jours + \(Fmt.kcal(targetSurplus)) kcal de surplus. Il se calibrera sur ta balance après 14 journées complètes."
        case .estimate:
            return "Objectif : dépense estimée depuis ton profil + \(Fmt.kcal(targetSurplus)) kcal de surplus."
        }
    }

    // MARK: - Calculs

    static func baseExpenditure(day: DayHealth?, bmr: Double) -> Double? {
        guard let d = day else { return nil }
        if d.basalKcal >= 0.7 * bmr { return d.basalKcal + d.activeKcal }
        if d.activeKcal > 50 { return bmr + d.activeKcal }
        return nil
    }

    static func expenditure(day: DayHealth?, bmr: Double, activityFactor: Double, intake: Double) -> (Double, ExpenditureSource) {
        let digestion = 0.1 * intake
        if let d = day, d.basalKcal >= 0.7 * bmr {
            return (d.basalKcal + d.activeKcal + digestion, .measured)
        }
        if let d = day, d.activeKcal > 50 {
            return (bmr + d.activeKcal + digestion, .partial)
        }
        return (bmr * activityFactor, .estimate)
    }

    /// Pente (kg/semaine) des pesées des 28 derniers jours.
    static func weightTrend(_ points: [WeightPoint], now: Date) -> Double? {
        guard let limit = Calendar.current.date(byAdding: .day, value: -28, to: now) else { return nil }
        let recent = points.filter { $0.date >= limit }
        guard recent.count >= 3,
              let first = recent.map(\.date).min(), let last = recent.map(\.date).max(),
              last.timeIntervalSince(first) >= 7 * 86400 else { return nil }
        return WeightTrend.slopePerDay(recent).map { $0 * 7 }
    }
}
