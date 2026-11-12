import Foundation

/// D'où vient l'estimation de la dépense d'une journée.
enum ExpenditureSource {
    /// Métabolisme de repos + énergie active mesurés (Apple Watch).
    case measured
    /// Métabolisme calculé (formule) + énergie active mesurée (iPhone).
    case partial
    /// Formule × niveau d'activité, aucune donnée mesurée.
    case estimate

    var label: String {
        switch self {
        case .measured: return "mesurée (Santé)"
        case .partial: return "partiellement mesurée"
        case .estimate: return "estimée (profil)"
        }
    }
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

/// Moteur de calcul : apports vs dépenses → tendance de poids.
///
/// Hypothèses (à garder en tête, ce sont des estimations) :
/// - ~7 700 kcal de surplus cumulé ≈ +1 kg (approximation classique, surtout valable pour la masse grasse).
/// - Dépense = énergie de repos + énergie active (Santé) + ~10 % des apports (coût de la digestion).
/// - Les journées sans aucun repas saisi sont ignorées (sinon fausse impression de déficit).
struct EnergyAnalysis {
    static let kcalPerKg = 7700.0
    static let neutralZone = 150.0 // kcal/jour considérées comme « équilibre »
    static let minDaysForVerdict = 3

    let weightKg: Double
    let bmr: Double
    let todayIntake: Macros
    let todayTarget: Double
    let todayTargetSource: ExpenditureSource
    let proteinTarget: Double
    let targetSurplus: Double
    /// Jours complets (avant aujourd'hui) avec au moins un repas saisi, 14 derniers jours.
    let history: [DayBalance]
    let weightTrendKgPerWeek: Double?

    @MainActor
    init(entries: [FoodEntry], health: HealthDataStore, profile: ProfileStore, now: Date = Date()) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        weightKg = profile.effectiveWeight(healthWeight: health.latestWeightKg)
        bmr = profile.bmr(weightKg: weightKg)
        proteinTarget = weightKg * profile.proteinPerKg
        targetSurplus = profile.targetSurplus

        // Apports par jour
        var intakeByDay: [Date: Macros] = [:]
        for e in entries {
            let d = cal.startOfDay(for: e.date)
            intakeByDay[d, default: .zero] = intakeByDay[d, default: .zero] + e.macros
        }
        todayIntake = intakeByDay[today] ?? .zero

        // Historique des balances (14 jours complets)
        var history: [DayBalance] = []
        for offset in (1...14).reversed() {
            guard let d = cal.date(byAdding: .day, value: -offset, to: today),
                  let intake = intakeByDay[d], intake.kcal > 0 else { continue }
            let (exp, src) = Self.expenditure(day: health.day(d), bmr: bmr,
                                              activityFactor: profile.activityFactor, intake: intake.kcal)
            history.append(DayBalance(date: d, intake: intake.kcal, expenditure: exp, source: src))
        }
        self.history = history

        // Objectif du jour : dépense habituelle (7 derniers jours) + surplus visé
        let recentBases: [Double] = (1...7).compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return Self.baseExpenditure(day: health.day(d), bmr: bmr)
        }
        if recentBases.count >= 3 {
            let avg = recentBases.reduce(0, +) / Double(recentBases.count)
            // apport A tel que A − (base + 10 % A) = surplus  →  A = (base + surplus) / 0,9
            todayTarget = (avg + profile.targetSurplus) / 0.9
            todayTargetSource = .measured
        } else {
            todayTarget = bmr * profile.activityFactor + profile.targetSurplus
            todayTargetSource = .estimate
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

    // MARK: - Calculs

    /// Dépense sans le coût de digestion.
    static func baseExpenditure(day: DayHealth?, bmr: Double) -> Double? {
        guard let d = day else { return nil }
        // Données de repos incomplètes (montre retirée) → on prend la formule.
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

    /// Pente (kg/semaine) des pesées des 28 derniers jours, par régression linéaire.
    static func weightTrend(_ points: [WeightPoint], now: Date) -> Double? {
        guard let limit = Calendar.current.date(byAdding: .day, value: -28, to: now) else { return nil }
        let recent = points.filter { $0.date >= limit }
        guard recent.count >= 3,
              let first = recent.first?.date, let last = recent.last?.date,
              last.timeIntervalSince(first) >= 7 * 86400 else { return nil }
        let xs = recent.map { $0.date.timeIntervalSince(first) / 86400 }
        let ys = recent.map(\.kg)
        let n = Double(recent.count)
        let mx = xs.reduce(0, +) / n
        let my = ys.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (x, y) in zip(xs, ys) {
            num += (x - mx) * (y - my)
            den += (x - mx) * (x - mx)
        }
        guard den > 0 else { return nil }
        return num / den * 7
    }
}
