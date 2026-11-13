import Foundation

/// Profil utilisateur, persisté dans UserDefaults.
final class ProfileStore: ObservableObject {
    private enum Keys {
        static let weight = "profile.weightKg"
        static let height = "profile.heightCm"
        static let birthYear = "profile.birthYear"
        static let isMale = "profile.isMale"
        static let activity = "profile.activityFactor"
        static let surplus = "profile.targetSurplus"
        static let protein = "profile.proteinPerKg"
        static let useHealthWeight = "profile.useHealthWeight"
        static let imported = "profile.didImportFromHealth"
        static let reminderEnabled = "profile.reminderEnabled"
        static let reminderHour = "profile.reminderHour"
        static let reminderMinute = "profile.reminderMinute"
    }

    private let defaults = UserDefaults.standard

    @Published var weightKg: Double { didSet { defaults.set(weightKg, forKey: Keys.weight) } }
    @Published var heightCm: Double { didSet { defaults.set(heightCm, forKey: Keys.height) } }
    @Published var birthYear: Int { didSet { defaults.set(birthYear, forKey: Keys.birthYear) } }
    @Published var isMale: Bool { didSet { defaults.set(isMale, forKey: Keys.isMale) } }
    /// Facteur d'activité utilisé seulement si les données de dépense Santé manquent.
    @Published var activityFactor: Double { didSet { defaults.set(activityFactor, forKey: Keys.activity) } }
    /// Surplus calorique visé (kcal/jour) pour la prise de poids.
    @Published var targetSurplus: Double { didSet { defaults.set(targetSurplus, forKey: Keys.surplus) } }
    @Published var proteinPerKg: Double { didSet { defaults.set(proteinPerKg, forKey: Keys.protein) } }
    /// Utiliser automatiquement la dernière pesée de l'app Santé.
    @Published var useHealthWeight: Bool { didSet { defaults.set(useHealthWeight, forKey: Keys.useHealthWeight) } }
    @Published var didImportFromHealth: Bool { didSet { defaults.set(didImportFromHealth, forKey: Keys.imported) } }
    /// Rappel du soir si la journée n'est pas validée.
    @Published var reminderEnabled: Bool { didSet { defaults.set(reminderEnabled, forKey: Keys.reminderEnabled) } }
    @Published var reminderHour: Int { didSet { defaults.set(reminderHour, forKey: Keys.reminderHour) } }
    @Published var reminderMinute: Int { didSet { defaults.set(reminderMinute, forKey: Keys.reminderMinute) } }

    init() {
        let d = UserDefaults.standard
        weightKg = d.object(forKey: Keys.weight) as? Double ?? 70
        heightCm = d.object(forKey: Keys.height) as? Double ?? 178
        birthYear = d.object(forKey: Keys.birthYear) as? Int ?? 2000
        isMale = d.object(forKey: Keys.isMale) as? Bool ?? true
        activityFactor = d.object(forKey: Keys.activity) as? Double ?? 1.55
        targetSurplus = d.object(forKey: Keys.surplus) as? Double ?? 300
        proteinPerKg = d.object(forKey: Keys.protein) as? Double ?? 1.8
        useHealthWeight = d.object(forKey: Keys.useHealthWeight) as? Bool ?? true
        didImportFromHealth = d.object(forKey: Keys.imported) as? Bool ?? false
        reminderEnabled = d.object(forKey: Keys.reminderEnabled) as? Bool ?? true
        reminderHour = d.object(forKey: Keys.reminderHour) as? Int ?? 21
        reminderMinute = d.object(forKey: Keys.reminderMinute) as? Int ?? 0
    }

    /// Heure du rappel sous forme de Date (pour le sélecteur d'heure).
    var reminderTime: Date {
        get {
            Calendar.current.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: Date()) ?? Date()
        }
        set {
            let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            reminderHour = c.hour ?? 21
            reminderMinute = c.minute ?? 0
        }
    }

    var age: Int {
        max(10, Calendar.current.component(.year, from: Date()) - birthYear)
    }

    /// Poids utilisé dans les calculs.
    func effectiveWeight(healthWeight: Double?) -> Double {
        if useHealthWeight, let w = healthWeight { return w }
        return weightKg
    }

    /// Métabolisme de base (Mifflin-St Jeor), kcal/jour.
    func bmr(weightKg w: Double) -> Double {
        10 * w + 6.25 * heightCm - 5 * Double(age) + (isMale ? 5 : -161)
    }

    /// Recopie les données de profil présentes dans l'app Santé.
    @MainActor
    func importFromHealth(_ health: HealthDataStore) {
        if let w = health.latestWeightKg { weightKg = (w * 10).rounded() / 10 }
        if let h = health.heightCm { heightCm = h.rounded() }
        if let y = health.birthYear { birthYear = y }
        if let m = health.isMale { isMale = m }
        didImportFromHealth = true
    }

    static let activityLevels: [(factor: Double, label: String)] = [
        (1.2, "Sédentaire"),
        (1.375, "Légèrement actif (1-3 séances/sem.)"),
        (1.55, "Actif (3-5 séances/sem.)"),
        (1.725, "Très actif (6-7 séances/sem.)"),
        (1.9, "Extrêmement actif"),
    ]
}
