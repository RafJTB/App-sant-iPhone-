import SwiftUI
import SwiftData

struct FoodLogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodEntry.date) private var entries: [FoodEntry]
    @Query private var dayLogs: [DayLog]
    @EnvironmentObject private var profile: ProfileStore
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var addingMeal: Meal?
    @State private var templateMeal: Meal?
    @State private var editing: FoodEntry?
    @State private var templateName = ""

    private var dayEntries: [FoodEntry] {
        entries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    private var totals: Macros {
        dayEntries.reduce(Macros.zero) { $0 + $1.macros }
    }

    private var isComplete: Bool {
        dayLogs.completedDays.contains(Calendar.current.startOfDay(for: day))
    }

    /// Apport habituel d'une journée complète (médiane des journées validées).
    private var typicalIntake: Double? {
        let cal = Calendar.current
        var byDay: [Date: Double] = [:]
        for e in entries { byDay[cal.startOfDay(for: e.date), default: 0] += e.kcal }
        let values = dayLogs.completedDays
            .filter { !cal.isDate($0, inSameDayAs: day) }
            .compactMap { byDay[$0] }
            .filter { $0 > 0 }
            .sorted()
        guard values.count >= 3 else { return nil }
        return values[values.count / 2]
    }

    private var looksIncomplete: Bool {
        guard let typical = typicalIntake else { return false }
        return totals.kcal < typical * EnergyAnalysis.lowDayRatio
    }

    /// Aliments du même repas la veille du jour affiché.
    private func previousDayItems(_ meal: Meal) -> [FoodEntry] {
        guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: day) else { return [] }
        return entries.filter { Calendar.current.isDate($0.date, inSameDayAs: previous) && $0.meal == meal }
    }

    private var entryDate: Date {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return Date() }
        return cal.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    private func copy(_ items: [FoodEntry], to meal: Meal) {
        for e in items {
            context.insert(FoodEntry(date: entryDate, name: e.name, meal: meal,
                                     quantity: e.quantity, isGrams: e.isGrams, macros: e.macros))
        }
    }

    private func saveTemplate() {
        guard let meal = templateMeal else { return }
        let items = dayEntries.filter { $0.meal == meal }.map(TemplateItem.init(entry:))
        let name = templateName.trimmingCharacters(in: .whitespaces)
        guard !items.isEmpty, !name.isEmpty else { return }
        context.insert(MealTemplate(name: name, meal: meal, items: items))
        templateMeal = nil
    }

    private func setComplete(_ complete: Bool) {
        DayCompletion.set(complete, day: day, logs: dayLogs, context: context)
        Task { await ReminderScheduler.reschedule(profile: profile, context: context) }
    }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section {
                        DaySelector(day: $day)
                        HStack {
                            StatTile(value: Fmt.kcal(totals.kcal), unit: "kcal", caption: "total")
                            StatTile(value: "\(Int(totals.protein.rounded()))", unit: "g", caption: "protéines")
                            StatTile(value: "\(Int(totals.carbs.rounded()))", unit: "g", caption: "glucides")
                            StatTile(value: "\(Int(totals.fat.rounded()))", unit: "g", caption: "lipides")
                        }
                    }
    
                    ForEach(Meal.allCases) { meal in
                        let items = dayEntries.filter { $0.meal == meal }
                        Section {
                            ForEach(items) { entry in
                                Button {
                                    editing = entry
                                } label: {
                                    FoodRow(entry: entry)
                                }
                                .foregroundStyle(.primary)
                            }
                            .onDelete { offsets in
                                for index in offsets { context.delete(items[index]) }
                            }
                            Button {
                                addingMeal = meal
                            } label: {
                                Label("Ajouter un aliment", systemImage: "plus.circle.fill")
                            }
                            if items.isEmpty {
                                let previous = previousDayItems(meal)
                                if !previous.isEmpty {
                                    Button {
                                        copy(previous, to: meal)
                                    } label: {
                                        Label("Comme hier · \(Fmt.kcal(previous.reduce(0) { $0 + $1.kcal })) kcal",
                                              systemImage: "arrow.counterclockwise")
                                    }
                                }
                            } else {
                                Button {
                                    templateName = meal.label
                                    templateMeal = meal
                                } label: {
                                    Label("Enregistrer comme repas habituel", systemImage: "star")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } header: {
                            HStack {
                                Label(meal.label, systemImage: meal.symbol)
                                Spacer()
                                Text("\(Fmt.kcal(items.reduce(0) { $0 + $1.kcal })) kcal")
                            }
                        }
                    }

                    Section {
                        if isComplete {
                            HStack {
                                Label("Journée validée", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .font(.body.weight(.semibold))
                                Spacer()
                                Button("Rouvrir") { setComplete(false) }
                                    .buttonStyle(.borderless)
                            }
                        } else {
                            if looksIncomplete, let typical = typicalIntake {
                                Label("Seulement \(Fmt.kcal(totals.kcal)) kcal, contre \(Fmt.kcal(typical)) d'habitude : il manque peut-être un repas.",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                            Button {
                                setComplete(true)
                            } label: {
                                Label("Journée terminée", systemImage: "checkmark.circle")
                                    .font(.body.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .disabled(dayEntries.isEmpty)
                        }
                    } footer: {
                        Text(isComplete
                             ? "Cette journée compte dans le verdict et la calibration."
                             : "Valide la journée une fois tous tes repas saisis : seules les journées complètes comptent dans le verdict.")
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .whiteListStyle()
            .navigationTitle("Repas")
            .sheet(item: $addingMeal) { meal in
                AddFoodView(day: day, meal: meal)
            }
            .sheet(item: $editing) { entry in
                EditEntryView(entry: entry)
                    .presentationDetents([.medium, .large])
            }
            .alert("Repas habituel", isPresented: Binding(
                get: { templateMeal != nil },
                set: { if !$0 { templateMeal = nil } }
            )) {
                TextField("Nom (ex. : Mon petit-déj)", text: $templateName)
                Button("Enregistrer") { saveTemplate() }
                Button("Annuler", role: .cancel) { templateMeal = nil }
            } message: {
                Text("Tu pourras ajouter tout ce repas en un tap depuis « Ajouter un aliment ».")
            }
        }
    }
}

private struct DaySelector: View {
    @Binding var day: Date

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
            Spacer()
            Text(isToday ? "Aujourd'hui" : day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.headline)
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .disabled(isToday)
        }
    }

    private func shift(_ days: Int) {
        if let d = Calendar.current.date(byAdding: .day, value: days, to: day) { day = d }
    }
}

private struct FoodRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                Text("\(entry.quantityLabel) · P \(Int(entry.protein.rounded())) · G \(Int(entry.carbs.rounded())) · L \(Int(entry.fat.rounded()))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Fmt.kcal(entry.kcal)) kcal").monospacedDigit()
        }
    }
}

