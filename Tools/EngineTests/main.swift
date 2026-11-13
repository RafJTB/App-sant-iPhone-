// Tests du moteur de calcul (EnergyCore, WeightTrend, SleepCore), lancés par la CI sur macOS.
import Foundation

var failures = 0
func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    if condition { print("✅ \(name)") } else { failures += 1; print("❌ \(name) \(detail)") }
}
func near(_ a: Double?, _ b: Double, tol: Double = 1) -> Bool { a.map { abs($0 - b) <= tol } ?? false }

let cal = Calendar.current
let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 12))!
let today = cal.startOfDay(for: now)
func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: today)! }
let bmr = 1750.0

func inputs(intake: (Int) -> Double?, completed: (Int) -> Bool = { _ in true },
            weight: ((Int) -> Double?)? = nil, watch: Bool = false) -> EnergyCore.Inputs {
    var byDay: [Date: Double] = [:]
    var done = Set<Date>()
    var weights: [WeightPoint] = []
    var health: [DayHealth] = []
    for n in 1...28 {
        if let k = intake(n) { byDay[day(n)] = k }
        if completed(n) { done.insert(day(n)) }
        if let w = weight?(n) { weights.append(WeightPoint(date: day(n).addingTimeInterval(7.5 * 3600), kg: w)) }
        if watch { health.append(DayHealth(date: day(n), activeKcal: 700, basalKcal: 1750)) }
    }
    return .init(intakeByDay: byDay, completedDays: done, days: health, weights: weights,
                 bmr: bmr, activityFactor: 1.55, surplus: 300, now: now, calendar: cal)
}

// 1. Poids stable + 3 000 kcal/jour → dépense réelle 3 000
do {
    let r = EnergyCore.compute(inputs(intake: { _ in 3000 }, weight: { $0 % 2 == 0 ? 72 : nil }))
    check("Poids stable : dépense calibrée = apports", near(r.calibrated?.kcalPerDay, 3000), "\(String(describing: r.calibrated?.kcalPerDay))")
    check("Objectif = dépense + surplus", near(r.todayTarget, 3300) && r.todayTargetSource == .calibrated)
    check("Balance nulle → poids stable", r.verdict == .maintaining)
}

// 2. +0,05 kg/jour avec 3 000 kcal → dépense 2 615, verdict +0,35 kg/semaine
do {
    let r = EnergyCore.compute(inputs(intake: { _ in 3000 }, weight: { 72 + Double(28 - $0) * 0.05 }))
    check("Prise de poids : dépense = 3000 − 0,05 × 7700", near(r.calibrated?.kcalPerDay, 2615), "\(String(describing: r.calibrated?.kcalPerDay))")
    check("Projection ≈ +0,35 kg/semaine", near(r.projectedKgPerWeek, 0.35, tol: 0.01))
    if case .gaining = r.verdict { check("Verdict : prise de poids", true) } else { check("Verdict : prise de poids", false, "\(r.verdict)") }
    check("Tendance réelle ≈ +0,35 kg/semaine", near(r.weightTrendKgPerWeek, 0.35, tol: 0.01))
}

// 3. Couverture insuffisante (15 journées validées) → pas de calibration, on garde la montre
do {
    let r = EnergyCore.compute(inputs(intake: { _ in 3000 }, completed: { $0 <= 15 }, weight: { _ in 72 }, watch: true))
    check("15/28 journées : pas de calibration", r.calibrated == nil && r.calibrationProgress.completeDays == 15)
    check("Objectif montre = (2450 + 300) / 0,9", near(r.todayTarget, 2750 / 0.9) && r.todayTargetSource == .measured)
}

// 4. Seuil exact : 20 journées validées → calibration active
do {
    let r = EnergyCore.compute(inputs(intake: { _ in 3000 }, completed: { $0 <= 20 }, weight: { _ in 72 }))
    check("20/28 journées : calibration active", r.calibrated != nil)
}

// 5. Journée non validée ignorée, même avec des apports
do {
    let r = EnergyCore.compute(inputs(intake: { $0 == 2 ? 500 : 3000 }, completed: { $0 != 2 }, watch: true))
    check("Journée non validée absente de l'historique", !r.history.contains { $0.date == day(2) } && r.history.count == 13)
}

// 6. Montre : 2 400 kcal mangées, dépense 1750 + 700 + 240 → déficit de 290
do {
    let r = EnergyCore.compute(inputs(intake: { _ in 2400 }, completed: { $0 <= 7 }, watch: true))
    check("Balance montre = −290 kcal", near(r.averageBalance, -290))
    if case .losing = r.verdict { check("Verdict : perte de poids", true) } else { check("Verdict : perte de poids", false, "\(r.verdict)") }
}

