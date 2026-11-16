import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var health: HealthDataStore
    @Environment(\.modelContext) private var context
    @State private var backupURL: URL?
    @State private var showImporter = false
    @State private var backupMessage: String?

    private var weightUsed: Double { profile.effectiveWeight(healthWeight: health.latestWeightKg) }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section {
                        Toggle("Utiliser le poids de l'app Santé", isOn: $profile.useHealthWeight)
                        if profile.useHealthWeight, let w = health.latestWeightKg {
                            LabeledContent("Dernière pesée (Santé)", value: "\(Fmt.number(w)) kg")
                        } else {
                            Stepper(value: $profile.weightKg, in: 30...250, step: 0.5) {
                                LabeledContent("Poids", value: "\(Fmt.number(profile.weightKg)) kg")
                            }
                        }
                        Button("Reprendre la dernière pesée de Santé") {
                            profile.importFromHealth(health)
                        }
                    } header: {
                        Text("Moi")
                    }
    
                    Section {
                        Stepper(value: $profile.targetSurplus, in: 0...1000, step: 50) {
                            LabeledContent("Surplus visé", value: "+\(Int(profile.targetSurplus)) kcal/j")
                        }
                        Stepper(value: $profile.proteinPerKg, in: 1.2...2.5, step: 0.1) {
                            LabeledContent("Protéines", value: "\(Fmt.number(profile.proteinPerKg)) g/kg")
                        }
                        LabeledContent("Objectif protéines", value: Fmt.grams(weightUsed * profile.proteinPerKg))
                    } header: {
                        Text("Objectif prise de poids")
                    } footer: {
                        Text("Repères courants : +250 à +500 kcal/jour (≈ +0,25 à +0,5 kg/semaine) et 1,6 à 2,2 g de protéines par kg pour une prise de masse surtout musculaire, avec de la musculation.")
                    }
    
                    Section {
                        NavigationLink {
                            LibraryView()
                        } label: {
                            Label("Repas habituels et recettes", systemImage: "book.closed")
                        }
                    }

                    Section {
                        if let backupURL {
                            ShareLink(item: backupURL) {
                                Label("Enregistrer le fichier de sauvegarde", systemImage: "square.and.arrow.up")
                            }
                        } else {
                            Button {
                                do {
                                    backupURL = try Backup.export(context: context)
                                    backupMessage = nil
                                } catch {
                                    backupMessage = "Export impossible : \(error.localizedDescription)"
                                }
                            } label: {
                                Label("Préparer une sauvegarde", systemImage: "externaldrive")
                            }
                        }
                        Button {
                            showImporter = true
                        } label: {
                            Label("Restaurer une sauvegarde", systemImage: "arrow.down.doc")
                        }
                        if let backupMessage {
                            Text(backupMessage).font(.footnote).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Sauvegarde")
                    } footer: {
                        Text("Tes repas ne sont stockés que sur cet iPhone. Enregistre de temps en temps une sauvegarde dans Fichiers ou iCloud Drive. La restauration ajoute les données sans créer de doublons. Les données Santé (poids, sommeil, sport) restent dans l'app Santé.")
                    }

                    Section {
                        Toggle("Rappel du soir", isOn: $profile.reminderEnabled)
                        if profile.reminderEnabled {
                            DatePicker("Heure", selection: $profile.reminderTime, displayedComponents: .hourAndMinute)
                        }
                    } header: {
                        Text("Rappel")
                    } footer: {
                        Text("Une notification si ta journée n'est pas encore validée. Rien n'est envoyé les jours déjà validés.")
                    }
                    .onChange(of: profile.reminderEnabled) { _, enabled in
                        Task {
                            if enabled { _ = await ReminderScheduler.requestPermission() }
                            await ReminderScheduler.reschedule(profile: profile, context: context)
                        }
                    }
                    .onChange(of: profile.reminderMinute + profile.reminderHour * 60) { _, _ in
                        Task { await ReminderScheduler.reschedule(profile: profile, context: context) }
                    }

                    Section {
                        Button("Actualiser les données Santé") {
                            Task { await health.requestAuthorizationAndLoad() }
                        }
                        if let date = health.lastUpdate {
                            LabeledContent("Dernière mise à jour", value: date.formatted(date: .omitted, time: .shortened))
                        }
                    } header: {
                        Text("Santé")
                    } footer: {
                        Text("L'app lit tes données (sommeil, activité, séances, poids) et n'écrit que les pesées que tu saisis. Tes repas restent stockés sur ton iPhone. Les calories brûlées viennent de ton Apple Watch : porte-la jour et nuit pour des mesures complètes. Pour modifier les autorisations : Réglages › Santé › Accès aux données et appareils › Santé.")
                    }
    
                    Section("Comment est calculé le verdict ?") {
                        Text("Balance = calories mangées − dépense, sur les 7 dernières journées validées. Au début, la dépense est celle mesurée par ton Apple Watch (énergie au repos + active + ~10 % pour la digestion) ; les jours où tu ne l'as pas portée sont ignorés. Après 20 journées validées sur 28 et 4 pesées sur 2 semaines, elle est recalculée à partir de ta balance : apports moyens − variation de poids × 7 700 kcal/kg. C'est plus fiable que la montre.")
                            .font(.footnote)
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .whiteListStyle()
            .navigationTitle("Profil")
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                do {
                    let summary = try Backup.restore(from: result.get(), context: context)
                    backupMessage = "Restauré : \(summary.text)."
                } catch {
                    backupMessage = "Restauration impossible : \(error.localizedDescription)"
                }
            }
        }
    }
}
