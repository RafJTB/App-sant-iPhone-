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

enum Verdict: Equatable {
    case notEnoughData(daysLogged: Int)
    case gaining(kgPerWeek: Double)
    case maintaining
    case losing(kgPerWeek: Double)
}

/// Dépense réelle déduite de la balance.
/// Si tu as mangé en moyenne A kcal/jour et que ton poids a varié de P kg/jour,
/// ta dépense réelle ≈ A − P × 7 700.
struct CalibratedExpenditure {
    let kcalPerDay: Double
    let daysUsed: Int
    let weighIns: Int
    /// Ce qu'annonçait la montre sur les mêmes jours (pour comparaison).
    let watchEstimate: Double?
    /// Part des jours de la fenêtre qui sont validés (0…1).
    var coverage: Double { Double(daysUsed) / Double(EnergyCore.calibrationWindow) }
}

struct CalibrationProgress {
    let completeDays: Int
    let weighIns: Int
    let spanDays: Int
}

/// Moteur de calcul pur (sans HealthKit ni SwiftData), testé en CI par Tools/EngineTests.
///
/// Hypothèses (ce sont des estimations) :
/// - ~7 700 kcal de surplus cumulé ≈ +1 kg.
/// - Sans calibration : dépense = énergie de repos + active (Santé) + ~10 % des apports (digestion).
/// - Seules les journées **validées** comptent.
enum EnergyCore {
    static let kcalPerKg = 7700.0
    static let neutralZone = 150.0
    static let minDaysForVerdict = 3
    static let calibrationWindow = 28
    /// 20 jours sur 28 : en dessous, les jours non saisis (souvent les week-ends,
    /// où l'on mange plus) biaisent la moyenne des apports vers le bas.
    static let minCalibrationDays = 20
    static let minWeighIns = 4
    static let minWeighInSpanDays = 14
    static let lowDayRatio = 0.6

    struct Inputs {
        /// kcal par jour (clé : début de journée).
        var intakeByDay: [Date: Double]
        var completedDays: Set<Date>
        var days: [DayHealth]
        var weights: [WeightPoint]
        var bmr: Double
        var activityFactor: Double
        var surplus: Double
        var now: Date
        var calendar: Calendar = .current
    }

    struct Result {
        let todayTarget: Double
        let todayTargetSource: ExpenditureSource
        /// Journées validées des 14 derniers jours.
        let history: [DayBalance]
        /// Journées validées des 7 derniers jours.
        let last7: [DayBalance]
        let weightTrendKgPerWeek: Double?
        let calibrated: CalibratedExpenditure?
        let calibrationProgress: CalibrationProgress
        /// Apport médian d'une journée validée.
        let typicalIntake: Double?
        let isTodayComplete: Bool

        var averageBalance: Double? {
            guard last7.count >= EnergyCore.minDaysForVerdict else { return nil }
            return last7.map(\.balance).reduce(0, +) / Double(last7.count)
        }

        var projectedKgPerWeek: Double? {
            averageBalance.map { $0 * 7 / EnergyCore.kcalPerKg }
        }

        var verdict: Verdict {
            guard let avg = averageBalance, let kg = projectedKgPerWeek else {
                return .notEnoughData(daysLogged: last7.count)
            }
            if avg > EnergyCore.neutralZone { return .gaining(kgPerWeek: kg) }
            if avg < -EnergyCore.neutralZone { return .losing(kgPerWeek: kg) }
            return .maintaining
        }
    }

