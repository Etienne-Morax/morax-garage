# Distribution — Morax Garage sur Morax One

Ce document décrit la chaîne de publication et de distribution du binaire natif macOS **Morax Garage** consommé par le hub **Morax One**.

---

## 1. Commande unique de release

La release s'exécute via une commande unique qui enchaîne automatiquement les 6 étapes : **préflight → build universel → signature Developer ID → packaging DMG → notarisation & staple → vérification post-distribution**.

```bash
scripts/package_release.sh
```

Sur un Mac configuré une fois avec `scripts/setup-notarization.sh` (§5), cette commande produit une release signée Developer ID, notarisée et agrafée : l'identité *Developer ID Application* de l'équipe est détectée dans le trousseau et le profil `notarytool` par défaut est `morax-notary`. Les variables `MORAX_SIGN_IDENTITY` et `MORAX_NOTARY_PROFILE` restent disponibles pour les surcharger.

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
| `MORAX_SIGN_IDENTITY` | *(Optionnel)* Identité *Developer ID Application*. Par défaut : celle de l'équipe trouvée dans le trousseau. |
| `MORAX_NOTARY_PROFILE` | *(Optionnel)* Profil `notarytool` du trousseau, `morax-notary` par défaut. |
| `MORAX_NOTARY_KEYCHAIN` | *(Optionnel)* Trousseau qui contient ce profil (utilisé par la CI, trousseau de session sinon). |
| `MORAX_TEAM_ID` | Identifiant d'équipe Apple Developer (10 caractères, lu dans `Config/Signing.xcconfig` si la variable n'est pas définie). |
| `MORAX_VERSION` | *(Optionnel)* Surcharge de la version définie dans `./VERSION`. |
| `MORAX_BUILD` | *(Optionnel)* Surcharge du numéro de build généré. |
| `MORAX_DOWNLOADS_BUCKET` | *(Optionnel)* Bucket R2 de `upload_release.sh`, `morax-downloads` par défaut. |
| `MORAX_WRANGLER` | *(Optionnel)* Commande wrangler de `upload_release.sh`, `npx --yes wrangler@4.151.1` par défaut. |
| `MORAX_REF` / `MORAX_SRC_DIR` / `MORAX_REPO_URL` / `MORAX_RUN_TESTS` | *(Optionnel)* Réglages de `install-from-source.sh`. |
| `ALLOW_UNNOTARIZED` | *(Optionnel)* Vaut `1` pour autoriser une génération locale ad-hoc non notarisée. |

---

## 5. Prérequis pour la distribution notarisée

