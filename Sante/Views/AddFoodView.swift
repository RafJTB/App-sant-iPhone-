import SwiftUI
import SwiftData

struct AddFoodView: View {
    let day: Date
    @State private var meal: Meal
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodEntry.date, order: .reverse) private var history: [FoodEntry]
    @State private var showScanner = false
    @State private var scannedItem: FoodItem?
    @State private var offResults: [OFFProduct] = []
    @State private var offQuery = ""
    @State private var offLoading = false
    @State private var offError: String?

    init(day: Date, meal: Meal) {
        self.day = day
        _meal = State(initialValue: meal)
    }

    private var recents: [FoodItem] {
        var seen = Set<String>()
        var out: [FoodItem] = []
        for entry in history where !seen.contains(entry.name.lowercased()) {
            seen.insert(entry.name.lowercased())
            out.append(entry.asFoodItem)
            if out.count >= 15 { break }
        }
        return out
    }

    private func matches(_ item: FoodItem) -> Bool {
        search.isEmpty || item.name.localizedStandardContains(search)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Repas", selection: $meal) {
                        ForEach(Meal.allCases) { Text($0.label).tag($0) }
                    }
                    Button {
                        showScanner = true
                    } label: {
                        Label("Scanner un code-barres", systemImage: "barcode.viewfinder")
                    }
                    NavigationLink {
                        ManualEntryView(onSave: save)
                    } label: {
                        Label("Saisie manuelle (étiquette, plat…)", systemImage: "square.and.pencil")
                    }
                }

                if !search.trimmingCharacters(in: .whitespaces).isEmpty || !offResults.isEmpty || offLoading {
                    openFoodFactsSection
                }

                let filteredRecents = recents.filter(matches)
                if !filteredRecents.isEmpty {
                    Section("Récents") {
                        ForEach(filteredRecents) { item in
                            NavigationLink {
                                PortionView(item: item, onSave: save)
                            } label: {
                                FoodItemRow(item: item)
                            }
                        }
                    }
                }

                Section {
                    ForEach(FoodDatabase.items.filter(matches)) { item in
                        NavigationLink {
                            PortionView(item: item, onSave: save)
                        } label: {
                            FoodItemRow(item: item)
                        }
                    }
                } header: {
                    Text("Aliments courants")
                } footer: {
                    Text("Valeurs moyennes approximatives. Pour un produit précis, utilise la saisie manuelle avec l'étiquette.")
                }
            }
            .searchable(text: $search, prompt: "Rechercher un aliment ou une marque")
            .onSubmit(of: .search) { searchOpenFoodFacts() }
            .sheet(isPresented: $showScanner) {
                ScanBarcodeView { item in scannedItem = item }
            }
            .navigationDestination(item: $scannedItem) { item in
                PortionView(item: item, onSave: save)
            }
            .navigationTitle(meal.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var openFoodFactsSection: some View {
        Section {
            if offLoading {
                HStack { ProgressView(); Text("Recherche sur Open Food Facts…").foregroundStyle(.secondary) }
            } else if offQuery != search.trimmingCharacters(in: .whitespaces) || (offResults.isEmpty && offError == nil) {
                Button {
                    searchOpenFoodFacts()
                } label: {
                    Label("Chercher « \(search) » dans les produits du commerce", systemImage: "magnifyingglass")
                }
            }
            if let offError {
                Text(offError).font(.footnote).foregroundStyle(.orange)
            }
            ForEach(offResults) { product in
                NavigationLink {
                    PortionView(item: product.asFoodItem, onSave: save)
                } label: {
                    FoodItemRow(item: product.asFoodItem)
                }
            }
        } header: {
            Text("Produits du commerce")
        } footer: {
            Text("Source : Open Food Facts (base collaborative). Vérifie les valeurs avec l'étiquette en cas de doute.")
        }
    }

    private func searchOpenFoodFacts() {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, !offLoading else { return }
        offLoading = true
        offError = nil
        offQuery = query
        Task {
            do {
                let results = try await OpenFoodFactsClient.shared.search(query)
                offResults = results
                if results.isEmpty { offError = "Aucun produit trouvé pour « \(query) »." }
            } catch {
                offResults = []
                offError = error.localizedDescription
            }
            offLoading = false
        }
    }

    /// Date de l'entrée : maintenant si c'est aujourd'hui, sinon midi du jour choisi.
    private var entryDate: Date {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return Date() }
        return cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    private func save(name: String, amount: Double, isGrams: Bool, macros: Macros) {
        let entry = FoodEntry(date: entryDate, name: name, meal: meal,
                              quantity: amount, isGrams: isGrams, macros: macros)
        context.insert(entry)
        dismiss()
    }
}

private struct FoodItemRow: View {
    let item: FoodItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.name)
            Text(item.isPortion
                 ? "\(Fmt.kcal(item.base.kcal)) kcal / portion"
                 : "\(Fmt.kcal(item.base.kcal)) kcal / 100 g · P \(Fmt.number(item.base.protein)) g")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct PortionView: View {
    let item: FoodItem
    let onSave: (String, Double, Bool, Macros) -> Void
    @State private var amount: Double

    init(item: FoodItem, onSave: @escaping (String, Double, Bool, Macros) -> Void) {
        self.item = item
        self.onSave = onSave
        _amount = State(initialValue: item.defaultAmount)
    }

    var body: some View {
        let macros = item.macros(for: amount)
        Form {
            Section(item.name) {
                HStack {
                    Text(item.isPortion ? "Portions" : "Quantité")
                    Spacer()
                    TextField("0", value: $amount, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    Text(item.isPortion ? "×" : "g").foregroundStyle(.secondary)
                }
                Stepper("Ajuster", value: $amount, in: 0...5000, step: item.isPortion ? 0.5 : 10)
            }
            Section("Apport") {
                MacroSummaryRows(macros: macros)
            }
            Section {
                Button {
                    onSave(item.name, amount, !item.isPortion, macros)
                } label: {
                    Text("Ajouter").frame(maxWidth: .infinity).bold()
                }
                .disabled(amount <= 0)
            }
        }
        .navigationTitle("Portion")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ManualEntryView: View {
    let onSave: (String, Double, Bool, Macros) -> Void
    @State private var name = ""
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?

    var body: some View {
        Form {
            Section("Aliment ou plat") {
                TextField("Nom (ex. : Pâtes bolognaise maison)", text: $name)
            }
            Section {
                numberField("Calories", value: $kcal, unit: "kcal")
                numberField("Protéines", value: $protein, unit: "g")
                numberField("Glucides", value: $carbs, unit: "g")
                numberField("Lipides", value: $fat, unit: "g")
            } header: {
                Text("Pour la portion consommée")
            } footer: {
                Text("Seules les calories sont obligatoires. L'aliment sera ensuite proposé dans « Récents ».")
            }
            Section {
                Button {
                    let macros = Macros(kcal: kcal ?? 0, protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0)
                    onSave(name.trimmingCharacters(in: .whitespaces), 1, false, macros)
                } label: {
                    Text("Ajouter").frame(maxWidth: .infinity).bold()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (kcal ?? 0) <= 0)
            }
        }
        .navigationTitle("Saisie manuelle")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func numberField(_ label: String, value: Binding<Double?>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}
