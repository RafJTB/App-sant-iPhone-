# Coach Abdos – PWA

Mini application web mobile, installable sur l'écran d'accueil, qui guide au quotidien vers des abdos visibles **sans perdre de poids** : recomposition corporelle, maintenance les jours de repos, léger surplus les jours d'entraînement.

Profil de départ : homme, 1,70 m, 60 kg, débutant, salle de sport, entraînement lun · mar · jeu · sam, sans restriction alimentaire, budget moyen. Tout est modifiable dans **Réglages**.

## Ce que fait l'app

| Onglet | Contenu |
|---|---|
| **Aujourd'hui** | Date, séance du jour, prochain repas avec l'heure et le compte à rebours, protéines et calories consommées vs objectif, rappels rapides, conseil du jour |
| **Repas** | 5 repas les jours d'entraînement, 4 les jours de repos, avec heure, ingrédients pesés, kcal et macros calculées automatiquement. 3 alternatives équivalentes par repas, extras, liste de courses sur 7 jours |
| **Séance** | Programme de 4 semaines (fondations → progression → volume → décharge) en haut / bas du corps + 3 blocs d'abdos par semaine. Séries, reps, repos, reps en réserve, technique, saisie de la charge, charge conseillée (double progression), minuteur de repos automatique |
| **Suivi** | Poids et tour de taille, moyennes hebdomadaires, graphique, analyse automatique de la tendance (« ajoute 150 kcal », « garde le cap »…), photos stockées uniquement sur le téléphone |
| **Rappels** | Eau (verres), sommeil (7-9 h, heure de coucher conseillée), pas (8 000-10 000), historique sur 7 jours |
| **Réglages** | Objectifs (avec recalcul Mifflin-St Jeor), jours et heure d'entraînement, horaires des repas, rappels, sauvegarde / import des données |

Des **bannières** apparaissent dans l'app à l'heure des repas, 30 min avant la séance, quand tu es en retard sur l'eau et avant l'heure du coucher.

### Objectifs par défaut

| | Jour d'entraînement | Jour de repos |
|---|---|---|
| Calories | 2 600 kcal | 2 400 kcal |
| Menu proposé | ≈ 2 600 kcal · 120 g de protéines | ≈ 2 440 kcal · 112 g de protéines |
| Protéines | objectif 115 g, zone 100-120 g | idem |

Maintenance estimée ≈ 2 390 kcal (Mifflin-St Jeor, 25 ans, activité 1,55). L'âge par défaut est une hypothèse : renseigne le tien dans Réglages puis touche « Recalculer depuis mon profil ». La vraie référence reste la tendance de ta balance (onglet Suivi).

## Installer sur ton iPhone

L'app doit être servie en HTTPS. Le plus simple : **GitHub Pages**, gratuit pour ce dépôt public.

1. Sur GitHub : dépôt **App-sant-iPhone-** › **Settings** › **Pages**.
2. *Build and deployment* › Source : **Deploy from a branch**.
3. Branche : celle qui contient le dossier `abdos/` (par exemple `claude/funny-edison-amsx0q`, ou la branche principale après fusion), dossier **/ (root)** › **Save**.
4. Attends 1 à 2 minutes, puis ouvre dans **Safari** sur l'iPhone :
   `https://rafjtb.github.io/App-sant-iPhone-/abdos/`
5. Bouton **Partager** › **Sur l'écran d'accueil** › **Ajouter**.
6. Lance l'app depuis l'icône une première fois avec du réseau : elle est ensuite disponible **hors ligne**.

> Alternative sans GitHub Pages : glisse le dossier `abdos/` sur [app.netlify.com/drop](https://app.netlify.com/drop) et ouvre l'URL obtenue dans Safari.

**Notifications système** (facultatif) : iOS 16.4 ou plus récent, app installée sur l'écran d'accueil, puis Réglages › « Autoriser les notifications système ».

## Fichiers

```
abdos/
├── index.html              L'app complète (HTML + CSS + JS, aucune dépendance externe)
├── sw.js                   Service worker : cache pour le mode hors ligne
├── manifest.webmanifest    Nom, couleurs et icônes de l'app installée
└── icons/                  Icônes (icon.svg = source des PNG)
```

`index.html` fonctionne aussi seul (ouvert directement), mais le mode hors ligne et l'installation exigent `sw.js` et `manifest.webmanifest` à côté : les navigateurs n'acceptent pas de service worker intégré dans la page.

## Modifier le contenu

Toutes les données sont regroupées en haut du script de `index.html`, section **1. DONNÉES MODIFIABLES** :

| Objet | Rôle |
|---|---|
| `FOODS` | Aliments, valeurs pour 100 g (kcal, protéines, glucides, lipides) |
| `MEALS` | Repas : liste `[aliment, grammes, libellé]`, les macros sont calculées automatiquement |
| `MEAL_SLOTS` / `MEAL_PLANS` | Créneaux et options proposées par type de journée (la 1re option est celle par défaut) |
| `EXERCISES` | Exercices : consignes techniques, palier de progression (`inc`) |
| `SCHEMES` | Séries × reps sur les 4 semaines |
| `SESSIONS` / `ABS_BLOCKS` / `ROTATION` | Composition des séances et ordre de rotation |
| `WEEKS`, `TIPS`, `DEFAULT_SETTINGS` | Consignes de chaque semaine, conseils du jour, réglages par défaut |

Après une modification publiée, change `CACHE` dans `sw.js` (ex. `coach-abdos-v2`) pour forcer la mise à jour sur le téléphone.

## Données et vie privée

- Tout est stocké **sur le téléphone** : `localStorage` pour les données, IndexedDB pour les photos (redimensionnées à 1 280 px). Rien n'est envoyé en ligne.
- Supprimer l'app de l'écran d'accueil efface ses données : utilise **Réglages › Exporter** de temps en temps (photos non incluses).

## Limites connues

- Les rappels ne s'affichent que lorsque l'app est ouverte ou vient d'être mise en arrière-plan : iOS suspend les web apps fermées. De vrais rappels app fermée demandent des notifications push avec un serveur (voir pistes ci-dessous).
- Les pas et le sommeil se saisissent à la main : une web app ne peut pas lire l'app Santé.
- Valeurs nutritionnelles moyennes (table Ciqual) : l'étiquette de tes produits fait foi.
- Conseils généraux, pas un avis médical.

## Pistes d'amélioration

1. **API nutrition** : recherche et scan de code-barres via Open Food Facts (déjà utilisé par l'app iOS du dépôt) pour remplacer les extras saisis à la main.
2. **Rappels push app fermée** : Web Push (iOS 16.4+) avec un petit serveur ou une fonction serverless qui envoie les rappels repas / eau / coucher à l'heure prévue.
3. **IA coach** : bilan hebdomadaire envoyé à un modèle de langage (poids, taille, charges, sommeil) qui ajuste calories et programme, et répond aux questions (« je n'ai pas de poulet, par quoi le remplacer ? »).
