# ARCHITECTURE_MAP — Morax Garage

> Phase 1 : cartographie, en lecture seule. Branche `audit/system-audit-2026-09`, 2026-09-28.
> Chaque affirmation cite `path:line`. Quand un élément n'existe pas, il est noté **absent**. Les constats de la section 12 indiquent leur niveau de confiance.

---

## 1. Vue d'ensemble

Morax Garage est une application macOS 14+ de maintenance et de télémétrie. Elle est écrite en Swift 6 avec SwiftPM, sans projet Xcode.

| Élément | Valeur | Preuve |
|---|---|---|
| Manifest | `swift-tools-version: 6.0`, `.macOS(.v14)` | `Package.swift:1-7` |
| Produits | `MoraxCockpitKit` (library), `MoraxCockpit` (exe), `MoraxCockpitMenu` (exe) | `Package.swift:8-12` |
| Dépendance externe unique | SwiftTerm 1.18.0 (utilisée seulement par l'app principale) | `Package.swift:14-16`, `Package.resolved` |
| Version | `1.0.0` | `VERSION` |
| Bundles | `com.morax.garage` (app) et `com.morax.garage.menu` (helper, `LSUIElement`) | `scripts/build_app.sh:114-115`, `:188-205` |
| Taille | 34 631 lignes Swift dans `Sources/`, 55 fichiers de tests | `wc -l` |

### Graphe des modules

```
MoraxCockpit (app SwiftUI) ──► MoraxCockpitKit ◄── MoraxCockpitMenu (helper menu bar)
        │                            ▲
        └──► SwiftTerm               └── MoraxCockpitTests
```

`MoraxCockpitKit` ne dépend de rien. Il contient tous les services, scanners et modèles, ainsi que des vues partagées : le HUD Mini Cockpit et la vue de la barre de menus (`Core/DesignSystem/MoraxMenuBarView.swift`).

### Sous-dossiers de `MoraxCockpitKit`

| Dossier | Rôle | Fichiers clés |
|---|---|---|
| `Core` | Réglages, runner de processus, registre d'outils, journal, corbeille, SafetyGate, Keychain, design system | `AppSettings.swift`, `ProcessRunner.swift`, `ToolRegistry.swift`, `OperationLog.swift`, `TrashService.swift`, `SafetyGate.swift`, `KeychainSecret.swift`, `TelemetryLogger.swift` |
| `Metrics` | Télémétrie en direct (CPU/GPU/RAM/réseau/processus/caches) et coordinateur | `TelemetryCoordinator.swift`, `SystemMetricsService.swift`, `NetworkMetricsService.swift`, `ProcessResourceService.swift`, `CacheTelemetryService.swift`, `GpuProcessSampler.swift`, `NativeGpuSampler.swift` |
| `Diagnostics` | Moteur de règles, historique persistant, pression mémoire | `DiagnosticService.swift`, `DiagnosticEngine.swift`, `TelemetryHistoryStore.swift`, `MemoryPressureMonitor.swift` |
| `Scanners` | Scanners de nettoyage (Resolve, photo, navigateurs, système, dev, installeurs, Claude Code, caches d'apps) | `*Scanner.swift`, `FileItem.swift` |
| `Services` | État persistant par onglet et cache disque des scans | `CachedScanStore.swift`, `CleanupStateService.swift`, `Apps*`, `Audit*`, `Brew*`, `EnvironmentStateService.swift`, `PermissionsService.swift`, `UpdateService.swift` |
| `StorageMap` | Parcours du disque, treemap, staging | `StorageScanner.swift`, `StorageNode.swift`, `StorageMapStateService.swift`, `TreemapLayoutEngine.swift` |
| `Usage` | Quotas IA (cockpit interne) et coûts OpenAI | `UsageQuotaService.swift`, `OpenAICostsService.swift`, `UsageQuotaCredentials.swift` |
| `MiniCockpit` | HUD flottant (NSPanel) | `MiniCockpitWindowController.swift`, `MiniCockpitStateEngine.swift`, `MiniCockpitHUDView.swift` |
| `PhotoSync` | Suivi des projets photo Mac → SSD → NAS, copie rsync | `PhotoSyncScanner.swift`, `PhotoSyncStateService.swift`, `PhotoSyncCopyPlan.swift` |
| `AIModels` | Inventaire et désinstallation de modèles locaux (Ollama, HF, LM Studio) | `AIModelScanner.swift`, `AIModelUninstaller.swift`, `AIModelsStateService.swift` |
| `Higgsfield`, `MetaMuse` | Crédits Higgsfield (CLI) et activité Muse Code (CLI et logs locaux) | `HiggsfieldCreditService.swift`, `MetaMuseService.swift` |

**Patron dominant :** 37 singletons `static let shared` (`grep -rn 'static let shared' Sources`). La plupart sont `@MainActor @Observable`. Les vues les référencent via `@State private var x = Service.shared`.

---

## 2. Interface

### 2.1 Fenêtres et scènes (app principale)

| Scène | Détail | Preuve |
|---|---|---|
| `WindowGroup("Morax Garage", id: "main_window")` | `RootView`, 1080×720 par défaut, min 640×480 | `App/MoraxCockpitApp.swift:18-29` |
| `MenuBarExtra(isInserted: $menuBarEnabled)` | Style `.window`, contenu `MoraxMenuBarContent`, label `MoraxMenuBarLabel` | `App/MoraxCockpitApp.swift:41-49` |
| Mini Cockpit HUD | `NSPanel` créé par `MiniCockpitWindowController`, niveau `.floating` ou `.normal`, option `canJoinAllSpaces` | `MiniCockpit/MiniCockpitWindowController.swift:151-162` |
| Fermeture de la dernière fenêtre | L'app reste active (`return false`) | `App/MoraxCockpitApp.swift:85-88` |
| Fenêtre « Liquid Glass » | Fenêtre non opaque, fond `.clear`, `NSVisualEffectView .sidebar/.behindWindow` | `App/RootView.swift:245-253` ; `WindowLiquidGlassConfigurator` en fin de `RootView.swift` ; `MoraxCockpitApp.swift:109-111` |

### 2.2 Navigation par onglets

`NavigationSplitView` : barre latérale groupée, et un seul onglet monté à la fois via un `switch` dans `tabView(for:)` (`App/RootView.swift:325-345`). Changer d'onglet **reconstruit la vue**. L'état survit dans les singletons. Les sous-onglets de Réglages restent vivants après une première visite (`ZStack` + `.opacity`, `Features/Settings/SettingsView.swift:53,72-77`).

| Item (`GarageNavigationItem`) | Vue | Chargement à l'apparition | Cache |
|---|---|---|---|
| Dashboard | `DashboardView` | `onAppear` → `TelemetryCoordinator.acquire` (`DashboardView.swift:118-141`) | direct |
| Sync Photos | `PhotoSyncView` | `.task { scan(force:false) }` (`PhotoSyncView.swift:40`) | TTL 6 h (`PhotoSyncStateService.swift:36`) |
| Storage Map | `StorageMapView` | `restoreCacheFromDisk()` hors main (`StorageMapView.swift:102-105`) | plist ≤ 48 Mo (`StorageMapStateService.swift:50`) |
| Cleanup & Cache | `CleanupView` | cache chargé à l'init (`CleanupStateService.swift:108-120`) | `cleanup_cache.plist` |
| Modèles IA | `AIModelsView` | `.task { scan() }` (`AIModelsView.swift:26`) | TTL 24 h (`AIModelsStateService.swift:75-76`) |
| Applications | `AppsView` | `loadApps(force:false)` (`AppsView.swift:93`) | TTL 24 h |
| Persistence Audit | `AuditView` | `loadAudit(force:false)` (`AuditView.swift:104`) | TTL 24 h |
| Environment | `EnvironmentView` | `loadTools(force:false)` (`EnvironmentView.swift:68`) | TTL 24 h |
| Réglages / Permissions / Mole Terminal / Homebrew / Démo | `SettingsView` avec sous-onglets | Permissions : `checkAllPermissions()` synchrone (`PermissionsView.swift:65`) ; Brew : `loadOutdated(force:false)` (`BrewView.swift:117`) | — |

### 2.3 Mini Cockpit HUD

- Démarré au lancement si `morax_mini_cockpit_enabled` (`MoraxCockpitApp.swift:77-82`, et aussi `MoraxCockpitMenuApp.swift:27-31`).
- Demande de télémétrie : `[.system, .process, .usage, .openAICosts]`. Les deux branches `isExpanded` sont **identiques** (`MiniCockpitStateEngine.swift:401-420`).
- Boucle d'observation à 1 Hz sur le MainActor qui recopie `SystemMetricsService` et `ProcessMetricsService` (`MiniCockpitStateEngine.swift:422-434`).
- Rendu : `NSVisualEffectView .hudWindow` (`MiniCockpitLiquidGlass.swift:16-30`) et sparkline `Canvas` (`MiniCockpitTiles.swift:46`).

### 2.4 Barre de menus

| Hôte | Mécanisme | Preuve |
|---|---|---|
| App principale | `MenuBarExtra` intégrée, activée par défaut (`morax_menubar_enabled` = true) | `MoraxCockpitApp.swift:15,41` ; `AppSettings.swift:323` |
| Helper `MoraxCockpitMenu` | App séparée `LSUIElement` avec son propre `MenuBarExtra` et ses propres instances des services Kit | `MoraxCockpitMenu/MoraxCockpitMenuApp.swift:5-17` ; `build_app.sh:204` |
| Label | Acquiert `.system` si CPU, RAM, température, disque **ou alerte swap** est affiché, et `.network` si le réseau l'est | `MoraxMenuBarView.swift:133-145` |
| Popover | Acquiert `[.system, .network, .process]` pendant qu'il est ouvert | `MoraxMenuBarView.swift:382-390` |

Le helper ouvre l'app principale via `NSWorkspace` avec `com.morax.garage`, puis `com.morax.cockpit`, puis des chemins `/Applications` (`MoraxCockpitMenuApp.swift:41-58`). `install.sh` installe les deux apps (`scripts/install.sh:29-30`).

---

## 3. Services, threads, tâches et acteurs

### 3.1 Coordination de la télémétrie

`TelemetryCoordinator` (`@MainActor`, `Metrics/TelemetryCoordinator.swift:47-170`) compte les demandes par consommateur (`demands: [String: Set<TelemetryFeed>]`). Un flux démarre à la première demande. Il s'arrête **5 s** après le dernier retrait (`defaultStopGracePeriod`, `:60`). `releaseAll()` s'exécute à la terminaison (`MoraxCockpitApp.swift:128`).

| Flux (`TelemetryFeed`) | Service | Source | Cadence |
|---|---|---|---|
| `.system` | `SystemMetricsService` | `macmon pipe -i 1500` en flux continu + fallback Darwin (`host_statistics`, `sysctl`) | 1,5 s (`SystemMetricsService.swift:324,543-547`) ; watchdog 4 s (`:401-417`) |
| `.network` | `NetworkMetricsService` | `/usr/bin/nettop -P -c -L 1 …` lancé une fois par tick, fallback `getifaddrs`/`SCDynamicStore` | 3,5 s (`NetworkMetricsService.swift:139,266-282`) |
| `.process` | `ProcessMetricsService` | `/bin/ps -axo pid,%cpu,rss,comm` + IORegistry `IOAccelerator` (GPU par processus) | 5 s (`ProcessResourceService.swift:222,347-362`) |
| `.usage` | `UsageQuotaService` | HTTPS `GET {base}/api/usage/quotas`, en-tête `X-Internal-Key` | 300 s, backoff jusqu'à 900 s (`UsageQuotaService.swift:8-10,92-99`) |
| `.openAICosts` | `OpenAICostsService` | `https://api.openai.com/v1/organization/costs` | 300 s (`OpenAICostsService.swift:15-19`) |
| `.higgsfield` | `HiggsfieldCreditService` | CLI `higgsfield`/`hf` (`account status --json`, `workspace list/set`) | 300 s (`HiggsfieldCreditService.swift:38,142,256,287`) |
| `.metaMuse` | `MetaMuseService` | CLI `muse export` + `~/.local/share/muse/sessions` | 300 s (`MetaMuseService.swift:133,167`). **Jamais demandé par aucun consommateur** (le seul `.metaMuse` est `TelemetryCoordinator.swift:80`) |

Consommateurs déclarés (`TelemetryCoordinator.swift:173-186`) : `dashboard`, `menuBarPopover`, `menuBarLabel`, `miniCockpit`, `miniCockpitDetail` et `usage`. `usage` n'est jamais utilisé.

### 3.2 Services hors coordinateur

| Service | Déclencheur | Détail |
|---|---|---|
| `CacheTelemetryService` | Démarré dans `applicationDidFinishLaunching` (`MoraxCockpitApp.swift:72`) | Scan quotidien (maxAge 24 h), vérification toutes les heures dans un `Task.detached(.background)`. 5 scanners lancés en parallèle (`CacheTelemetryService.swift:194-230`) |
| `PermissionsService` | Au lancement, puis à chaque `NSApplication.didBecomeActiveNotification` | `checkAllPermissions()` synchrone sur main (`PermissionsService.swift:100-127`) |
| `UpdateService` | Au lancement selon la fréquence | **Simulé** : aucune requête réseau, renvoie toujours « à jour » (`UpdateService.swift:79-118`) |
| `DiagnosticService` | Reçoit chaque snapshot système, processus et cache | `@MainActor`. Persiste l'historique (`DiagnosticService.swift:41-85`) |
| `MemoryPressureMonitor` | `DispatchSource.makeMemoryPressureSource(queue: .main)` | `MemoryPressureMonitor.swift:19` |
| `RunningApplicationsIndex` | Notifications `NSWorkspace` didLaunch/didTerminate | `RunningApplicationsIndex.swift:29-30` |

### 3.3 Modèle de concurrence

- **MainActor** : pratiquement tous les services d'état (`@MainActor @Observable`). Les boucles de collecte sont des `Task.detached(priority: .userInitiated)` qui reviennent sur main pour publier.
- **Acteur** : `GpuProcessStateTracker` (`GpuProcessSampler.swift:112`).
- **Verrous** : `cachedScanStoreFileLock` (`CachedScanStore.swift:11`), `OperationLog.lock` et `ProcessRegistry`.
- **Timers** : aucun `Timer` ni `TimelineView`. Toutes les cadences reposent sur `Task.sleep`.
- **Animations infinies** : seulement pendant un scan (`StorageMapView.swift:1079-1085`, `DashboardView.swift:1030`, `HiggsfieldCreditCard.swift:113`).

---

## 4. Processus enfants, daemons et helpers

| Processus | Lancé par | Durée de vie |
|---|---|---|
| `macmon pipe -i 1500` (Homebrew, résolu par `ToolRegistry`) | `.system` | Continu tant que le flux est demandé. Observé en enfant de l'app installée : `pgrep` → `49156 /opt/homebrew/bin/macmon pipe -i 1500` |
| `/usr/bin/nettop` | `.network` | Un lancement toutes les 3,5 s |
| `/bin/ps` | `.process` | Un lancement toutes les 5 s, plus des appels synchrones (voir C5) |
| `/usr/bin/pgrep` | `ClaudeCodeScanner` | Ponctuel (`ClaudeCodeScanner.swift:26`) |
| `brew outdated --json=v2` | `BrewService` | Ponctuel (`BrewService.swift:70-77`) |
| `/usr/bin/rsync` | Copie PhotoSync | Flux pendant la copie (`PhotoSyncCopyPlan.swift:23`, `PhotoSyncStateService.swift:288`) |
| `ollama rm <model>` | Désinstallation de modèles | Ponctuel (`AIModelUninstaller.swift:101-112`) |
| CLI `higgsfield`/`hf`, `muse` | Flux crédits | Ponctuel, timeout 8 s ou 30 s |
| `$SHELL -l` (SwiftTerm `LocalProcessTerminalView`) | Onglet Mole Terminal | Créé une fois, puis conservé jusqu'à la fin de l'app (`TerminalView.swift:109-127`). Non couvert par `ProcessRunner.terminateAll()` |
| `NSAppleScript` → Terminal `higgsfield auth login` | Bouton de connexion Higgsfield | Ponctuel (`HiggsfieldCreditCard.swift:445-458`) |
| `MoraxCockpitMenu` (helper) | Lancement manuel | Instancie ses propres services, donc son propre `macmon` (observé : `87395 macmon` enfant de `.build/release/MoraxCockpitMenu`) |

**Launch agents / daemons propres à l'app :** absents. L'app ne fait que *lire* `~/Library/LaunchAgents`, `/Library/LaunchAgents` et `/Library/LaunchDaemons` pour l'audit (`AuditService.swift:4-17`).
**Login item :** `SMAppService.mainApp.register()/unregister()`, piloté par `morax_launch_at_login` (`AppSettings.swift:392-407`).

---

## 5. Stockage local

### 5.1 `~/Library/Application Support/MoraxGarage/` (état observé)

| Fichier | Taille | Écrit par | Format |
|---|---|---|---|
| `storage_map_cache.plist` | **29,5 Mo** | `StorageMapStateService.saveCacheToDisk` (`:185-215`) | Binary plist, ≤ 80 000 nœuds, profondeur ≤ 12 (`:43-46`) |
| `telemetry-history.json` | **4,3 Mo** (9 980 records, 1 000 processRecords, 31 cacheRecords) | `TelemetryHistoryStore.write` (`:209-216`) | JSON, réécrit en entier à chaque ajout |
| `cleanup_cache.plist` | 601 Ko | `CleanupStateService` / `CachedScanStore` | plist |
| `usage-quotas.json` | 6 Ko | `UsageQuotaService.persist` (`:149-155`) | JSON |
| `photo_sync_cache.plist`, `ai_models_cache.plist`, `apps_inventory_cache.plist`, `persistence_audit_cache.plist`, `environment_tools_cache.plist` | 1–22 Ko | `CachedScanStore` (TTL 24 h, 6 h pour PhotoSync) | plist |

Autre répertoire : `~/Library/Application Support/Morax Garage/bin` (avec une espace). C'est le dossier d'outils gérés, consulté en premier par `ToolRegistry.resolveBinaryPath` (`ToolRegistry.swift:41-43,58-60`). Il est vide.

### 5.2 Autres emplacements

| Emplacement | Contenu | Preuve |
|---|---|---|
| `~/Library/Logs/MoraxGarage/operations.log` | Journal des opérations de corbeille et nettoyage (JSONL en ajout, **sans rotation**), 134 Ko | `OperationLog.swift:82-84` |
| `~/Library/Caches/MoraxCockpit/` | `Cache.db` (+wal/shm), `WebKit/`, `fsCachedData/`, daté du 3 septembre. C'est le cache `URLSession.shared` d'un ancien identifiant (exécution sans bundle). Seul `GeneralSettingsView.swift:190` utilise encore `URLSession.shared`. Aucun `WKWebView` dans le code | `ls` ; grep `WKWebView` : absent |
| `$TMPDIR/metamuse-export-<UUID>.json` | Export temporaire, supprimé par `defer` | `MetaMuseService.swift:56-58` |
| Keychain | Service `com.morax.garage.usage`, comptes `internal-key` et `openai-admin-key` | `UsageQuotaCredentials.swift:4-19` |

### 5.3 Clés UserDefaults (domaine `com.morax.garage`)

- **Général** : `morax_show_dock_icon`, `morax_launch_at_login`, `morax_update_check_frequency`, `morax_temperature_unit`, `morax_keep_menubar_position`, `morax_macos_widgets_enabled`, `morax_appearance_mode` (`AppSettings.swift:86-91` ; `RootView.swift:81`)
- **Mini Cockpit** : `morax_mini_cockpit_enabled`, `_always_on_top`, `_all_spaces`, `_expanded`, `_appearance` (`AppSettings.swift:94-98`)
- **Barre de menus** : `morax_menubar_enabled`, `_show_icon`, `_show_cpu`, `_show_ram`, `_show_network`, `_show_disk`, `_show_temperature`, `_show_swap_alert` (défaut **true**, `:346`) (`AppSettings.swift:101-108`)
- **Usage / IA** : `morax_usage_cockpit_base_url` (défaut `https://<your-usage-cockpit-host>`, `:352`), `dashboard_show_usage_quotas`, `morax_higgsfield_monitoring_enabled`, `morax_metamuse_monitoring_enabled`, `morax_metamuse_project_id`, `morax_metamuse_team_id`, `morax_metamuse_manual_percent`, `morax_metamuse_manual_updated_at`, `morax_openai_costs_project_id`, `dashboard_show_cockpit_binnacle`
- **Données** : `morax_cockpit_cached_cache_snapshot` (snapshot JSON des caches, `CacheTelemetryService.swift:128,187-189`), `morax_photo_sync_configuration` (`PhotoSyncStateService.swift:37`), `morax_last_update_check_date` (`UpdateService.swift:40`)

**Bases de données :** absentes (pas de SQLite, Core Data ni SwiftData). Le seul `Cache.db` est celui de `URLCache`.

---

## 6. Réseau

| Endpoint | Méthode et auth | Code |
|---|---|---|
| `{morax_usage_cockpit_base_url}/api/usage/quotas` (Tailscale `*.ts.net` par défaut) | GET, `X-Internal-Key` lu dans le Keychain, session éphémère, timeout 8 s | `UsageQuotaService.swift:92-99` ; test de connexion : `GeneralSettingsView.swift:185-190` |
| `https://api.openai.com/v1/organization/costs` | GET, clé admin OpenAI (Keychain) | `OpenAICostsService.swift:19,97-99` |
| Higgsfield | Indirect, via le CLI | `HiggsfieldCreditService.swift` |
| Liens ouverts dans le navigateur | `github.com/morax/garage/releases`, `github.com/higgsfield-ai/cli`, `dev.meta.ai/usage/` | `UpdateService.swift:19` ; `GeneralSettingsView.swift:958` ; `MetaMuseModels.swift:198` |

**Serveur local / port en écoute :** absent.

---

## 7. Permissions OS, sandbox et signature

- **Sandbox :** absent. Aucun fichier `.entitlements` dans le dépôt. Signature ad hoc `--sign -` par défaut, hardened runtime seulement avec une identité Developer ID (`build_app.sh:229-236`).
- **Chaînes TCC dans Info.plist :** `NSFullDiskAccessUsageDescription`, `NSDownloadsFolder…`, `NSDesktopFolder…`, `NSDocumentsFolder…`, `NSRemovableVolumes…`, `NSAppleEvents…`, `NSSystemAdministration…` (`build_app.sh:140-153`).
- **Vérifications à l'exécution :** Full Disk Access testé en ouvrant `TCC.db` (`PermissionsService.swift:194-221`), Accessibility via `AXIsProcessTrusted()` (`:180`). Les réglages système s'ouvrent via des URL `x-apple.systempreferences:` (`:59-67`).
- **Apple Events :** `NSAppleScript` qui pilote Terminal (`HiggsfieldCreditCard.swift:456`).

## 8. Notifications, mises à jour, logs et crashs

| Sujet | État |
|---|---|
| Notifications utilisateur (`UNUserNotificationCenter`) | **absent** |
| Notifications internes | `NotificationCenter` : `.moraxReopenMainWindow`, `.moraxNavigateToTab` (`MoraxCockpitApp.swift:5-8`) |
| Auto-update (Sparkle ou autre) | **absent** ; `UpdateService` est un stub qui fait patienter 700 ms (`UpdateService.swift:97-100`) |
| Logs | `os.Logger` avec les sous-systèmes `com.morax.cockpit` (Telemetry, ProcessRunner, Lifecycle ; `TelemetryLogger.swift:5-7`) et `com.morax.garage` (TelemetryHistory ; `TelemetryHistoryStore.swift:138`), plus `operations.log` |
| Crash reporting / MetricKit | **absent** |

## 9. IA, GPU et agents

| Sujet | État |
|---|---|
| Modèles IA locaux | **Inventaire seulement** : `~/.ollama/models`, `~/.cache/huggingface/hub`, `~/.lmstudio/models`, `~/.cache/lm-studio/models` (`AIModelScanner.swift:28,122,153-154`). Suppression via `ollama rm` ou la corbeille |
| Runtime d'inférence, serveur d'inférence, CoreML, MLX | **absent** |
| Embeddings, vector store | **absent** |
| Agents, prompts, outils LLM, MCP | **absent** dans l'app. Les chemins `.claude/*` et `mcp-configs` sont seulement protégés par `SafetyGate` (`SafetyGate.swift:69-74`) ou scannés comme caches (`ClaudeCodeScanner.swift`) |
| API de modèles | Aucun appel d'inférence. Seulement le **reporting** de coûts et quotas (OpenAI costs, cockpit interne, Higgsfield, Meta Muse) |
| GPU / Metal | Pas de `Metal`/`MTL`. GPU lu via `macmon` et IORegistry `IOAccelerator` (`NativeGpuSampler.swift:14-29`, `GpuProcessSampler.swift:32-60`). Le coût GPU côté app vient du compositing : `NSVisualEffectView` et fenêtres transparentes |

## 10. Build et outillage

- `scripts/build_app.sh` : build universel arm64 et x86_64 (vérification `lipo`, `:217-227`), `.app` écrits dans `dist/`.
- `install.sh` : copie dans `/Applications`, signature ad hoc `--deep`, `killall -9` des anciennes instances (`install.sh:33,56-57`).
- Autres scripts : `package_release.sh`, `release-preflight.sh`, `release-verify.sh`, `uninstall.sh`, `scripts/bench/` (non suivi par git).

## 11. Cycle de vie au lancement

`applicationDidFinishLaunching` (`MoraxCockpitApp.swift:55-83`) :
1. `applyDockVisibility`, `syncLaunchAtLoginStatus`.
2. `ensureMainWindowVisible` après 150 ms.
3. `PermissionsService.checkAllPermissions()` (synchrone).
4. `CacheTelemetryService.startMonitoring()`.
5. `UpdateService.checkOnLaunchIfNeeded`.
6. Mini Cockpit si activé.

En parallèle, le premier accès à `TelemetryCoordinator.shared` (label de la barre de menus, `RootView.onAppear`) instancie **les 7 services** de la table `controls` (`TelemetryCoordinator.swift:74-82`).

Terminaison (`:126-131`) : HUD masqué, `releaseAll()`, arrêt du cache telemetry, `ProcessRunner.terminateAll()`.

---

## 12. Constats de la phase 1 (priorisés)

| # | Constat | Preuve | Impact | Confiance |
|---|---|---|---|---|
| C1 | **La barre de menus garde `macmon` actif en permanence par défaut.** `requiredFeeds` ajoute `.system` dès que `menuBarShowSwapAlert` est vrai, et cette option vaut `true` par défaut. `morax_menubar_enabled` vaut aussi `true` par défaut. Le flux `.system` (macmon à 1,5 s, fallback Darwin, `DiagnosticService.ingest` sur main) tourne donc toute la vie de l'app, fenêtre cachée comprise. C'est contraire à la règle « demand-driven » et cela contredit le « hidden idle 0 % » de Pass 2 | `MoraxMenuBarView.swift:133-145` ; `AppSettings.swift:323,346` ; `MoraxCockpitApp.swift:15,41` ; runtime : `macmon pipe -i 1500` (pid 49156) enfant de `/Applications/Morax Garage.app` | CPU idle (0,76 % mesuré), wakeups, empêche l'app d'être vraiment au repos | Haute |
| C2 | **L'historique de télémétrie est réécrit en entier sur le MainActor.** Chaque `append` recharge le fichier, filtre et trie 10 000 records, puis réencode les **4,3 Mo** de JSON en écriture atomique. Cela arrive jusqu'à deux fois par minute (système et processus, compteurs 60 s indépendants). En plus, `ingestProcesses` calcule toutes les 5 s `processMemoryStatistics` pour chaque top app en parcourant les 1 000 processRecords | `DiagnosticService.swift:4-6,41-73` ; `TelemetryHistoryStore.swift:168-178,209-231` ; fichier : 9 980 + 1 000 + 31 records | Saccades sur main, E/S disque continues, CPU | Haute (code) / Moyenne (ampleur) |
| C3 | **Le JSON de 4,3 Mo est décodé de façon synchrone sur main au lancement**, au premier accès à `DiagnosticService.shared` (déclenché par le premier `updateSnapshot` ou par `ingestCache`) | `DiagnosticService.swift:21-27` ; `TelemetryHistoryStore.swift:147-166` ; `SystemMetricsService.swift:734-738` | Temps jusqu'à la première fenêtre (1,3–2,1 s) | Haute (code) / Moyenne (part du temps) |
| C4 | **Le décodage du flux `macmon` tourne sur le MainActor.** `streamFromMacmon` est une méthode isolée de la classe `@MainActor`, donc la boucle `for await` et `decoder.decode` + `createSnapshot` s'exécutent sur main à chaque ligne (1,5 s) | `SystemMetricsService.swift:318-319,538-564` | CPU main en continu, en cumul avec C1 | Haute |
| C5 | **`ps` est lancé de façon synchrone sur main.** `ProcessMetricsService.init()` et `startMonitoring()` appellent `sampleImmediate()`, qui lance `/bin/ps -axo` et bloque sur `readDataToEndOfFile`/`waitUntilExit`, en plus d'un parcours IORegistry. L'`init` est déclenché tôt par `TelemetryCoordinator.init` | `ProcessResourceService.swift:233-243,275-280,347-358` ; `TelemetryCoordinator.swift:74-82` | Latence au lancement et à chaque (re)démarrage du flux processus, pire sous charge | Haute |
| C6 | **Le calcul des volumes disque tourne sur main, NAS compris.** `getDiskVolumes()` appelle `mountedVolumeURLs(... .skipHiddenVolumes)` puis `volumeAvailableCapacityForImportantUsageKey` pour chaque volume. Cela inclut les montages réseau (NAS `/Volumes/Storage 2`, `PhotoSyncModels.swift:21`), toutes les 30 s, depuis des méthodes isolées au MainActor | `SystemMetricsService.swift:740-783` | Blocage possible du thread UI si le NAS dort ou répond lentement | Moyenne |
| C7 | **L'identifiant de consommateur `"dashboard"` a deux écrivains aux demandes différentes.** `RootView` acquiert `[.system,.network,.process]` et `DashboardView` acquiert ce même ensemble plus `.usage/.openAICosts/.higgsfield`. `acquire` remplace la demande : le dernier appel gagne, et l'ordre `onAppear`/`onChange` n'est pas garanti. Les flux d'usage peuvent donc s'arrêter après 5 s ou basculer d'état | `RootView.swift:266-290` ; `DashboardView.swift:118-141` ; `TelemetryCoordinator.swift:98-107` | Données d'usage figées ou démarrages et arrêts inutiles | Moyenne |
| C8 | **L'arbre Storage Map reste en mémoire indéfiniment.** Après une visite, jusqu'à 80 000 objets `StorageNode` (classes) décodés d'un plist de 29,5 Mo restent dans le singleton. Il n'y a ni éviction quand on quitte l'onglet ni réaction à la pression mémoire (seul `clearCache()` les libère, par action utilisateur) | `StorageMapStateService.swift:8,43,117-124,298-299` ; `StorageNode.swift:246,269` | Candidat plausible pour les 192 Mo de « Malloc Small » de l'app installée | Moyenne (attribution à confirmer par `heap`/Allocations) |
| C9 | **Le helper menu duplique la barre de menus de l'app principale** et lance **son propre** `macmon`. Si les deux tournent : deux icônes et deux flux `macmon`. `install.sh` installe les deux | `MoraxCockpitApp.swift:39-49` (commentaire qui rend le helper redondant) ; `MoraxCockpitMenuApp.swift:8-16` ; `install.sh:29-30,57` ; runtime : `87395 macmon` enfant de `MoraxCockpitMenu` | CPU et RAM doublés | Haute (code) / contexte d'usage à confirmer |
| C10 | **Le Mini Cockpit en mode compact demande autant qu'en mode détaillé**, y compris `.process` (`ps` toutes les 5 s + IORegistry), avec en plus une boucle MainActor à 1 Hz qui ne suit pas la cadence de 1,5 s du flux système | `MiniCockpitStateEngine.swift:401-434` | Coût du HUD compact supérieur au nécessaire | Haute (code) |
| C11 | **Permissions revérifiées de façon synchrone à chaque activation de l'app.** Les sondes fichiers (ouverture de `TCC.db`, `contentsOfDirectory`) tournent sur main, et `permissions` est réassigné sans comparaison, ce qui invalide les observateurs à chaque retour au premier plan | `PermissionsService.swift:100-127,194-221` | Petit accroc à chaque activation | Moyenne |
| C12 | **Code mort ou trompeur.** Flux `.metaMuse` jamais acquis. Consommateur `TelemetryConsumer.usage` inutilisé. `UpdateService` simulé qui renvoie toujours « à jour ». Handler `scenePhase` vide (`MoraxCockpitApp.swift:33-37`). `operations.log` sans rotation. Cache `~/Library/Caches/MoraxCockpit` orphelin | `TelemetryCoordinator.swift:80,185` ; `UpdateService.swift:97-117` ; `OperationLog.swift:23-38` | Maintenance, fausse impression de fonctionnalité | Haute |

**Déjà traité par les passes précédentes, vérifié dans le code et non re-signalé :**
- Arrêt des flux après un délai de grâce (`TelemetryCoordinator.swift:51-60`).
- Un seul onglet monté (commit `53b4a29`).
- Restauration de Storage Map hors main (`StorageMapStateService.swift:129-153`).
- Caches de scan avec TTL, sans re-scan en boucle (`CachedScanStore.swift:25-63` et chaque `load*(force:false)`).
- `nettop` en one-shot, exclu du Mini Cockpit.
