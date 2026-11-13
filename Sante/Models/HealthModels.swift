import Foundation

/// Données agrégées d'une journée, lues dans l'app Santé.
struct DayHealth: Identifiable {
    let date: Date
    var activeKcal: Double = 0
    var basalKcal: Double = 0
    var steps: Double = 0
    var exerciseMinutes: Double = 0
    var id: Date { date }
}

struct WeightPoint: Identifiable {
    let id = UUID()
    let date: Date
    let kg: Double
}
