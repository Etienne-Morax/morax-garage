# Changelog — Morax Garage

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<a id="103"></a>
## [1.0.3] - 2026-10-19

### Added
- Bouton « Caches récurrents » dans l'onglet Nettoyage : un clic scanne les caches qui se remplissent après chaque installation ou build (npm/npx, uv, pip, Yarn, Go, CocoaPods, SwiftPM, Homebrew, DerivedData Xcode, anciennes versions des navigateurs Playwright) et pré-coche ceux sans risque. Rien ne part à la Corbeille avant confirmation ; les caches de Xcode ne sont pas cochés tant que Xcode est ouvert.
- L'écran de fin du nettoyage rappelle que l'espace n'est libéré qu'une fois la Corbeille vidée, avec un bouton « Open Trash ».

<a id="102"></a>
## [1.0.2] - 2026-10-16

### Added
- Ajout de la bande « Compteurs IA » : quotas cockpit authentifiés, cache local, Keychain,
  cadrans Claude/Codex/Gemini et dépense DeepSeek sans pourcentage inventé.
- Correctifs : fraîcheur locale des relevés hors ligne, dépense DeepSeek basée sur le solde
  fournisseur lorsqu’elle existe, pastilles secondaires complètes et tests URLProtocol injectables.
- Releases signed with a Developer ID Application certificate, notarized by Apple and stapled, built locally or by `release.yml` once its signing secrets exist.

### Notes
- This is the first notarized build: macOS opens it without the quarantine workaround needed for 1.0.1.

<a id="101"></a>
## [1.0.1] - 2026-10-10

### Added
- Open-source release: the project is now public at https://github.com/Etienne-Morax/morax-garage.
- GitHub Releases: pushing a `v*` tag builds the universal DMG, its SHA-256 and the `release.json` manifest, and publishes them.
- Install from source with a single command (`scripts/install-from-source.sh`), without needing a prebuilt DMG.
- `scripts/upload_release.sh` to push the DMG to Morax One storage (no hardcoded project URL, key never printed).

### Changed
- Code cleanup across the sources and release scripts; release verification now also checks that the manifest `signedBy` and `stapled` fields match the actual signature.
- Release scripts no longer embed any Apple Team ID.

### Notes
- Release builds published on GitHub are ad-hoc signed and not notarized (`notarized: false`, `stapled: false`). On first launch, right-click the app and choose Open, or run `xattr -dr com.apple.quarantine "/Applications/Morax Garage.app"`.

<a id="100"></a>
## [1.0.0] - 2026-08-25

### Added
- Native macOS universal application (Apple Silicon `arm64` and Intel `x86_64`) for Mac maintenance and performance optimization.
- Comprehensive cache cleaner auditing DaVinci Resolve render caches, Lightroom previews, Xcode/developer build artifacts, and system caches.
- LaunchAgents and LaunchDaemons audit module to inspect and manage persistence items.
- Real-time CPU, RAM, and Disk telemetry dashboard with live visualization.
- Dedicated standalone MenuBar companion helper (`Morax Garage Menu.app`) for continuous system health monitoring.
- Integration-ready release packaging and manifest contract (§3.3) for Morax One hub distribution.
