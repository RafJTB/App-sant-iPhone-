import Foundation
import SwiftData

/// Sauvegarde et restauration de tout ce que tu saisis (repas, journées validées, repas habituels, recettes)
/// dans un fichier JSON que tu peux garder dans Fichiers ou iCloud Drive.
struct BackupFile: Codable {
    struct Entry: Codable {
        var date: Date
        var name: String
        var meal: String
        var quantity: Double
        var isGrams: Bool
        var kcal: Double
        var protein: Double
        var carbs: Double
        var fat: Double
    }
    struct Template: Codable {
        var name: String
        var meal: String
        var items: [TemplateItem]
    }
    struct RecipeDTO: Codable {
        var name: String
        var servings: Double
        var ingredients: [TemplateItem]
    }

    var version = 1
    var exportedAt = Date()
    var entries: [Entry]
    var completedDays: [Date]
    var templates: [Template]
    var recipes: [RecipeDTO]
}

struct BackupSummary {
    let entries: Int
    let days: Int
    let templates: Int
    let recipes: Int

    var text: String {
        "\(entries) aliments, \(days) journées validées, \(templates) repas habituels, \(recipes) recettes"
    }
}

enum Backup {
    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Écrit la sauvegarde dans un fichier temporaire et renvoie son adresse (à partager).
    @MainActor
    static func export(context: ModelContext) throws -> URL {
        let entries = try context.fetch(FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date)]))
        let logs = try context.fetch(FetchDescriptor<DayLog>())
        let templates = try context.fetch(FetchDescriptor<MealTemplate>())
        let recipes = try context.fetch(FetchDescriptor<Recipe>())

        let file = BackupFile(
            entries: entries.map {
                .init(date: $0.date, name: $0.name, meal: $0.mealRaw, quantity: $0.quantity, isGrams: $0.isGrams,
                      kcal: $0.kcal, protein: $0.protein, carbs: $0.carbs, fat: $0.fat)
            },
            completedDays: logs.filter(\.isComplete).map(\.day).sorted(),
            templates: templates.map { .init(name: $0.name, meal: $0.mealRaw, items: $0.items) },
            recipes: recipes.map { .init(name: $0.name, servings: $0.servings, ingredients: $0.ingredients) }
        )

        let stamp = Date().formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sauvegarde-sante-\(stamp).json")
        try encoder.encode(file).write(to: url, options: .atomic)
        return url
    }

    /// Ajoute le contenu d'une sauvegarde sans créer de doublons.
    @MainActor
    static func restore(from url: URL, context: ModelContext) throws -> BackupSummary {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let file = try decoder.decode(BackupFile.self, from: Data(contentsOf: url))

        func key(_ date: Date, _ name: String, _ kcal: Double) -> String {
            "\(Int(date.timeIntervalSince1970))|\(name)|\(Int(kcal.rounded()))"
        }
        var existing = Set(try context.fetch(FetchDescriptor<FoodEntry>()).map { key($0.date, $0.name, $0.kcal) })
        var addedEntries = 0
        for e in file.entries where !existing.contains(key(e.date, e.name, e.kcal)) {
            existing.insert(key(e.date, e.name, e.kcal))
            context.insert(FoodEntry(date: e.date, name: e.name, meal: Meal(rawValue: e.meal) ?? .snack,
                                     quantity: e.quantity, isGrams: e.isGrams,
                                     macros: Macros(kcal: e.kcal, protein: e.protein, carbs: e.carbs, fat: e.fat)))
            addedEntries += 1
        }

        let logs = try context.fetch(FetchDescriptor<DayLog>())
        var addedDays = 0
        for day in file.completedDays {
            let start = Calendar.current.startOfDay(for: day)
            if let log = logs.first(where: { Calendar.current.isDate($0.day, inSameDayAs: start) }) {
                if !log.isComplete { log.isComplete = true; addedDays += 1 }
            } else {
                context.insert(DayLog(day: start))
                addedDays += 1
            }
        }

        let templateNames = Set(try context.fetch(FetchDescriptor<MealTemplate>()).map(\.name))
        var addedTemplates = 0
        for t in file.templates where !templateNames.contains(t.name) {
            context.insert(MealTemplate(name: t.name, meal: Meal(rawValue: t.meal) ?? .snack, items: t.items))
            addedTemplates += 1
        }

        let recipeNames = Set(try context.fetch(FetchDescriptor<Recipe>()).map(\.name))
        var addedRecipes = 0
        for r in file.recipes where !recipeNames.contains(r.name) {
            context.insert(Recipe(name: r.name, servings: r.servings, ingredients: r.ingredients))
            addedRecipes += 1
        }

        try context.save()
        return BackupSummary(entries: addedEntries, days: addedDays, templates: addedTemplates, recipes: addedRecipes)
    }
}
