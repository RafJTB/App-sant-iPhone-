import Foundation
import SwiftData

/// Un aliment avec sa quantité, utilisé dans les repas habituels et les recettes.
struct TemplateItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// Grammes si `isGrams`, sinon nombre de portions.
    var quantity: Double
    var isGrams: Bool
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    init(name: String, quantity: Double, isGrams: Bool, macros: Macros) {
        self.name = name
        self.quantity = quantity
        self.isGrams = isGrams
        kcal = macros.kcal
        protein = macros.protein
        carbs = macros.carbs
        fat = macros.fat
    }

    init(entry: FoodEntry) {
        self.init(name: entry.name, quantity: entry.quantity, isGrams: entry.isGrams, macros: entry.macros)
    }

    var macros: Macros { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }

    var quantityLabel: String {
        isGrams ? "\(Int(quantity.rounded())) g" : "\(Fmt.number(quantity)) portion(s)"
    }
}

/// Encodage JSON des listes d'aliments (plus robuste que les tableaux Codable directement dans SwiftData).
private enum ItemsCoding {
    static func decode(_ data: Data) -> [TemplateItem] {
        (try? JSONDecoder().decode([TemplateItem].self, from: data)) ?? []
    }
    static func encode(_ items: [TemplateItem]) -> Data {
        (try? JSONEncoder().encode(items)) ?? Data()
    }
}

/// Repas habituel : plusieurs aliments ajoutés d'un coup (ex. « Mon petit-déj »).
@Model
final class MealTemplate {
    var name: String
    var mealRaw: String
    var itemsData: Data
    var createdAt: Date

    init(name: String, meal: Meal, items: [TemplateItem]) {
        self.name = name
        self.mealRaw = meal.rawValue
        self.itemsData = ItemsCoding.encode(items)
        self.createdAt = Date()
    }

    var meal: Meal { Meal(rawValue: mealRaw) ?? .snack }

    var items: [TemplateItem] {
        get { ItemsCoding.decode(itemsData) }
        set { itemsData = ItemsCoding.encode(newValue) }
    }

    var total: Macros { items.reduce(Macros.zero) { $0 + $1.macros } }
}

/// Recette maison : ingrédients du plat entier, divisés en portions.
@Model
final class Recipe {
    var name: String
    var servings: Double
    var ingredientsData: Data
    var createdAt: Date

    init(name: String, servings: Double, ingredients: [TemplateItem]) {
        self.name = name
        self.servings = servings
        self.ingredientsData = ItemsCoding.encode(ingredients)
        self.createdAt = Date()
    }

    var ingredients: [TemplateItem] {
        get { ItemsCoding.decode(ingredientsData) }
        set { ingredientsData = ItemsCoding.encode(newValue) }
    }

    var total: Macros { ingredients.reduce(Macros.zero) { $0 + $1.macros } }

    var perServing: Macros { total * (1 / max(servings, 1)) }

    /// Pour l'ajouter comme un aliment « à la portion ».
    var asFoodItem: FoodItem {
        FoodItem(id: "recipe-\(name.lowercased())", name: name, base: perServing, isPortion: true, defaultAmount: 1)
    }
}
