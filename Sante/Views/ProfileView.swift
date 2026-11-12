import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var profile: ProfileStore
    @EnvironmentObject private var health: HealthDataStore

    private var weightUsed: Double { profile.effectiveWeight(healthWeight: health.latestWeightKg) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Utiliser le poids de l'app Santé", isOn: $profile.useHealthWeight)
                    if profile.useHealthWeight, let w = health.latestWeightKg {
                        LabeledContent("Dernière pesée (Santé)", value: "\(Fmt.number(w)) kg")
                    } else {
                        Stepper(value: $profile.weightKg, in: 30...250, step: 0.5) {
                            LabeledContent("Poids", value: "\(Fmt.number(profile.weightKg)) kg")
                        }
                    }
                    Stepper(value: $profile.heightCm, in: 120...230, step: 1) {
                        LabeledContent("Taille", value: "\(Int(profile.heightCm)) cm")
                    }
                    Stepper(value: $profile.birthYear, in: 1930...2015) {
                        LabeledContent("Année de naissance", value: String(profile.birthYear))
                    }
                    Picker("Sexe", selection: $profile.isMale) {
                        Text("Homme").tag(true)
                        Text("Femme").tag(false)
                    }
                    Button("Importer depuis l'app Santé") {
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
                    Picker("Niveau d'activité", selection: $profile.activityFactor) {
                        ForEach(ProfileStore.activityLevels, id: \.factor) { level in
                            Text(level.label).tag(level.factor)
                        }
                    }
                    LabeledContent("Métabolisme de base", value: "\(Fmt.kcal(profile.bmr(weightKg: weightUsed))) kcal")
                } header: {
                    Text("Si pas d'Apple Watch")
                } footer: {
                    Text("Avec une Apple Watch, l'app utilise ta dépense réelle (énergie au repos + active). Sinon, elle l'estime avec la formule de Mifflin-St Jeor × ton niveau d'activité.")
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
                    Text("L'app lit uniquement tes données (sommeil, activité, séances, poids). Tes repas restent stockés sur ton iPhone. Pour modifier les autorisations : Réglages › Santé › Accès aux données et appareils › Santé.")
                }

                Section("Comment est calculé le verdict ?") {
                    Text("Balance = calories mangées − (énergie au repos + énergie active + ~10 % des apports pour la digestion). On fait la moyenne sur les 7 derniers jours saisis, puis ~7 700 kcal de surplus ≈ +1 kg. C'est une estimation : la courbe de ta balance reste la référence.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Profil")
        }
    }
}