/// Modifier la quantité ou le repas d'un aliment déjà saisi.
private struct EditEntryView: View {
    let entry: FoodEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var quantity: Double
    @State private var meal: Meal

    init(entry: FoodEntry) {
        self.entry = entry
        _quantity = State(initialValue: entry.quantity)
        _meal = State(initialValue: entry.meal)
    }

    /// Les apports suivent la quantité, proportionnellement.
    private var scaled: Macros {
        entry.quantity > 0 ? entry.macros * (quantity / entry.quantity) : entry.macros
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section(entry.name) {
                        HStack {
                            Text(entry.isGrams ? "Quantité" : "Portions")
                            Spacer()
                            TextField("0", value: $quantity, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                            Text(entry.isGrams ? "g" : "×").foregroundStyle(.secondary)
                        }
                        Stepper("Ajuster", value: $quantity, in: 0...5000, step: entry.isGrams ? 10 : 0.5)
                        Picker("Repas", selection: $meal) {
                            ForEach(Meal.allCases) { Text($0.label).tag($0) }
                        }
                    }
                    Section("Apport") {
                        MacroSummaryRows(macros: scaled)
                    }
                    Section {
                        Button("Supprimer", role: .destructive) {
                            context.delete(entry)
                            dismiss()
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .whiteListStyle()
            .navigationTitle("Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }.disabled(quantity <= 0)
                }
            }
        }
    }

    private func save() {
        let m = scaled
        entry.quantity = quantity
        entry.kcal = m.kcal
        entry.protein = m.protein
        entry.carbs = m.carbs
        entry.fat = m.fat
        entry.mealRaw = meal.rawValue
        dismiss()
    }
}
