# Distribution — Morax Garage sur Morax One

Ce document décrit la chaîne de publication et de distribution du binaire natif macOS **Morax Garage** consommé par le hub **Morax One**.

---

## 1. Commande unique de release

La release s'exécute via une commande unique qui enchaîne automatiquement les 6 étapes : **préflight → build universel → signature Developer ID → packaging DMG → notarisation & staple → vérification post-distribution**.

```bash
scripts/package_release.sh
```

Pour produire une release distribuable officielle notarisée :

```bash
MORAX_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
MORAX_NOTARY_PROFILE="morax-notary" \
MORAX_TEAM_ID="<team-id>" \
scripts/package_release.sh
```

Pour un build de test local / staging sans notarisation :

```bash
ALLOW_UNNOTARIZED=1 scripts/package_release.sh
```

---

## 2. Artefacts produits

Les artefacts générés se trouvent dans `dist/release/` :

| Fichier | Rôle |
|---|---|
| `MoraxGarage-<version>.dmg` | Image disque finale distribuable (contenant l'app, le helper menubar, le lien `/Applications` et `LISEZ-MOI.txt`) |
| `MoraxGarage-<version>.dmg.sha256` | Empreinte cryptographique autonome du fichier DMG |
| `release.json` | Manifeste mesuré respectant strictement le contrat Morax One (§3.3) |

---

## 3. Contrat de manifeste `release.json` (Morax One §3.3)

Toutes les valeurs mesurables sont **mesurées sur le fichier produit** et non déclarées manuellement. Aucune URL n'est stockée dans le manifeste (le hub résout l'emplacement et signe une URL courte à l'usage).

Exemple de `release.json` généré (build ad-hoc, non notarisé ; une release notarisée porte `notarized: true`, `stapled: true`, `signedBy: "Developer ID Application"`) :

```json
{
  "app": "garage",
  "name": "Morax Garage",
  "version": "1.0.1",
  "channel": "stable",
  "platform": "macos",
  "arch": "universal",
  "minimumOS": "14.0",
  "releasedAt": "2026-10-10T12:00:00Z",
  "file": "MoraxGarage-1.0.1.dmg",
  "sizeBytes": 25202863,
  "sha256": "1ae64a40a331173fbf4d264c3b2f955184b2eb34b91dd2fb8e8e7eb8d6078e54",
  "notarized": false,
  "stapled": false,
  "signedBy": "Ad-hoc",
  "releaseNotes": "docs/CHANGELOG.md#101"
}
```

- `app` : slug strict dans `APP_SLUGS` de Morax One (`garage`).
- `arch` : extrait dynamiquement via `lipo -archs` (`universal`).
- `minimumOS` : extrait du `Info.plist` via `PlistBuddy` (`14.0`).
- `sha256` : calculé via `shasum -a 256`.
- `sizeBytes` : calculé via `stat -f%z`.
- `notarized` et `stapled` : vérité mesurée sur l'artefact.
- `releaseNotes` : ancre `docs/CHANGELOG.md#<version sans points>` (1.0.1 devient `#101`) ; le changelog doit contenir `<a id="101"></a>` avant la section de la version.

---

## 4. Variables d'environnement et Configuration de signature

La configuration de signature principale est définie dans `Config/Signing.xcconfig`.
Aucun secret, certificat ou identifiant privé n'est commité dans le dépôt (`*.local.xcconfig` et `.env` sont gitignorés).

| Variable | Description |
|---|---|
| `MORAX_SIGN_IDENTITY` | Nom de l'identité *Developer ID Application* dans le trousseau macOS. |
| `MORAX_NOTARY_PROFILE` | Nom du profil `notarytool` enregistré dans le trousseau. |
| `MORAX_TEAM_ID` | Identifiant d'équipe Apple Developer (10 caractères, lu dans `Config/Signing.xcconfig` si la variable n'est pas définie). |
| `MORAX_VERSION` | *(Optionnel)* Surcharge de la version définie dans `./VERSION`. |
| `MORAX_BUILD` | *(Optionnel)* Surcharge du numéro de build généré. |
| `MORAX_SUPABASE_URL` | URL du projet Supabase de Morax One (requis par `upload_release.sh`). |
| `SUPABASE_SERVICE_ROLE_KEY` | Clé service role (requis par `upload_release.sh`, jamais affichée). |
| `MORAX_STORAGE_BUCKET` | *(Optionnel)* Bucket de stockage, `releases` par défaut. |
| `MORAX_REF` / `MORAX_SRC_DIR` / `MORAX_REPO_URL` / `MORAX_RUN_TESTS` | *(Optionnel)* Réglages de `install-from-source.sh`. |
| `ALLOW_UNNOTARIZED` | *(Optionnel)* Vaut `1` pour autoriser une génération locale ad-hoc non notarisée. |

---

## 5. Prérequis pour la distribution notarisée