1. **Compte Apple Developer Program** : compte individuel payant. Les certificats de développement ont une validité de **1 an** (au lieu de 7 jours pour l'ancienne Personal Team) et la notarisation Developer ID pour macOS est pleinement accessible.
2. **Configuration guidée, une fois par Mac** :
   ```bash
   scripts/setup-notarization.sh
   ```
   Le script vérifie la présence du certificat *Developer ID Application* de l'équipe et, s'il manque, indique comment le créer (Xcode > Settings > Accounts > Manage Certificates > « + » > Developer ID Application, rôle Account Holder requis). Il enregistre ensuite le profil `notarytool` `morax-notary` : l'Apple ID et un mot de passe d'application (account.apple.com > Connexion et sécurité) sont saisis dans les invites de `notarytool`, jamais dans le script.

### Releases notarisées en CI

`release.yml` notarise les GitHub Releases dès que ces cinq secrets existent sur le dépôt public (sinon la release reste ad-hoc ; un jeu incomplet fait échouer le workflow) :

| Secret | Contenu |
|---|---|
| `MACOS_DEVELOPER_ID_P12_BASE64` | Certificat Developer ID Application + clé privée exportés en `.p12` |
| `MACOS_DEVELOPER_ID_P12_PASSWORD` | Mot de passe du `.p12` |
| `NOTARY_API_KEY_P8_BASE64` | Clé API App Store Connect (`AuthKey_XXXX.p8`, rôle Developer) |
| `NOTARY_API_KEY_ID` | Key ID de cette clé |
| `NOTARY_API_ISSUER_ID` | Issuer ID (App Store Connect > Users and Access > Integrations) |

1. Trousseaux > *Developer ID Application: …* > clic droit > **Exporter** au format `.p12`.
2. App Store Connect > Users and Access > Integrations > **App Store Connect API** : créer une clé et télécharger le `.p8` (téléchargeable une seule fois).
3. Envoyer les secrets (le mot de passe du `.p12` est demandé dans une invite masquée) :
   ```bash
   scripts/set-ci-signing-secrets.sh developer-id.p12 AuthKey_XXXX.p8 <key-id> <issuer-id>
   ```

La CI importe le certificat dans un trousseau temporaire (`scripts/ci-import-signing.sh`), y stocke le profil `notarytool`, puis le supprime en fin de job.

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
| **Preflight** : `missing required environment variables: MORAX_SIGN_IDENTITY` | Aucun certificat Developer ID de l'équipe dans le trousseau | `scripts/setup-notarization.sh` |
| **Preflight** : `notarytool cannot use MORAX_NOTARY_PROFILE` | Profil notarytool absent ou mot de passe d'application révoqué | `scripts/setup-notarization.sh` |
| **CI** : `Signing secret for … is missing` | Secrets de signature partiellement définis | Relancer `scripts/set-ci-signing-secrets.sh` |
| **Build failure** : `Metal toolchain required` | Compilation `swift build --arch` appelée | Ne pas utiliser `--arch` ; le script utilise `--triple` par tranche qui évite la dépendance xcbuild Metal. |
| **Verification failure** : `Gatekeeper rejected the app` | L'app n'est pas signée avec un Developer ID ou le ticket n'a pas été agrafé | Vérifier la soumission `notarytool` et `stapler staple`. |

---

## 9. GitHub Releases

Dépôt public : https://github.com/Etienne-Morax/morax-garage

Le workflow `.github/workflows/release.yml` se déclenche sur un tag `v*` (et manuellement via `workflow_dispatch`, sans publication) :

1. Vérifie que le tag correspond au fichier `VERSION` (`v1.0.1` pour `1.0.1`).
2. Importe le certificat et la clé de notarisation si les secrets sont définis (§5), puis exécute `scripts/package_release.sh` sur `macos-15` : release notarisée avec secrets, ad-hoc (`ALLOW_UNNOTARIZED=1`) sans.
3. Publie via `gh release create` le DMG, son `.sha256` et `release.json`, avec les notes extraites de `docs/CHANGELOG.md` (`scripts/release-notes.sh`).

Publier une version :

```bash
# 1. Mettre à jour VERSION et ajouter la section <a id="..."></a> dans docs/CHANGELOG.md, merger.
git tag v1.0.1 && git push origin v1.0.1
```

Sans secrets de signature, les builds GitHub sont ad-hoc et non notarisés : au premier lancement, clic droit sur l'app puis **Ouvrir**, ou `xattr -dr com.apple.quarantine "/Applications/Morax Garage.app"`. Les notes de release et `release.json` indiquent toujours l'état réel.

## 10. Install from source

Sans DMG, avec Xcode ou les Command Line Tools (Swift 6, macOS 14+) :

```bash
curl -fsSL https://raw.githubusercontent.com/Etienne-Morax/morax-garage/main/scripts/install-from-source.sh | bash
```

Le script clone (ou met à jour) `~/Library/Caches/morax-garage-src`, puis lance `scripts/install.sh` qui compile et installe les deux apps dans `/Applications` (signature ad-hoc, aucun `sudo`). `MORAX_REF=v1.0.1` fige un tag ou une branche ; `MORAX_RUN_TESTS=1` exécute aussi la suite de tests.

## 11. Publishing to Morax One

1. Produire la release notarisée : `scripts/package_release.sh` (§1). Le hub refuse un manifeste dont la confiance annoncée contredit la signature.
2. Téléverser le DMG dans le bucket R2 privé de Morax One (ADR 0019 de Morax One), avec wrangler connecté au compte Cloudflare (`npx wrangler login`) :
   ```bash
   scripts/upload_release.sh
   ```
   Le script refuse un DMG dont le sha256 diffère de `release.json`, le place sous `morax-downloads/garage/<fichier>`, puis le relit depuis R2 et compare son sha256.
3. Ingérer le manifeste dans le dépôt Morax One, puis ouvrir une pull request : `pnpm release:ingest garage <chemin>/dist/release/release.json`. Le manifeste ne contient aucune URL : le Worker `morax-downloads` signe l'URL de téléchargement.
