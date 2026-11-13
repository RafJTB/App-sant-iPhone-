import Foundation

/// Lissage du poids : le poids varie de ±1 kg d'un jour à l'autre (eau, sel, digestion).
/// On fait la moyenne par jour, puis une moyenne glissante sur 7 jours.
enum WeightTrend {
    struct Point: Identifiable {
        let date: Date
        let raw: Double
        let trend: Double
        var id: Date { date }
    }

    static func smoothed(_ points: [WeightPoint], window: Int = 7) -> [Point] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: points) { cal.startOfDay(for: $0.date) }
        let daily = byDay
            .map { (day: $0.key, kg: $0.value.map(\.kg).reduce(0, +) / Double($0.value.count)) }
            .sorted { $0.day < $1.day }

        return daily.map { current in
            guard let start = cal.date(byAdding: .day, value: -(window - 1), to: current.day) else {
                return Point(date: current.day, raw: current.kg, trend: current.kg)
            }
            let inWindow = daily.filter { $0.day >= start && $0.day <= current.day }
            let mean = inWindow.map(\.kg).reduce(0, +) / Double(inWindow.count)
            return Point(date: current.day, raw: current.kg, trend: mean)
        }
    }

    /// Pente en kg/jour par régression linéaire.
    static func slopePerDay(_ points: [WeightPoint]) -> Double? {
        guard points.count >= 2, let first = points.map(\.date).min() else { return nil }
        let xs = points.map { $0.date.timeIntervalSince(first) / 86400 }
        let ys = points.map(\.kg)
        let n = Double(points.count)
        let mx = xs.reduce(0, +) / n
        let my = ys.reduce(0, +) / n
        var num = 0.0, den = 0.0
        for (x, y) in zip(xs, ys) {
            num += (x - mx) * (y - my)
            den += (x - mx) * (x - mx)
        }
        guard den > 0 else { return nil }
        return num / den
    }
}