// 7. Pas assez de journées validées
do {
    let r = EnergyCore.compute(inputs(intake: { _ in 3000 }, completed: { $0 <= 2 }, watch: true))
    check("2 journées : pas de verdict", r.verdict == .notEnoughData(daysLogged: 2))
}

// 8. Aucune donnée Santé → formule × activité
do {
    let r = EnergyCore.compute(inputs(intake: { _ in 3000 }, completed: { $0 <= 5 }))
    check("Sans Santé : objectif = BMR × 1,55 + 300", near(r.todayTarget, bmr * 1.55 + 300) && r.todayTargetSource == .estimate)
    check("Sans Santé : balance = 3000 − BMR × 1,55", near(r.averageBalance, 3000 - bmr * 1.55))
}

// 9. Garde-fou : pesées incohérentes (−10 kg en 4 semaines) → calibration rejetée
do {
    let r = EnergyCore.compute(inputs(intake: { _ in 3000 }, weight: { 72 - Double(28 - $0) * 10 / 27 }))
    check("Pesées aberrantes : calibration rejetée", r.calibrated == nil)
}

// 10. Apport typique = médiane
do {
    let r = EnergyCore.compute(inputs(intake: { $0 <= 3 ? [0, 2000, 3000, 9000][$0] : nil }, completed: { $0 <= 3 }))
    check("Apport typique = médiane (3000)", near(r.typicalIntake, 3000))
}

// 11. Lissage du poids
do {
    let pts = (0..<10).map { WeightPoint(date: day(10 - $0), kg: 70 + Double($0) * 0.1) }
    check("Pente linéaire exacte (0,1 kg/jour)", near(WeightTrend.slopePerDay(pts), 0.1, tol: 0.0001))
    let s = WeightTrend.smoothed(pts)
    // moyenne des 7 derniers jours : 70,3 … 70,9 → 70,6
    check("Moyenne glissante 7 jours", s.count == 10 && near(s.last?.trend, 70.6, tol: 0.0001), "\(String(describing: s.last?.trend))")
    let twoSameDay = [WeightPoint(date: day(1), kg: 70), WeightPoint(date: day(1).addingTimeInterval(3600), kg: 71)]
    check("Deux pesées le même jour → moyenne", near(WeightTrend.smoothed(twoSameDay).first?.raw, 70.5, tol: 0.0001))
}

// 12. Sommeil : Watch (phases) + iPhone (doublon) → pas de double comptage
do {
    let bed = day(1).addingTimeInterval(23 * 3600)          // hier 23:00
    func seg(_ fromH: Double, _ toH: Double, _ kind: SleepSegment.Kind, _ src: String) -> SleepSegment {
        SleepSegment(start: bed.addingTimeInterval(fromH * 3600), end: bed.addingTimeInterval(toH * 3600), kind: kind, source: src)
    }
    let segments = [
        seg(0, 2, .core, "watch"), seg(2, 3.5, .deep, "watch"), seg(3.5, 4, .awake, "watch"),
        seg(4, 6, .rem, "watch"), seg(6, 8, .core, "watch"),
        seg(0, 8, .unspecified, "iphone"), seg(-0.5, 8.5, .inBed, "iphone"),
    ]
    let nights = SleepCore.nights(from: segments, calendar: cal)
    check("Une seule nuit, rattachée au jour du réveil", nights.count == 1 && nights.first?.date == today)
    check("Sommeil = 7 h 30 (Watch seule, sans doublon iPhone)", near(nights.first?.asleep, 7.5 * 3600))
    check("Phases : profond 1 h 30, paradoxal 2 h, éveillé 30 min",
          near(nights.first?.deep, 5400) && near(nights.first?.rem, 7200) && near(nights.first?.awake, 1800))
    check("Temps au lit = 9 h", near(nights.first?.inBed, 9 * 3600))
    // iPhone seul, deux échantillons qui se chevauchent
    let phone = [seg(0, 5, .unspecified, "iphone"), seg(4, 8, .unspecified, "iphone")]
    check("Chevauchements fusionnés (8 h, pas 9 h)", near(SleepCore.nights(from: phone, calendar: cal).first?.asleep, 8 * 3600))
    // sieste l'après-midi rattachée au jour même
    let nap = [SleepSegment(start: today.addingTimeInterval(14 * 3600), end: today.addingTimeInterval(15 * 3600), kind: .unspecified, source: "iphone")]
    check("Sieste de 14 h rattachée au jour même", SleepCore.nights(from: nap, calendar: cal).first?.date == today)
}

print(failures == 0 ? "\nTous les tests passent." : "\n\(failures) test(s) en échec.")
exit(failures == 0 ? 0 : 1)
