import Foundation
import SwiftData

/// Les quatre repas de la journée.
enum Meal: String, CaseIterable, Identifiable, Codable {
    case breakfast, lunch, snack, dinner

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: return "Petit-déjeuner"
        case .lunch: return "Déjeuner"
        case .snack: return "Collation"
        case .dinner: return "Dîner"
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .snack: return "carrot.fill"
        case .dinner: return "moon.stars.fill"
        }
    }

    /// Repas proposé par défaut selon l'heure.
    static func suggested(for date: Date = Date()) -> Meal {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 4..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<18: return .snack
        default: return .dinner
        }
    }
}

/// Apports nutritionnels (totaux).
struct Macros: Equatable {
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    static let zero = Macros(kcal: 0, protein: 0, carbs: 0, fat: 0)

    static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(kcal: lhs.kcal + rhs.kcal,
               protein: lhs.protein + rhs.protein,
               carbs: lhs.carbs + rhs.carbs,
               fat: lhs.fat + rhs.fat)
    }

    static func * (lhs: Macros, factor: Double) -> Macros {
        Macros(kcal: lhs.kcal * factor,
               protein: lhs.protein * factor,
               carbs: lhs.carbs * factor,
               fat: lhs.fat * factor)
    }
}

/// Un aliment consommé, stocké localement (SwiftData) sur l'iPhone.
@Model
final class FoodEntry {
    var date: Date
    var name: String
    var mealRaw: String
    /// Grammes si `isGrams`, sinon nombre de portions.
    var quantity: Double
    var isGrams: Bool
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    init(date: Date, name: String, meal: Meal, quantity: Double, isGrams: Bool, macros: Macros) {
        self.date = date
        self.name = name
        self.mealRaw = meal.rawValue
        self.quantity = quantity
        self.isGrams = isGrams
        self.kcal = macros.kcal
        self.protein = macros.protein
        self.carbs = macros.carbs
        self.fat = macros.fat
    }

    var meal: Meal { Meal(rawValue: mealRaw) ?? .snack }

    var macros: Macros { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }

    var quantityLabel: String {
        if isGrams { return "\(Int(quantity.rounded())) g" }
        let q = quantity.formatted(.number.precision(.fractionLength(0...1)))
        return quantity <= 1 ? "\(q) portion" : "\(q) portions"
    }

    /// Permet de ré-ajouter rapidement un aliment déjà saisi.
    var asFoodItem: FoodItem {
        if isGrams && quantity > 0 {
            return FoodItem(id: "r-\(name.lowercased())", name: name,
                            base: macros * (100 / quantity), isPortion: false, defaultAmount: quantity)
        }
        let q = quantity > 0 ? quantity : 1
        return FoodItem(id: "r-\(name.lowercased())", name: name,
                        base: macros * (1 / q), isPortion: true, defaultAmount: q)
    }
}
