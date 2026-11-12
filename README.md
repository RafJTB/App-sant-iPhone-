# Santé – sommeil, sport, repas et prise de poids (iPhone)

App iOS native (SwiftUI) qui lit tes données de l'app **Santé** et te permet de **saisir ce que tu manges** pour savoir si, au rythme actuel, **tu vas prendre du poids**.

## Ce que fait l'app

| Onglet | Contenu | Source |
|---|---|---|
| **Aujourd'hui** | Calories mangées vs objectif, protéines, verdict « Vais-je prendre du poids ? », graphique de balance, sommeil et activité du jour | Repas + Santé |
| **Repas** | Journal par repas, navigation par jour, **scan de code-barres**, **recherche dans les produits du commerce (Open Food Facts)**, ~55 aliments courants, récents, saisie manuelle | Local (iPhone) + Open Food Facts |
| **Sommeil** | Dernière nuit (coucher/réveil, phases profond/léger/paradoxal), 14 nuits, moyenne, régularité | Santé |
| **Sport** | Énergie active, pas, minutes d'exercice, séances des 30 derniers jours (type, durée, kcal, distance) | Santé |
| **Profil** | Poids/taille/âge/sexe (importés de Santé), surplus visé, protéines g/kg, niveau d'activité | Santé + toi |

### Comment est calculé le verdict

1. **Dépense du jour** :
   - avec Apple Watch → énergie au repos + énergie active (mesurées) + ~10 % des apports (digestion) ;
   - iPhone seul → métabolisme de base (Mifflin-St Jeor) + énergie active ;
   - rien → métabolisme de base × niveau d'activité.
2. **Balance** = calories mangées − dépense, uniquement sur les jours **où tu as saisi des repas** (sinon un jour vide ferait croire à un énorme déficit).
3. Moyenne sur les **7 derniers jours complets** (au moins 3 jours) → ~7 700 kcal ≈ 1 kg → **kg/semaine prévus**.
4. Comparaison avec la **tendance réelle de ta balance** (pesées Santé, régression sur 4 semaines). Si la balance monte moins vite que prévu, c'est souvent que des repas manquent ou que les portions sont sous-estimées.

> ⚠️ Ce sont des estimations : les calories brûlées affichées par les montres ont une marge d'erreur, et la règle des 7 700 kcal/kg est une approximation. La référence finale reste ta balance.

## Installer l'app sur ton iPhone

**Sans Mac** : suis [INSTALLATION.md](INSTALLATION.md) (TestFlight via GitHub, ou Sideloadly sur PC).

**Avec un Mac** : il faut **Xcode 16 ou plus récent** (gratuit sur le Mac App Store). L'iPhone doit être sous **iOS 17+**.

1. Clone le dépôt et ouvre `Sante.xcodeproj` dans Xcode.
2. Sélectionne la cible **Sante** › onglet **Signing & Capabilities** :
   - **Team** : choisis ton compte Apple (un compte gratuit suffit pour un usage perso) ;
   - **Bundle Identifier** : remplace `fr.monapp.sante` par un identifiant unique (ex. `fr.tonnom.sante`) ;
   - vérifie que la capability **HealthKit** est présente (sinon `+ Capability` › HealthKit).
3. Branche ton iPhone, active le **mode développeur** (Réglages › Confidentialité et sécurité › Mode développeur), sélectionne-le en haut d'Xcode et clique sur ▶︎.
4. Sur l'iPhone : Réglages › Général › VPN et gestion de l'appareil › fais confiance à ton certificat.
5. Au premier lancement, **autorise toutes les catégories** demandées par Santé.

> Avec un compte Apple gratuit, l'app doit être réinstallée depuis Xcode **tous les 7 jours**. Avec le programme développeur (99 €/an), elle reste 1 an et tu peux passer par TestFlight.

## Structure du code

```
Sante/
├── SanteApp.swift              Point d'entrée (SwiftData + objets partagés)
├── Models/
│   ├── FoodEntry.swift         Repas saisis (SwiftData), Macros, Meal
│   ├── FoodDatabase.swift      Aliments courants (valeurs /100 g)
│   └── ProfileStore.swift      Profil + métabolisme de base
├── Services/
│   ├── HealthDataStore.swift   Lecture HealthKit (activité, sommeil, séances, poids)
│   ├── SleepBuilder.swift      Regroupement des nuits, dédoublonnage iPhone/Watch
│   ├── WorkoutSummary.swift    Séances + noms/icônes en français
│   ├── OpenFoodFacts.swift     Client API Open Food Facts (code-barres + recherche)
│   └── EnergyAnalysis.swift    Balance énergétique, verdict, tendance de poids
└── Views/                      Les 5 onglets + composants
```

Un workflow GitHub Actions (`.github/workflows/build.yml`) compile l'app sur macOS à chaque push et teste le client Open Food Facts contre l'API réelle (`Tools/OFFCheck`).

### Scan de code-barres
- Utilise le scanner natif d'Apple (VisionKit) : **iPhone XS/XR ou plus récent**, ne fonctionne pas dans le simulateur (saisie du code possible en secours).
- Les données viennent d'**Open Food Facts**, une base collaborative : la plupart des produits français y sont, mais vérifie les valeurs avec l'étiquette en cas de doute.
- Un produit ajouté apparaît ensuite dans « Récents » : pas besoin de le rescanner.

## Pistes d'évolution

- Écrire les calories/macros dans Santé (`dietaryEnergyConsumed`) pour les partager avec d'autres apps.
- Objectif calorique ajusté automatiquement selon la tendance réelle de la balance.
- Widget écran d'accueil « calories restantes ».
