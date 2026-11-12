import SwiftUI
import Charts

struct SleepView: View {
    @EnvironmentObject private var health: HealthDataStore

    private var recent: [SleepNight] { Array(health.nights.suffix(14)) }

    private var average7: TimeInterval? {
        let last = health.nights.suffix(7)
        guard !last.isEmpty else { return nil }
        return last.map(\.asleep).reduce(0, +) / Double(last.count)
    }

    /// Écart-type de l'heure de coucher (en minutes) : indicateur de régularité.
    private var bedtimeSpreadMinutes: Double? {
        let last = health.nights.suffix(7)
        guard last.count >= 3 else { return nil }
        let cal = Calendar.current
        // Minutes depuis 18 h pour éviter la coupure de minuit
        let values: [Double] = last.map { night in
            let c = cal.dateComponents([.hour, .minute], from: night.bedtime)
            var m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) - 18 * 60
            if m < 0 { m += 24 * 60 }
            return m
        }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        return variance.squareRoot()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let night = health.lastNight {
                        LastNightCard(night: night)
                    } else {
                        Card(title: "Sommeil", symbol: "bed.double.fill", tint: .indigo) {
                            EmptyHealthHint(text: "Aucune donnée de sommeil. Active « Sommeil » dans l'app Santé (iPhone) ou porte ton Apple Watch la nuit, puis vérifie l'autorisation dans Réglages › Santé › Accès aux données.")
                        }
                    }

                    if !recent.isEmpty {
                        Card(title: "14 dernières nuits", symbol: "chart.bar.fill", tint: .indigo) {
                            HStack {
                                if let avg = average7 {
                                    StatTile(value: Fmt.duration(avg), unit: "", caption: "moyenne 7 nuits")
                                }
                                if let spread = bedtimeSpreadMinutes {
                                    StatTile(value: "±\(Int(spread.rounded()))", unit: "min", caption: "régularité du coucher")
                                }
                            }
                            Chart {
                                ForEach(recent) { night in
                                    ForEach(stageValues(night), id: \.stage) { item in
                                        BarMark(x: .value("Nuit", night.date, unit: .day),
                                                y: .value("Heures", item.hours))
                                            .foregroundStyle(by: .value("Phase", item.stage.rawValue))
                                    }
                                }
                                RuleMark(y: .value("Recommandé", 8))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                    .foregroundStyle(.secondary)
                            }
                            .chartForegroundStyleScale([
                                SleepStage.deep.rawValue: Color.indigo,
                                SleepStage.core.rawValue: Color.blue,
                                SleepStage.rem.rawValue: Color.cyan,
                                SleepStage.unspecified.rawValue: Color.purple,
                            ])
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                                    AxisValueLabel(format: .dateTime.day())
                                }
                            }
                            .frame(height: 200)
                            Text("Pour la prise de muscle, vise 7 à 9 h par nuit avec des horaires réguliers : la majorité de l'hormone de croissance est sécrétée en sommeil profond.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Sommeil")
            .refreshable { await health.reload() }
        }
    }

    private struct StageValue {
        let stage: SleepStage
        let hours: Double
    }

    private func stageValues(_ night: SleepNight) -> [StageValue] {
        if night.hasStages {
            return [
                StageValue(stage: .deep, hours: night.deep / 3600),
                StageValue(stage: .core, hours: night.core / 3600),
                StageValue(stage: .rem, hours: night.rem / 3600),
            ]
        }
        return [StageValue(stage: .unspecified, hours: night.hours)]
    }
}

private struct LastNightCard: View {
    let night: SleepNight

    private var title: String {
        Calendar.current.isDateInToday(night.date)
            ? "Cette nuit"
            : "Nuit du \(night.date.formatted(.dateTime.day().month()))"
    }

    var body: some View {
        Card(title: title, symbol: "moon.zzz.fill", tint: .indigo) {
            Text(Fmt.duration(night.asleep))
                .font(.system(size: 40, weight: .bold, design: .rounded))
            Text("Coucher \(Fmt.time(night.bedtime)) · Réveil \(Fmt.time(night.wakeTime))")
                .font(.subheadline).foregroundStyle(.secondary)

            if night.hasStages {
                HStack {
                    StatTile(value: Fmt.duration(night.deep), unit: "", caption: "profond")
                    StatTile(value: Fmt.duration(night.core), unit: "", caption: "léger")
                    StatTile(value: Fmt.duration(night.rem), unit: "", caption: "paradoxal")
                    StatTile(value: Fmt.duration(night.awake), unit: "", caption: "éveillé")
                }
            } else {
                Text("Phases de sommeil disponibles avec une Apple Watch.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
