import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @EnvironmentObject private var health: HealthDataStore
    @EnvironmentObject private var profile: ProfileStore
    @Query(sort: \FoodEntry.date) private var entries: [FoodEntry]
    @Query private var dayLogs: [DayLog]
    @State private var showWeightEntry = false

    var body: some View {
        let analysis = EnergyAnalysis(entries: entries, completedDays: dayLogs.completedDays,
                                      health: health, profile: profile)

        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    DateEyebrow()
                    if let message = health.errorMessage {
                        Card(title: "Santé", symbol: "exclamationmark.triangle.fill", tint: .orange) {
                            Text(message).font(.subheadline)
                        }
                    }
                    TodayCaloriesCard(analysis: analysis)
                    VerdictCard(analysis: analysis)
                    WeightCard(points: WeightTrend.smoothed(health.weights), onAdd: { showWeightEntry = true })
                    HStack(alignment: .top, spacing: 16) {
                        SleepMiniCard(night: health.lastNight)
                        ActivityMiniCard(day: health.today)
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Aujourd'hui")
            .refreshable { await health.reload() }
            .sheet(isPresented: $showWeightEntry) {
                WeightEntryView(initial: health.latestWeightKg ?? profile.weightKg)
                    .presentationDetents([.medium])
            }
        }
    }
}

// MARK: - Calories du jour

private struct TodayCaloriesCard: View {
    let analysis: EnergyAnalysis

