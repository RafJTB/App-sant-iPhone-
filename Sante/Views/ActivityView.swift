import SwiftUI
import Charts

struct ActivityView: View {
    @EnvironmentObject private var health: HealthDataStore

    private var last14: [DayHealth] { Array(health.days.suffix(14)) }

    private var weekWorkouts: [WorkoutSummary] {
        guard let limit = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else { return [] }
        return health.workouts.filter { $0.start >= limit }
    }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    Section("Aujourd'hui") {
                        let today = health.today ?? DayHealth(date: Date())
                        HStack {
                            StatTile(value: Fmt.kcal(today.activeKcal), unit: "kcal", caption: "active")
                            StatTile(value: Int(today.steps).formatted(), unit: "pas", caption: "marche")
                            StatTile(value: "\(Int(today.exerciseMinutes))", unit: "min", caption: "exercice")
                        }
                    }
    
                    Section("7 derniers jours") {
                        HStack {
                            StatTile(value: "\(weekWorkouts.count)", unit: "", caption: "séances")
                            StatTile(value: Fmt.duration(weekWorkouts.map(\.duration).reduce(0, +)), unit: "", caption: "durée totale")
                            StatTile(value: Fmt.kcal(weekWorkouts.compactMap(\.kcal).reduce(0, +)), unit: "kcal", caption: "séances")
                        }
                        if !last14.isEmpty {
                            Chart(last14) { day in
                                BarMark(x: .value("Jour", day.date, unit: .day),
                                        y: .value("kcal", day.activeKcal))
                                    .foregroundStyle(.pink.gradient)
                            }
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                                    AxisValueLabel(format: .dateTime.day())
                                }
                            }
                            .frame(height: 160)
                            .padding(.vertical, 4)
                            Text("Énergie active sur 14 jours. Chaque séance augmente ta dépense : pense à manger plus les jours d'entraînement.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
    
                    Section("Séances (30 jours)") {
                        if health.workouts.isEmpty {
                            EmptyHealthHint(text: "Aucune séance enregistrée. Les entraînements de l'Apple Watch, de l'app Forme ou d'apps comme Strava apparaissent ici s'ils sont envoyés vers Santé.")
                        }
                        ForEach(health.workouts) { workout in
                            WorkoutRow(workout: workout)
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .whiteListStyle()
            .navigationTitle("Sport")
            .refreshable { await health.reload() }
        }
    }
}

private struct WorkoutRow: View {
    let workout: WorkoutSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.symbol)
                .font(.title2)
                .foregroundStyle(.green)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.name).font(.body.weight(.medium))
                Text(workout.start.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.duration(workout.duration)).monospacedDigit()
                HStack(spacing: 6) {
                    if let km = workout.distanceKm, km > 0.05 {
                        Text("\(Fmt.number(km, digits: 2)) km")
                    }
                    if let kcal = workout.kcal {
                        Text("\(Fmt.kcal(kcal)) kcal")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
