import SwiftUI
import SwiftData

struct FoodLogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodEntry.date) private var entries: [FoodEntry]
    @Query private var dayLogs: [DayLog]
    @EnvironmentObject private var profile: ProfileStore
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var addingMeal: Meal?

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
                                FoodRow(entry: entry)
                            }
                            .onDelete { offsets in
                                for index in offsets { context.delete(items[index]) }
                            }
                            Button {
                                addingMeal = meal
                            } label: {
                                Label("Ajouter un aliment", systemImage: "plus.circle.fill")
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