    var body: some View {
        Card(title: "Calories du jour", symbol: "flame.fill", tint: .orange) {
            let intake = analysis.todayIntake
            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    ProgressRing(progress: intake.kcal / max(analysis.todayTarget, 1), color: .orange, lineWidth: 11)
                    VStack(spacing: 0) {
                        Text(Fmt.kcal(intake.kcal))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("sur \(Fmt.kcal(analysis.todayTarget))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 118, height: 118)

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(analysis.remainingToday > 0 ? "Reste" : "Dépassé de")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("\(Fmt.kcal(abs(analysis.remainingToday))) kcal")
                            .font(.title3.weight(.semibold)).monospacedDigit()
                    }
                    MacroBar(label: "Protéines", value: intake.protein, target: analysis.proteinTarget, color: .red)
                    HStack {
                        Text("Glucides \(Fmt.grams(intake.carbs))")
                        Spacer()
                        Text("Lipides \(Fmt.grams(intake.fat))")
                    }
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }

            Text(analysis.targetExplanation)
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Verdict

private struct VerdictCard: View {
    let analysis: EnergyAnalysis

    var body: some View {
        Card(title: "Vais-je prendre du poids ?", symbol: "scalemass.fill", tint: Color.accentColor) {
            verdictText

            if !analysis.history.isEmpty {
                Chart(analysis.history) { day in
                    BarMark(x: .value("Jour", day.date, unit: .day),
                            y: .value("Balance", day.balance))
                        .foregroundStyle(day.balance >= 0 ? Color.green : Color.red)
                    RuleMark(y: .value("Objectif", analysis.targetSurplus))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.secondary)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                        AxisValueLabel(format: .dateTime.day())
                    }
                }
                .frame(height: 150)
                Text("Balance quotidienne (apports − dépense) des journées validées. Pointillés : ton objectif.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            CalibrationRow(analysis: analysis)

            if let trend = analysis.weightTrendKgPerWeek {
                HStack {
                    Image(systemName: "chart.xyaxis.line")
                    Text("Balance réelle (Santé) : **\(Fmt.signed(trend, digits: 2)) kg/semaine** sur 4 semaines.")
                }
                .font(.subheadline)
                if let predicted = analysis.projectedKgPerWeek, predicted - trend > 0.3 {
                    Text("Ta balance monte moins vite que prévu : il est probable que certains repas ne soient pas saisis, ou que les portions soient sous-estimées.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Pèse-toi 2 à 3 fois par semaine (balance connectée ou saisie dans Santé) pour comparer la prévision à la réalité.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var verdictText: some View {
        switch analysis.verdict {
        case .notEnoughData(let n):
            Text("Valide au moins \(EnergyAnalysis.minDaysForVerdict) journées complètes (onglet Repas › « Journée terminée ») pour obtenir un verdict : \(n)/\(EnergyAnalysis.minDaysForVerdict) sur les 7 derniers jours.")
                .font(.subheadline)
        case .gaining(let kg):
            VStack(alignment: .leading, spacing: 8) {
                StatusChip(text: "Prise de poids probable", color: .green)
                Text("\(Fmt.signed(kg, digits: 2)) kg / semaine")
                    .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                Text("Surplus moyen de **\(Fmt.signed(analysis.averageBalance ?? 0, digits: 0)) kcal/jour** → environ **\(Fmt.signed(kg, digits: 2)) kg/semaine** (\(Fmt.signed(kg * 4.3, digits: 1)) kg/mois).")
                    .font(.subheadline)
                if kg > 0.5 {
                    Text("Rythme rapide : une bonne partie risque d'être du gras. Pour une prise de masse propre, vise +0,25 à +0,5 kg/semaine.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        case .maintaining:
            VStack(alignment: .leading, spacing: 8) {
                StatusChip(text: "Poids stable", color: .blue)
                Text("Tu es proche de l'équilibre (\(Fmt.signed(analysis.averageBalance ?? 0, digits: 0)) kcal/jour) : ton poids devrait rester stable. Ajoute environ \(Fmt.kcal(analysis.targetSurplus)) kcal/jour pour prendre du poids.")
                    .font(.subheadline)
            }
        case .losing(let kg):
            VStack(alignment: .leading, spacing: 8) {
                StatusChip(text: "Perte de poids probable", color: .red)
                Text("\(Fmt.signed(kg, digits: 2)) kg / semaine")
                    .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                Text("Déficit moyen de **\(Fmt.kcal(-(analysis.averageBalance ?? 0))) kcal/jour** → environ **\(Fmt.signed(kg, digits: 2)) kg/semaine**. Il te manque ~\(Fmt.kcal(analysis.targetSurplus - (analysis.averageBalance ?? 0))) kcal/jour pour atteindre ton objectif.")
                    .font(.subheadline)
            }
        }
    }
}

// MARK: - Calibration

private struct CalibrationRow: View {
    let analysis: EnergyAnalysis

    var body: some View {
        if let c = analysis.calibrated {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text("Dépense réelle : **\(Fmt.kcal(c.kcalPerDay)) kcal/jour**")
                } icon: {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.accentColor)
                }
                .font(.subheadline)
                Group {
                    if let watch = c.watchEstimate {
                        Text("Calculée sur \(c.daysUsed) journées sur \(EnergyAnalysis.calibrationWindow) et \(c.weighIns) pesées. La montre estimait \(Fmt.kcal(watch)) kcal (\(Fmt.signed(watch - c.kcalPerDay, digits: 0))).")
                    } else {
                        Text("Calculée sur \(c.daysUsed) journées et \(c.weighIns) pesées.")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            let p = analysis.calibrationProgress
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Calibration sur ta balance").font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(min(p.completeDays, EnergyAnalysis.minCalibrationDays))/\(EnergyAnalysis.minCalibrationDays) j")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
                ProgressView(value: Double(min(p.completeDays, EnergyAnalysis.minCalibrationDays)),
                             total: Double(EnergyAnalysis.minCalibrationDays))
                    .tint(Color.accentColor)
                Text("Après \(EnergyAnalysis.minCalibrationDays) journées validées sur les \(EnergyAnalysis.calibrationWindow) dernières et au moins \(EnergyAnalysis.minWeighIns) pesées sur 2 semaines (\(p.weighIns) pour l'instant), l'app calcule ta vraie dépense à partir de ta balance et ajuste ton objectif.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Poids

private struct WeightCard: View {
    let points: [WeightTrend.Point]
    let onAdd: () -> Void

    private var recent: [WeightTrend.Point] {
        guard let limit = Calendar.current.date(byAdding: .day, value: -42, to: Date()) else { return points }
        return points.filter { $0.date >= limit }
    }

    /// Variation de la tendance sur 7 jours.
    private var weekChange: Double? {
        guard let last = recent.last,
              let ref = Calendar.current.date(byAdding: .day, value: -7, to: last.date),
              let before = recent.last(where: { $0.date <= ref }) else { return nil }
        return last.trend - before.trend
    }

    var body: some View {
        Card(title: "Poids", symbol: "scalemass", tint: .teal) {
            if let last = recent.last {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(Fmt.number(last.trend)) kg")
                        .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                    if let change = weekChange {
                        Text("\(Fmt.signed(change, digits: 1)) kg en 7 j")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(change >= 0 ? Color.accentColor : Color.red)
                    }
                }
                Text("Tendance lissée sur 7 jours · dernière pesée \(Fmt.number(last.raw)) kg")
                    .font(.caption).foregroundStyle(.secondary)

                Chart(recent) { p in
                    PointMark(x: .value("Jour", p.date, unit: .day), y: .value("Pesée", p.raw))
                        .foregroundStyle(Color.secondary.opacity(0.45))
                        .symbolSize(22)
                    LineMark(x: .value("Jour", p.date, unit: .day), y: .value("Tendance", p.trend))
                        .foregroundStyle(Color.teal)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 140)
            } else {
                Text("Aucune pesée pour l'instant. Pèse-toi le matin, à jeun, 3 fois par semaine : la tendance compte plus que chaque pesée.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Button(action: onAdd) {
                Label("Ajouter une pesée", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.teal)
        }
    }
}

private struct WeightEntryView: View {
    @EnvironmentObject private var health: HealthDataStore
    @Environment(\.dismiss) private var dismiss
    @State private var kg: Double
    @State private var date = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(initial: Double) {
        _kg = State(initialValue: (initial * 10).rounded() / 10)
    }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        HStack {
                            Text("Poids")
                            Spacer()
                            TextField("0", value: $kg, format: .number.precision(.fractionLength(1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                            Text("kg").foregroundStyle(.secondary)
                        }
                        Stepper("Ajuster", value: $kg, in: 30...250, step: 0.1)
                        DatePicker("Date", selection: $date, in: ...Date())
                    } footer: {
                        Text("Enregistré dans l'app Santé. Idéalement le matin, à jeun, après être passé aux toilettes.")
                    }
                    if let errorMessage {
                        Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .whiteListStyle()
            .navigationTitle("Nouvelle pesée")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(kg < 30 || isSaving)
                }
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await health.saveWeight(kg, date: date)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - Mini cartes

private struct SleepMiniCard: View {
    let night: SleepNight?

    var body: some View {
        Card(title: "Sommeil", symbol: "bed.double.fill", tint: .indigo) {
            if let night {
                StatTile(value: Fmt.duration(night.asleep), unit: "",
                         caption: "\(Fmt.time(night.bedtime)) → \(Fmt.time(night.wakeTime))")
                if night.hours < 7 {
                    Text("Moins de 7 h : la récupération et la prise de muscle en pâtissent.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                EmptyHealthHint(text: "Aucune nuit enregistrée.")
            }
        }
    }
}

private struct ActivityMiniCard: View {
    let day: DayHealth?

    var body: some View {
        Card(title: "Activité", symbol: "flame", tint: .pink) {
            if let day, day.activeKcal > 0 || day.steps > 0 {
                StatTile(value: Fmt.kcal(day.activeKcal), unit: "kcal", caption: "énergie active")
                StatTile(value: Int(day.steps).formatted(), unit: "pas", caption: "aujourd'hui")
            } else {
                EmptyHealthHint(text: "Pas encore d'activité aujourd'hui.")
            }
        }
    }
}