    static func compute(_ i: Inputs) -> Result {
        let cal = i.calendar
        let today = cal.startOfDay(for: i.now)
        func dayBefore(_ n: Int) -> Date? { cal.date(byAdding: .day, value: -n, to: today) }
        func health(_ d: Date) -> DayHealth? { i.days.first { cal.isDate($0.date, inSameDayAs: d) } }
        func completeIntake(_ d: Date) -> Double? {
            guard i.completedDays.contains(d), let kcal = i.intakeByDay[d], kcal > 0 else { return nil }
            return kcal
        }

        let windowDays = (1...calibrationWindow).compactMap(dayBefore)
        let windowIntakes = windowDays.compactMap { d in completeIntake(d).map { (d, $0) } }

        // Apport typique (médiane)
        var typical: Double?
        if windowIntakes.count >= 3 {
            let sorted = windowIntakes.map(\.1).sorted()
            typical = sorted[sorted.count / 2]
        }

        // --- Calibration sur la balance ---
        let windowStart = dayBefore(calibrationWindow) ?? today
        let windowWeights = i.weights.filter { $0.date >= windowStart && $0.date < today }
        let span: Int = {
            guard let a = windowWeights.map(\.date).min(), let b = windowWeights.map(\.date).max() else { return 0 }
            return Int(b.timeIntervalSince(a) / 86400)
        }()
        let progress = CalibrationProgress(completeDays: windowIntakes.count, weighIns: windowWeights.count, spanDays: span)

        var calibrated: CalibratedExpenditure?
        if windowIntakes.count >= minCalibrationDays,
           windowWeights.count >= minWeighIns, span >= minWeighInSpanDays,
           let slope = WeightTrend.slopePerDay(windowWeights) {
            let avgIntake = windowIntakes.map(\.1).reduce(0, +) / Double(windowIntakes.count)
            let tdee = avgIntake - slope * kcalPerKg
            // Garde-fou : résultat physiologiquement plausible uniquement
            if tdee > i.bmr * 1.05 && tdee < i.bmr * 2.6 {
                let watch: [Double] = windowIntakes.compactMap { d, intake in
                    baseExpenditure(day: health(d), bmr: i.bmr).map { $0 + 0.1 * intake }
                }
                calibrated = CalibratedExpenditure(
                    kcalPerDay: tdee,
                    daysUsed: windowIntakes.count,
                    weighIns: windowWeights.count,
                    watchEstimate: watch.count >= 7 ? watch.reduce(0, +) / Double(watch.count) : nil
                )
            }
        }

        // --- Historique des balances (14 jours validés) ---
        var history: [DayBalance] = []
        for offset in (1...14).reversed() {
            guard let d = dayBefore(offset), let intake = completeIntake(d) else { continue }
            if let c = calibrated {
                history.append(DayBalance(date: d, intake: intake, expenditure: c.kcalPerDay, source: .calibrated))
            } else {
                let (exp, src) = expenditure(day: health(d), bmr: i.bmr, activityFactor: i.activityFactor, intake: intake)
                history.append(DayBalance(date: d, intake: intake, expenditure: exp, source: src))
            }
        }
        let limit7 = dayBefore(7) ?? today
        let last7 = history.filter { $0.date >= limit7 }

        // --- Objectif du jour ---
        let target: Double
        let source: ExpenditureSource
        if let c = calibrated {
            target = c.kcalPerDay + i.surplus
            source = .calibrated
        } else {
            let bases = (1...7).compactMap(dayBefore).compactMap { baseExpenditure(day: health($0), bmr: i.bmr) }
            if bases.count >= 3 {
                let avg = bases.reduce(0, +) / Double(bases.count)
                // A − (base + 10 % A) = surplus  →  A = (base + surplus) / 0,9
                target = (avg + i.surplus) / 0.9
                source = .measured
            } else {
                target = i.bmr * i.activityFactor + i.surplus
                source = .estimate
            }
        }

        return Result(todayTarget: target, todayTargetSource: source, history: history, last7: last7,
                      weightTrendKgPerWeek: weightTrend(i.weights, now: i.now, calendar: cal),
                      calibrated: calibrated, calibrationProgress: progress,
                      typicalIntake: typical, isTodayComplete: i.completedDays.contains(today))
    }

    /// Dépense sans le coût de digestion.
    static func baseExpenditure(day: DayHealth?, bmr: Double) -> Double? {
        guard let d = day else { return nil }
        // Données de repos incomplètes (montre retirée) → formule.
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
        // Le facteur d'activité inclut déjà la digestion.
        return (bmr * activityFactor, .estimate)
    }

    /// Pente (kg/semaine) des pesées des 28 derniers jours.
    static func weightTrend(_ points: [WeightPoint], now: Date, calendar: Calendar = .current) -> Double? {
        guard let limit = calendar.date(byAdding: .day, value: -28, to: now) else { return nil }
        let recent = points.filter { $0.date >= limit }
        guard recent.count >= 3,
              let first = recent.map(\.date).min(), let last = recent.map(\.date).max(),
              last.timeIntervalSince(first) >= 7 * 86400 else { return nil }
        return WeightTrend.slopePerDay(recent).map { $0 * 7 }
    }
}
