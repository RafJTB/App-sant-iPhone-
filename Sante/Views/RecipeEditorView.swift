import SwiftUI
import SwiftData

/// Création ou modification d'une recette maison.
struct RecipeEditorView: View {
    let recipe: Recipe?
    var onSaved: ((Recipe) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name: String
    @State private var servings: Double
    @State private var ingredients: [TemplateItem]
    @State private var showPicker = false

    init(recipe: Recipe? = nil, onSaved: ((Recipe) -> Void)? = nil) {
        self.recipe = recipe
        self.onSaved = onSaved
        _name = State(initialValue: recipe?.name ?? "")
        _servings = State(initialValue: recipe?.servings ?? 4)
        _ingredients = State(initialValue: recipe?.ingredients ?? [])
    }

    private var total: Macros { ingredients.reduce(Macros.zero) { $0 + $1.macros } }
    private var perServing: Macros { total * (1 / max(servings, 1)) }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !ingredients.isEmpty }

    var body: some View {
        Form {
            Group {
                Section("Recette") {
                    TextField("Nom (ex. : Pâtes bolognaise maison)", text: $name)
                    Stepper(value: $servings, in: 1...20, step: 1) {
                        LabeledContent("Nombre de portions", value: Fmt.number(servings, digits: 0))
                    }
                }

                Section {
                    ForEach(ingredients) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                Text(item.quantityLabel).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Fmt.kcal(item.kcal)) kcal").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { ingredients.remove(atOffsets: $0) }
                    Button {
                        showPicker = true
                    } label: {
                        Label("Ajouter un ingrédient", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Ingrédients (plat entier)")
                } footer: {
                    Text("Indique les quantités pour tout le plat, par exemple 500 g de pâtes cuites et 400 g de steak haché.")
                }

                if !ingredients.isEmpty {
                    Section("Par portion") {
                        MacroSummaryRows(macros: perServing)
                        LabeledContent("Plat entier", value: "\(Fmt.kcal(total.kcal)) kcal")
                    }
                }
            }
            .listRowBackground(Theme.surface)
        }
        .whiteListStyle()
        .navigationTitle(recipe == nil ? "Nouvelle recette" : "Modifier la recette")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") { save() }.disabled(!canSave)
            }
        }
        .navigationDestination(isPresented: $showPicker) {
            IngredientPickerView { item in
                ingredients.append(item)
                showPicker = false
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let saved: Recipe
        if let recipe {
            recipe.name = trimmed
            recipe.servings = servings
            recipe.ingredients = ingredients
            saved = recipe
        } else {
            saved = Recipe(name: trimmed, servings: servings, ingredients: ingredients)
            context.insert(saved)
        }
        try? context.save()
        if let onSaved { onSaved(saved) } else { dismiss() }
    }
}

/// Choix d'un ingrédient : aliments courants, récents et produits du commerce.
struct IngredientPickerView: View {
    let onPick: (TemplateItem) -> Void
    @Query(sort: \FoodEntry.date, order: .reverse) private var history: [FoodEntry]
    @State private var search = ""
    @State private var offResults: [OFFProduct] = []
    @State private var offLoading = false
    @State private var offError: String?

    private var recents: [FoodItem] {
        var seen = Set<String>()
        var out: [FoodItem] = []
        for entry in history where entry.isGrams && !seen.contains(entry.name.lowercased()) {
            seen.insert(entry.name.lowercased())
            out.append(entry.asFoodItem)
            if out.count >= 10 { break }
        }
        return out
    }

    private func matches(_ item: FoodItem) -> Bool {
        search.isEmpty || item.name.localizedStandardContains(search)
    }

    private func portion(_ item: FoodItem) -> some View {
        PortionView(item: item, buttonTitle: "Ajouter à la recette") { name, amount, isGrams, macros in
            onPick(TemplateItem(name: name, quantity: amount, isGrams: isGrams, macros: macros))
        }
    }

    var body: some View {
        List {
            Group {
                if !search.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section("Produits du commerce") {
                        if offLoading {
                            ProgressView()
                        } else if offResults.isEmpty {
                            Button("Chercher « \(search) » sur Open Food Facts") { searchOFF() }
                        }
                        if let offError { Text(offError).font(.footnote).foregroundStyle(.orange) }
                        ForEach(offResults) { product in
                            NavigationLink { portion(product.asFoodItem) } label: { FoodItemRow(item: product.asFoodItem) }
                        }
                    }
                }
                let filteredRecents = recents.filter(matches)
                if !filteredRecents.isEmpty {
                    Section("Récents") {
                        ForEach(filteredRecents) { item in
                            NavigationLink { portion(item) } label: { FoodItemRow(item: item) }
                        }
                    }
                }
                Section("Aliments courants") {
                    ForEach(FoodDatabase.items.filter(matches)) { item in
                        NavigationLink { portion(item) } label: { FoodItemRow(item: item) }
                    }
                }
            }
            .listRowBackground(Theme.surface)
        }
        .searchable(text: $search, prompt: "Rechercher un ingrédient")
        .onSubmit(of: .search) { searchOFF() }
        .onChange(of: search) { _, _ in offResults = []; offError = nil }
        .whiteListStyle()
        .navigationTitle("Ingrédient")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func searchOFF() {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, !offLoading else { return }
        offLoading = true
        offError = nil
        Task {
            do {
                offResults = try await OpenFoodFactsClient.shared.search(query)
                if offResults.isEmpty { offError = "Aucun produit trouvé." }
            } catch {
                offError = error.localizedDescription
            }
            offLoading = false
        }
    }
}

/// Gestion des repas habituels et des recettes (depuis le Profil).
struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MealTemplate.createdAt, order: .reverse) private var templates: [MealTemplate]
    @Query(sort: \Recipe.name) private var recipes: [Recipe]

    var body: some View {
        List {
            Group {
                Section {
                    if templates.isEmpty {
                        Text("Aucun repas habituel. Dans l'onglet Repas, utilise « Enregistrer comme repas habituel » sous un repas déjà saisi.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(templates) { template in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                            Text("\(template.items.count) aliments · \(Fmt.kcal(template.total.kcal)) kcal · \(template.meal.label)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in for i in offsets { context.delete(templates[i]) } }
                } header: {
                    Text("Repas habituels")
                }

                Section {
                    ForEach(recipes) { recipe in
                        NavigationLink {
                            RecipeEditorView(recipe: recipe)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recipe.name)
                                Text("\(Fmt.number(recipe.servings, digits: 0)) portions · \(Fmt.kcal(recipe.perServing.kcal)) kcal par portion")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in for i in offsets { context.delete(recipes[i]) } }
                    NavigationLink {
                        RecipeEditorView()
                    } label: {
                        Label("Nouvelle recette", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Recettes maison")
                }
            }
            .listRowBackground(Theme.surface)
        }
        .whiteListStyle()
        .navigationTitle("Repas et recettes")
    }
}
