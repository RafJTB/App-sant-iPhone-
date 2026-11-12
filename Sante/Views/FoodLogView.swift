import SwiftUI
import SwiftData

struct FoodLogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodEntry.date) private var entries: [FoodEntry]
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var addingMeal: Meal?

    private var dayEntries: [FoodEntry] {
        entries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    private var totals: Macros {
        dayEntries.reduce(Macros.zero) { $0 + $1.macros }
    }

    var body: some View {
        NavigationStack {
            List {
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
            }
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