1. **Compte Apple Developer Program** : compte individuel payant. Les certificats de développement ont une validité de **1 an** (au lieu de 7 jours pour l'ancienne Personal Team) et la notarisation Developer ID pour macOS est pleinement accessible.
2. **Certificat Developer ID Application** installé dans le trousseau :
   ```bash
   security find-identity -v -p codesigning
   ```
3. **Profil notarytool configuré** dans le trousseau :
   ```bash
   xcrun notarytool store-credentials morax-notary \
     --apple-id "<apple-id-email>" \
     --team-id "<team-id>" \
     --password "<app-specific-password>"
   ```

---

## 6. Vérification post-distribution (`scripts/release-verify.sh`)

L'étape 6 du pipeline exécute une vérification stricte et indépendante sur le fichier DMG final :
- `codesign --verify --deep --strict --verbose=2` sur l'application et le DMG.
- `spctl -a -vvv -t install` (acceptation par Gatekeeper).
- `xcrun stapler validate` sur le DMG.
- Recalcul du SHA-256 et comparaison avec `release.json`.
- `lipo -archs` validant la présence des tranches `arm64` et `x86_64`.
- Montage du DMG (`hdiutil attach`), vérification du contenu et de `CFBundleShortVersionString`, puis démontage propre.

---

## 7. Mises à jour & Sparkle

Morax Garage n'embarque **aucun mécanisme de mise à jour Sparkle** en v1.
- Aucun composant ou framework Sparkle n'est lié.
- Aucun flux ou URL `SUFeedURL` n'existe dans l'application.
- Les téléchargements et mises à jour sont gérés de manière autoritaire par le hub Morax One.

---

## 8. Modes d'échec fréquents et remédiations

| Symptôme / Échec | Cause | Remédiation |
|---|---|---|
| **Preflight code 64** : `MORAX_SIGN_IDENTITY not found` | Certificat manquant dans le trousseau | Installer le certificat Developer ID exporté depuis developer.apple.com dans le trousseau de session. |
| **Preflight code 64** : `notarytool cannot use MORAX_NOTARY_PROFILE` | Profil notarytool non configuré | Exécuter `xcrun notarytool store-credentials <profil> --apple-id ... --team-id ... --password ...` |
| **Build failure** : `Metal toolchain required` | Compilation `swift build --arch` appelée | Ne pas utiliser `--arch` ; le script utilise `--triple` par tranche qui évite la dépendance xcbuild Metal. |
| **Verification failure** : `Gatekeeper rejected the app` | L'app n'est pas signée avec un Developer ID ou le ticket n'a pas été agrafé | Vérifier la soumission `notarytool` et `stapler staple`. |

---

## 9. GitHub Releases

Dépôt public : https://github.com/Etienne-Morax/morax-garage

Le workflow `.github/workflows/release.yml` se déclenche sur un tag `v*` (et manuellement via `workflow_dispatch`, sans publication) :

1. Vérifie que le tag correspond au fichier `VERSION` (`v1.0.1` pour `1.0.1`).
2. Exécute `ALLOW_UNNOTARIZED=1 scripts/package_release.sh` sur `macos-15` (signature ad-hoc, pas de notarisation).
3. Publie via `gh release create` le DMG, son `.sha256` et `release.json`, avec les notes extraites de `docs/CHANGELOG.md` (`scripts/release-notes.sh`).

Publier une version :

```bash
# 1. Mettre à jour VERSION et ajouter la section <a id="..."></a> dans docs/CHANGELOG.md, merger.
git tag v1.0.1 && git push origin v1.0.1
```

Les builds GitHub sont ad-hoc et non notarisés : au premier lancement, clic droit sur l'app puis **Ouvrir**, ou `xattr -dr com.apple.quarantine "/Applications/Morax Garage.app"`. La notarisation en CI (import d'un certificat Developer ID et d'un profil notarytool depuis des secrets de dépôt) reste un travail futur.

## 10. Install from source

Sans DMG, avec Xcode ou les Command Line Tools (Swift 6, macOS 14+) :

```bash
curl -fsSL https://raw.githubusercontent.com/Etienne-Morax/morax-garage/main/scripts/install-from-source.sh | bash
```

Le script clone (ou met à jour) `~/Library/Caches/morax-garage-src`, puis lance `scripts/install.sh` qui compile et installe les deux apps dans `/Applications` (signature ad-hoc, aucun `sudo`). `MORAX_REF=v1.0.1` fige un tag ou une branche ; `MORAX_RUN_TESTS=1` exécute aussi la suite de tests.

## 11. Publishing to Morax One

1. Produire la release : `ALLOW_UNNOTARIZED=1 scripts/package_release.sh` (ou la variante notarisée, §1).
2. Téléverser le DMG dans le stockage Morax One :
   ```bash
   MORAX_SUPABASE_URL="https://<project-ref>.supabase.co" \
   SUPABASE_SERVICE_ROLE_KEY="<service-role-key>" \
   scripts/upload_release.sh
   ```
   Le script vérifie l'existence de l'objet via l'endpoint authentifié `storage/v1/object/info/<bucket>/<fichier>`.
3. Copier `dist/release/release.json` vers `content/releases/garage.json` dans le dépôt Morax One et l'ouvrir en pull request. Le manifeste ne contient aucune URL : le hub signe l'URL de téléchargement.
