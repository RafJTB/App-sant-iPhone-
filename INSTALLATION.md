# Installer l'app sur ton iPhone sans Mac

Apple n'installe sur un iPhone que des apps **signées**. Sans Mac, c'est GitHub (qui loue des Mac dans le cloud) qui compile et signe l'app pour toi.

| | **Option A – TestFlight** (recommandée) | **Option B – Sideloadly** (gratuite) |
|---|---|---|
| Coût | 99 €/an (Apple Developer Program) | Gratuit |
| Ordinateur | Aucun (iPhone + navigateur suffisent) | PC Windows obligatoire |
| Durée de validité | 90 jours par version, ré-envoi en 1 clic | **7 jours**, puis réinstallation depuis le PC |
| Données Santé | ✅ Fonctionne | ⚠️ Non garanti (dépend de la signature gratuite) |

---

## Option A – TestFlight (≈ 45 min la première fois, puis 1 clic)

### 1. S'inscrire au programme développeur Apple
- Installe l'app **Apple Developer** sur ton iPhone › onglet Compte › **S'inscrire**.
- 99 €/an. Apple vérifie ton identité : compte **24 à 48 h** avant validation.

### 2. Récupérer ton Team ID
- [developer.apple.com/account](https://developer.apple.com/account) › **Membership details** › note le **Team ID** (10 caractères, ex. `AB12CD34EF`).

### 3. Réserver l'identifiant de l'app (Bundle ID) avec HealthKit
- [developer.apple.com/account/resources/identifiers](https://developer.apple.com/account/resources/identifiers/list) › **+** › *App IDs* › *App*.
- Description : `Sante` · Bundle ID **Explicit** : par ex. `fr.tonprenom.sante` (doit être unique au monde).
- Dans la liste *Capabilities*, coche **HealthKit** › Continue › Register.

### 4. Créer la fiche de l'app dans App Store Connect
- [appstoreconnect.apple.com](https://appstoreconnect.apple.com) › **Apps** › **+** › *Nouvelle app*.
- Plateforme iOS · Nom : un nom unique (ex. « Suivi Santé perso ») · Langue : Français · Bundle ID : celui de l'étape 3 · SKU : `sante-1`.
- L'app ne sera **pas publiée** sur l'App Store : elle restera privée dans TestFlight.

### 5. Créer une clé API (pour que GitHub puisse signer à ta place)
- App Store Connect › **Utilisateurs et accès** › **Intégrations** › *App Store Connect API* › **Clés d'équipe** › **+**.
- Nom : `GitHub` · Accès : **Admin** (nécessaire pour créer les certificats de signature automatiquement).
- Note l'**Issuer ID** (en haut de la page) et le **Key ID**.
- **Télécharge le fichier `.p8`** : ⚠️ Apple ne le propose **qu'une seule fois**.

### 6. Donner ces informations à GitHub (secrets chiffrés)
Sur GitHub : dépôt **App-sant-iPhone-** › **Settings** › **Secrets and variables** › **Actions** › **New repository secret**, et crée ces 5 secrets :

| Nom du secret | Valeur |
|---|---|
| `APPLE_TEAM_ID` | Team ID (étape 2) |
| `BUNDLE_ID` | ex. `fr.tonprenom.sante` (étape 3) |
| `ASC_ISSUER_ID` | Issuer ID (étape 5) |
| `ASC_KEY_ID` | Key ID (étape 5) |
| `ASC_KEY_P8` | **Tout le contenu** du fichier `.p8`, lignes `-----BEGIN PRIVATE KEY-----` et `-----END PRIVATE KEY-----` comprises |

> Astuce iPhone pour copier le `.p8` : dans l'app Fichiers, renomme-le en `.txt`, ouvre-le, *Tout sélectionner* › *Copier*.
>
> Les secrets sont chiffrés : personne (ni toi, ni GitHub, ni moi) ne peut les relire après enregistrement.

### 7. Lancer la compilation
- GitHub › onglet **Actions** › **TestFlight** › **Run workflow** › choisis la branche › **Run workflow**.
- Compte ~5 min. Si c'est vert ✅, Apple traite ensuite le build (5 à 30 min).
- Si c'est rouge ❌, copie-moi le message d'erreur : je corrige.

### 8. Installer sur l'iPhone
- App Store Connect › ton app › **TestFlight** › *Tests internes* › **+** › crée un groupe et ajoute-toi.
- Installe l'app **TestFlight** depuis l'App Store, ouvre l'invitation reçue par mail › **Installer**.
- Au premier lancement, autorise l'accès à Santé et à la caméra.

**Mise à jour / prolongation** : relance simplement l'étape 7. TestFlight propose la nouvelle version automatiquement.

---

## Option B – Sideloadly sur PC Windows (gratuit)

1. GitHub › **Actions** › **Build iOS** › dernière exécution verte › section **Artifacts** › télécharge **Sante-ipa-non-signee** (dézippe : tu obtiens `Sante-non-signee.ipa`).
2. Sur le PC, installe **iTunes** et **iCloud** *version site Apple* (pas Microsoft Store), puis **Sideloadly** (sideloadly.io).
3. Branche l'iPhone en USB, glisse l'`.ipa` dans Sideloadly, saisis ton identifiant Apple, clique **Start**.
4. Sur l'iPhone : Réglages › Confidentialité et sécurité › **Mode développeur** › activer (redémarrage), puis Réglages › Général › **VPN et gestion de l'appareil** › faire confiance à ton identifiant.

Limites : l'app expire au bout de **7 jours** (à refaire depuis le PC), 3 apps maximum, et l'accès aux données Santé peut être refusé avec un compte gratuit selon la manière dont Sideloadly re-signe l'app.
