# PERFORMANCE_AUDIT — Morax Garage

> Audit système 2026-09, branche `audit/system-audit-2026-09`, commit de référence `9eee9a7` (+ `6fe676e`). Lecture seule : aucun code modifié.
> Périmètre de ce fichier : **CPU**, **démarrage**, **réactivité UI/UX**, **architecture**, plus la synthèse priorisée de toutes les dimensions (12). Fichiers compagnons : `MEMORY_AUDIT.md`, `GPU_AUDIT.md`, `ENERGY_AUDIT.md`. Référence chiffrée : `BASELINE_V0.md`. Cartographie : `ARCHITECTURE_MAP.md`.
>
> **Statut** : vagues 1 et 2 implémentées ; voir `IMPLEMENTATION_LOG.md`, `FINAL_BENCHMARK.md` et `REMAINING_ISSUES.md`.

## Méthode et limites

- Chaque dimension a été auditée puis relue par un relecteur contradictoire. La sévérité retenue est celle de la revue (`adjusted_severity`) quand elle existe. Aucun constat n'a été réfuté. AIO-7 (recommandation de routage de modèles) a été ramené à « sans sévérité » : il n'est pas repris.
- Constat déjà corrigé : DEP-1 est **partiellement corrigé** (`Package.resolved` est suivi depuis `6fe676e` ; la contrainte `from: "1.0.7"` reste, `Package.swift:15`).
- Les coûts sont **déduits du code**, pas profilés. La baseline V0 (18,6 % CPU Dashboard, 138 Mo au lancement, 262 Mo dont 192 Mo `Malloc Small` dirty sur l'app installée) a été prise sous load average 15-50 : toute comparaison doit se faire dans des conditions de charge équivalentes (`scripts/bench/bench_runtime.sh`).
- Échelle : P0 = bloquant / perte de données certaine ; P1 = viole une règle produit (CPU/RAM bas, onglets instantanés, cache jamais re-scanné) ou risque de données ; P2 = coût ou défaut réel, gain modéré ; P3 = hygiène, gain marginal ou non mesuré.

## Synthèse priorisée

Aucun P0. Les doublons entre dimensions sont fusionnés sous un identifiant `Sxx` ; la sévérité retenue est la plus haute après revue. Colonne « Sources » : identifiants d'origine (sévérité revue entre parenthèses si différente). « Revue » = constat ajouté par le relecteur.

| ID | Sév. | Constat | Sources | Preuve principale | Effort | Risque |
|---|---|---|---|---|---|---|
| S01 | **P1** | Historique télémétrie (4,3 Mo JSON) décodé en synchrone au 1er accès puis ré-encodé et réécrit en entier sur le MainActor ~2×/min ; compaction bloquée (7 124 enregistrements `sampleCount=2` gelés) ; ~6-12 Go/jour d'écritures SSD | UIUX-1, STARTUP-2, ENE-4, CPU-3 (P2), MEM-4 (P2), ARCH-10 (P3) | `TelemetryHistoryStore.swift:168-178`, `:209-215`, `:225` ; `DiagnosticService.swift:21-27`, `:41-67` | M | moyen |
| S02 | **P1** | `ps` + parcours IORegistry synchrones sur le main thread (init, `startMonitoring`, chaque retour au Dashboard après 5 s) ; jusqu'à 3 `ps` au lancement car `TelemetryCoordinator.init` instancie les 7 feeds | STARTUP-1, GPU-3, CPU-4 (P2), ENE-9 (P2), AIO-3 (P2), REL-7 (P3), revue STARTUP | `ProcessResourceService.swift:233-243`, `:275-279`, `:347-363` ; `TelemetryCoordinator.swift:74-82` | S | faible |
| S03 | **P1** | Le label barre de menus (CPU activé par défaut) maintient `macmon pipe -i 1500` 24/7 alors que CPU/RAM/swap sont disponibles nativement | GPU-1, ENE-3, revue CPU | `MoraxMenuBarView.swift:133-143` ; `AppSettings.swift:334-337` ; `SystemMetricsService.swift:324`, `:543-547` | M | moyen |
| S04 | **P1** | Télémétrie Dashboard jamais suspendue quand la fenêtre est minimisée, masquée ou occultée (gate `scenePhase` retiré en `778ed13`) | ENE-1 | `RootView.swift:327` ; `MoraxCockpitApp.swift:33-37` | S | faible |
| S05 | **P1** | Ouvrir Sync Photos fait un `fileExists` sur le montage SMB du NAS sur le main thread ; montage figé = beachball | UIUX-2 | `PhotoSyncStateService.swift:129-131`, `:188-191` ; `PhotoSyncCopyPlan.swift:54-61` | S | faible |
| S06 | **P1** | Empreinte PhotoSync tronquée silencieusement sur erreur de lecture / démontage → faux « synchronisé » et « SSD libérable » | REL-1 | `PhotoSyncScanner.swift:105-107`, `:117` | S | faible |
| S07 | **P1** | `executeTrash` (suppression réelle) non testé, singletons en dur, éléments en échec retirés de la liste et du cache | TST-1 | `CleanupStateService.swift:568-634` | M | faible |
| S08 | P2 | Deux propriétaires du consumer `dashboard` (RootView et DashboardView) avec des feeds différents ; le dernier appel gagne | ARCH-4, TST-8, AIO-2, CPU-10 (P3), STARTUP-5 (P3), ENE-11 (P3) | `RootView.swift:281-289` ; `DashboardView.swift:132-140` ; `TelemetryCoordinator.swift:98-107` | S | faible |
| S09 | P2 | Higgsfield / Usage / OpenAI rafraîchis à chaque redémarrage de feed sans contrôle de fraîcheur ; snapshot Higgsfield non persisté | CPU-5, STARTUP-6, AIO-1, ENE-8 (P3) | `HiggsfieldCreditService.swift:67-83` ; `UsageQuotaService.swift:79-83` ; `OpenAICostsService.swift:54-58` | S | faible |
| S10 | P2 | Mini Cockpit : poll 1 Hz d'une source à 1,5 s, sparkline poussée sans détection de changement, feeds identiques compact/étendu, aucune pause sur occlusion | GPU-7, ENE-5, CPU-9 (P3), revue ARCH | `MiniCockpitStateEngine.swift:358-389`, `:399-432` | S | faible |
| S11 | P2 | Jauges : spring relancé sur 6 cadrans à chaque échantillon, arc non animable (pas d'`animatableData`), blur + ombres | CPU-1, GPU-4 | `AutomotiveGauge.swift:197`, `:214`, `:225-227`, `:538-551` | S | faible |
| S12 | P2 | `currentSnapshot` non quantifié republié à chaque échantillon (Dashboard + label invalidés toutes les 1,5 s), décodage macmon sur le main, cache `BalancedGrid` réinitialisé, `NumberFormatter` par appel | CPU-2, GPU-2, CPU-8 (P3), revue GPU | `SystemMetricsService.swift:317-322`, `:538-566`, `:735-738` ; `BalancedGrid.swift:29-31` ; `DashboardView.swift:553-560` | M | faible |
| S13 | P2 | Aucune gestion veille / verrouillage / écran éteint : macmon et polling tournent la nuit | ENE-2 | `grep screensDidSleep\|willSleep` vide ; `MoraxMenuBarView.swift:133-143` | S | faible |
| S14 | P2 | Sonde permissions exécutée 2-3× au lancement puis à chaque activation, sur le main (listing Downloads/Desktop/Documents) | STARTUP-3, UIUX-10 (P3) | `PermissionsService.swift:97-127` ; `MoraxCockpitApp.swift:68` | S | faible |
| S15 | P2 | Cache Cleanup : plist entier relu/réécrit par scanner, union `all` persistée en double, décodage synchrone sur le main au 1er accès, verrou global partagé par tous les stores | ARCH-2, STARTUP-11 (P3), UIUX-5 (P3) | `CleanupStateService.swift:107-165`, `:392-424` ; `CachedScanStore.swift:11`, `:180-189` | M | moyen |
| S16 | P2 | Carte cache du Dashboard et onglet Cleanup exécutent les mêmes scanners dans deux pipelines aux caches séparés | ARCH-3 | `CacheTelemetryService.swift:227-292` ; `CleanupStateService.swift:535-557` | M | moyen |
| S17 | P2 | Le helper `MoraxCockpitMenu` duplique menu bar + HUD + pile télémétrie, sans exclusion mutuelle (installé dans `/Applications`) | ARCH-7, ENE-10 (P3), DEP-5 (P3) | `MoraxCockpitMenuApp.swift:9-31` ; `scripts/build_app.sh:158-195` | M | moyen |
| S18 | P2 | `calculateSize` sans `autoreleasepool`, task group non borné, dossier `Google` non exclu → pic transitoire, candidat au `Malloc Small` dirty | MEM-1, revue MEM (AppsService) | `TrashService.swift:180-197` ; `SystemCacheScanner.swift:72-105` | S | faible |
| S19 | P2 | Arbre Storage Map (80k nœuds, `url` + `path` + UUID par nœud) résident à vie après la 1re visite | MEM-2 | `StorageMapStateService.swift:10`, `:44` ; `StorageNode.swift:245-291` | M | moyen |
| S20 | P2 | Treemap : layout recalculé dans le `body` à chaque invalidation ; Canvas de base redessiné à chaque mouvement de souris | GPU-8, UIUX-4 (P3) | `StorageMapView.swift:473-495` ; `TreemapCanvasView.swift:40-107` | M | faible |
| S21 | P2 | Liste Cleanup : `ForEach` sur tous les items par (tier × catégorie) ré-évalué à chaque case cochée | UIUX-3 | `CleanupResultsView.swift:131-163` ; `CleanupModalsAndSheets.swift:168` | M | moyen |
| S22 | P2 | « Ouvrir Morax Garage » depuis le Mini Cockpit inopérant une fois la fenêtre fermée ; callback écrasé par `{}` depuis Réglages ; risque de fenêtres principales dupliquées | UIUX-7, revue UIUX ×2 | `MoraxCockpitApp.swift:19-24`, `:76-104` ; `GeneralSettingsView.swift:62-65` | S | faible |
| S23 | P2 | Onglet revisité = nouveau scan concurrent (Audit/Apps/Environment) : pas de garde `isScanning`, `cancel()` sans effet | revue UIUX | `AuditStateService.swift:42-66` ; `AppsStateService.swift:41-67` ; `EnvironmentStateService.swift:40-65` | S | faible |
| S24 | P2 | `CleanupStateService` écrit via `.shared` au lieu de `self` (48 sites) ; les tests mutent l'environnement réel (`~/.Trash`, cache Application Support) | ARCH-1, TST-2 | `CleanupStateService.swift:371-627` ; `TabMemoryStateServicesTests.swift:158-180` | S | faible |
| S25 | P2 | Calcul de taille dupliqué, règles divergentes (fichiers cachés ignorés, taille logique vs allouée), non annulable | ARCH-9 | `TrashService.swift:165-198` ; `AIModelScanner.swift:188-208` | S | moyen |
| S26 | P2 | `ProcessRunner` : pipes lus après la sortie (blocage > 64 Ko), pas d'escalade SIGKILL, une `Task` par chunk (réordonnancement) | REL-2, REL-3 (P3), DEP-9 (P3) | `ProcessRunner.swift:70-80`, `:140-143` | M | faible |
| S27 | P2 | Historique effacé après un échec de décodage ; écrit sans synchronisation par deux processus | REL-6 | `TelemetryHistoryStore.swift:159-173` | M | faible |
| S28 | P2 | App installée signée ad hoc sans hardened runtime alors qu'elle détient Full Disk Access | SEC-1 | `scripts/build_app.sh:22`, `:231` | S | faible |
| S29 | P2 | Build non reproductible — **partiellement corrigé** (`Package.resolved` suivi, `6fe676e`) ; contrainte SwiftTerm `from: "1.0.7"` | DEP-1 | `Package.swift:15` | S | faible |
| S30 | P2 | Shaders Metal de SwiftTerm imposent le Metal toolchain à tout build, `swift test` compris | DEP-2 | `.build/checkouts/SwiftTerm/Package.swift:88-90` | M | moyen |
| S31 | P2 | Storage Map relance un scan disque complet à chaque visite après un 1er scan annulé/échoué, sans test | TST-3 | `StorageMapView.swift:102-114` | S | faible |
| S32 | P2 | Temps XCTest dominé par des `sleep` fixes et des parcours du vrai FS (~30 s GaugeFreeze) | TST-4 | `GaugeFreezeAuditTests.swift:24-120` | M | faible |
| S33 | P2 | Pipeline de copie PhotoSync (file, annulation, vérification) non testé | TST-7 | `PhotoSyncStateService.swift:281-349` | M | faible |
| S34 | P3 | Fonds translucides empilés (`CleanMyMacBackground` ×23, 2-3 backdrops behind-window sous des dégradés à 84-92 %) | CPU-7, GPU-5 | `RootView.swift:258`, `:608-615` ; `MoraxTheme.swift:58-120` | S | faible |
| S35 | P3 | Churn de processus (`nettop` /3,5 s, `ps` /5 s) et 3 `Process()` hors `ProcessRunner` (sans timeout ni registre) | CPU-6, ARCH-8, DEP-8 | `NetworkMetricsService.swift:139`, `:267-282` ; `ClaudeCodeScanner.swift:24-41` | M | moyen |
| S36 | P3 | Capacité de tous les volumes (NAS SMB inclus) interrogée sur le main, TTL 30 s | STARTUP-4, revue GPU | `SystemMetricsService.swift:392-397`, `:661`, `:740-782` | S | faible |
| S37 | P3 | Mascotte PNG 1024×1024 relue et décodée à chaque `body` ; PNG dupliqué, JPG inutilisé | STARTUP-10, MEM-7 | `MoraxMascotView.swift:13-15`, `:41-51` | S | faible |
| S38 | P3 | Snapshot CacheTelemetry (412 Ko) dans UserDefaults ; `collectSnapshot` isolé au main | STARTUP-8, MEM-5, revue ENE | `CacheTelemetryService.swift:128-189`, `:229`, `:274-294` | S | faible |
| S39 | P3 | Lectures Keychain synchrones sur le MainActor à chaque démarrage de feed et poll | STARTUP-7 | `KeychainSecret.swift:18-26` ; `UsageQuotaService.swift:51`, `:88` | S | faible |
| S40 | P3 | 2-3 appels IPC `SMAppService` redondants + double `activate` au lancement | STARTUP-9 | `AppSettings.swift:381`, `:390-409` | S | faible |
| S41 | P3 | Snapshot Storage Map : encodage `url` + `path`, pics transitoires à l'encode/décode | MEM-3 | `StorageNode.swift:560-584` ; `StorageMapStateService.swift:112`, `:190-218` | M | faible |
| S42 | P3 | `Bundle(url:)` gardés à vie par Foundation pour les noms d'apps | MEM-6 | `ProcessResourceService.swift:95` ; `AppsService.swift:92` | S | faible |
| S43 | P3 | Terminal intégré et shell `-l` gardés à vie, sans délégué de fin de processus | MEM-8, REL-10, DEP-7 | `TerminalView.swift:93-127` | S | faible |
| S44 | P3 | HUD mode clair : `.thinMaterial` behind-window + opacité de groupe 0,94 | GPU-6 | `MiniCockpitLiquidGlass.swift:139-153` ; `MiniCockpitHUDView.swift:94` | S | faible |
| S45 | P3 | Radar de scan Storage Map : 2 `repeatForever` + ombre, ignore Reduce Motion | GPU-9 | `StorageMapView.swift:1029-1086` | S | faible |
| S46 | P3 | ~30 ombres décoratives sur des éléments rafraîchis | GPU-10 | `MoraxTheme.swift:229-236` ; `TopAppsTelemetryCards.swift:152` | S | faible |
| S47 | P3 | Aucune tolérance de timer ; heartbeat 4 s même macmon sain | ENE-6 | `SystemMetricsService.swift:400-415` | S | faible |
| S48 | P3 | Boucles d'échantillonnage et scan quotidien en QoS `.userInitiated` | ENE-7 | `SystemMetricsService.swift:421` ; `CacheTelemetryService.swift:177` | S | faible |
| S49 | P3 | Code mort : `MetaMuseService` (~400 lignes), `MetricPoint`, `CleanupSnapshot`, handler `scenePhase` vide | ARCH-5, AIO-4 | `TelemetryCoordinator.swift:16`, `:80` ; `MoraxCockpitApp.swift:32-36` | S | faible |
| S50 | P3 | Réglages sans effet et clés `@AppStorage` en littéraux dupliqués | ARCH-6 | `GeneralSettingsView.swift:133-136`, `:413`, `:435` ; `DashboardView.swift:7-10` | S | faible |
| S51 | P3 | 4 fichiers > 800 lignes avec logique métier et I/O dans les vues | ARCH-11 | `DashboardView.swift` (1 462 l.), `GeneralSettingsView.swift` (1 119 l.) | L | faible |
| S52 | P3 | Services d'état copiés-collés (course sur résultat annulé) ; `DateFormatter()` alloué par ligne | ARCH-12 | `AuditStateService.swift:52-64` ; `FileItem.swift:281-285` | S | faible |
| S53 | P3 | Barre latérale en `Button` : pas de navigation clavier, pas de trait « sélectionné », pas de ⌘, ni ⌘1-9 | UIUX-6 | `RootView.swift:162-185` ; `MoraxCockpitApp.swift:17-31` | M | moyen |
| S54 | P3 | Connexion Higgsfield : `NSAppleScript` synchrone sur le main, erreur ignorée, presse-papiers écrasé | UIUX-8 | `HiggsfieldCreditCard.swift:444-464` | S | faible |
| S55 | P3 | Treemap et boutons icône invisibles pour VoiceOver ; polices 5-9,5 pt | UIUX-9 | `TreemapCanvasView.swift:61-91` ; `AIModelsView.swift:155-188` | M | faible |
| S56 | P3 | États vides trompeurs (bouclier vert sur échec/filtre) ; état de vue perdu à chaque changement d'onglet | UIUX-11 | `AuditView.swift:92-93` ; `RootView.swift:324-350` | S | faible |
| S57 | P3 | UI mi-français mi-anglais ; raccourcis empilés sur un même bouton dans Cleanup | UIUX-12 | `RootView.swift:4-17` ; `CleanupView.swift:150-152`, `:229-233` | S | faible |
| S58 | P3 | macmon bloqué jamais tué ni relancé | REL-4 | `SystemMetricsService.swift:399-415` | S | faible |
| S59 | P3 | Copies rsync sans watchdog ; disparition NAS/SSD bloque toute la file (reverify compris) | REL-5, revue REL | `PhotoSyncStateService.swift:281-302`, `:341-349` | M | moyen |
| S60 | P3 | Écritures de cache détachées non ordonnées ; erreurs de persistance avalées | REL-8 | `CachedScanStore.swift:90-97`, `:181-188` | S | faible |
| S61 | P3 | Le poll Higgsfield change le workspace CLI de l'utilisateur, jusqu'à 3 processus par poll | REL-9, AIO-9 | `HiggsfieldCreditService.swift:141-155`, `:256-289` | S | faible |
| S62 | P3 | Résolution d'outils : dossier inscriptible non peuplé prioritaire, chemins incohérents entre écrans | SEC-2, DEP-10 | `ToolRegistry.swift:41-77` ; `GeneralSettingsView.swift:1087-1109` | S | faible |
| S63 | P3 | Terminal intégré = shell de login avec le Full Disk Access de l'app | SEC-3 | `TerminalView.swift:117-124` | M | moyen |
| S64 | P3 | Bouton « Quick Look Preview » ouvre/lance le fichier | SEC-4 | `StorageMapInspectorView.swift:210-213` | S | faible |
| S65 | P3 | Garde anti-symlink `scanRoot` de SafetyGate jamais utilisée en production | SEC-5 | `SafetyGate.swift:249-258` | M | faible |
| S66 | P3 | Clé interne envoyée à une URL éditable sans contrôle https | SEC-6 | `AppSettings.swift:255-257` | S | faible |
| S67 | P3 | Keychain : attributs legacy ; secrets relus à chaque init de vue Réglages | SEC-7 | `KeychainSecret.swift:15` | S | faible |
| S68 | P3 | Chemins clients et identifiants en `.public` dans les logs ; journalisation fragmentée (2 sous-systèmes, pas de signposts) | SEC-8, AIO-8 | `PhotoSyncScanner.swift:106` ; `TelemetryLogger.swift:5-7` | S | faible |
| S69 | P3 | SwiftTerm 1.18.0 : crash sur DECRQSS non-ASCII (corrigé en 1.19.0) | DEP-3 | `SwiftTerm/Terminal.swift:1118` | S | moyen |
| S70 | P3 | `brew outdated` déclenche l'auto-update Homebrew, résultat non persisté | DEP-4 | `BrewService.swift:75-79` | S | faible |
| S71 | P3 | Binaires release non strippés (37,3 Mo → 15,6 Mo) | DEP-6 | `dist/Morax Garage.app/Contents/MacOS/MoraxCockpit` | S | faible |
| S72 | P3 | Tranche x86_64 compilée à chaque build alors que la télémétrie exige Apple Silicon | DEP-11 | `scripts/build_app.sh:11`, `:28-41` | S | faible |
| S73 | P3 | Tests de grace period/persistance dépendants de marges de `sleep` | TST-5 | `TelemetryCoordinator.swift:154-155` | M | faible |
| S74 | P3 | Chemin credentials sans test ; clé usage stockée non trimée | TST-6 | `UsageQuotaCredentials.swift` | S | faible |
| S75 | P3 | Singletons partagés qui fuient entre tests (feeds réels laissés actifs) | TST-9 | `GaugeFreezeAuditTests.swift:62-101` ; `MiniCockpitTests.swift:608-626` | S | faible |
| S76 | P3 | `testCancelledScanNeverPublishesItsTree` peut passer à vide ; `AIModelsStateService` sans test | TST-10 | `StorageMapScanRestartTests.swift:57-71` | S | faible |
| S77 | P3 | Pas d'observation des runtimes IA locaux en cours (process, modèles chargés, VRAM) | AIO-5 | `AIModelScanner.swift:17-23` | M | faible |
| S78 | P3 | Mémoire GPU unifiée et empreinte réelle des runners LLM non mesurées | AIO-6 | `NativeGpuSampler.swift:29-62` | S | faible |
| S79 | P3 | Le « backoff » de `UsageQuotaService` accélère le polling après un échec (10-160 s < 300 s) | revue AIO | `UsageQuotaService.swift:62-64` | S | faible |
| S80 | P3 | `findings` observable réassigné à chaque tick même inchangé → invalidations à cadence télémétrie | revue ARCH | `DiagnosticService.swift:70-72`, `:100-107` | S | faible |

Lecture transversale : S01, S02, S03, S04 et S08 concentrent l'essentiel du coût permanent et des violations des règles produit (CPU/RAM bas, onglets instantanés, cache jamais re-scanné). S01 et S02 sont des correctifs localisés à faible risque ; S03 demande de scinder le feed `.system`.

---

## 1. CPU

Hypothèse de coût du Dashboard (18,6 % au premier plan, non profilée) : invalidation de tout le binnacle toutes les 1,5 s (S12), animations spring (S11), puis travail de fond (S02, S35, S01). Test à zéro code recommandé en premier : activer Réduire les animations et comparer `top -pid <pid> -s 1 -l 60`.

### CPU-1 — Spring relancé sur les 6 cadrans à chaque échantillon · **P2** (auditeur P1) · S11
- **Preuve** : `AutomotiveGauge.swift:214`, `:227` (`.spring(response: 0.45…)` sur `fraction`) ; `CleanGaugeArcShape` sans `animatableData` (`:539-551`) : l'arc saute, seul le point interpole ; glow `.blur(radius: 4)` `:197` ; échantillon toutes les 1,5 s (`SystemMetricsService.swift:324`).
- **Impact** : travail d'animation ~65 % du temps sur 6 jauges ; défaut visuel (point détaché de l'arc). Part réelle du CPU non démontrée.
- **Effort / risque** : S / faible.
- **Fichiers** : `Sources/MoraxCockpit/Features/Dashboard/AutomotiveGauge.swift`.
- **Correctif** : supprimer le spring ou animer seulement si |Δ| > 2 % en `easeOut(0.25)` ; sinon rendre l'arc animable.
- **Test de validation** : A/B Réduire les animations ON/OFF (`top` 60 s), puis Instruments SwiftUI + Core Animation (commits/s) avant/après.

### CPU-2 — Snapshot `@Observable` unique qui invalide binnacle + en-tête toutes les 1,5 s · **P2** (auditeur P1) · S12
- **Preuve** : `SystemMetricsService.swift:317-322` (`currentSnapshot` non Equatable, horodaté) ; `DashboardView.swift:446-452`, `:174-181` lisent tout le snapshot ; `BalancedGrid.swift:29-31` vide le cache à chaque mise à jour ; `NumberFormatter` alloué dans `formatFrequency` (`DashboardView.swift:553-560`).
- **Impact** : une passe body + layout (~200 vues) toutes les 1,5 s même quand l'affichage ne change pas ; quelques ms, pas du travail par frame.
- **Effort / risque** : M / faible.
- **Fichiers** : `DashboardView.swift`, `SystemMetricsService.swift`, `Core/DesignSystem/BalancedGrid.swift`.
- **Correctif** : gains rapides d'abord (formatter `static`, cache `BalancedGrid` conservé à largeur constante) ; ensuite modèle d'affichage quantifié par cadran.
- **Test de validation** : Instruments SwiftUI « View Body » sur `PanoramicInstrumentBinnacle`/`AutomotiveGauge` pendant 60 s à charge stable.

### CPU-3 — Historique 4,3 Mo réécrit sur le MainActor · **P2** (auditeur P1) · S01
- **Preuve** : `TelemetryHistoryStore.swift:168-178` (load → append → prune → write), `:209-213` (encode + écriture atomique du fichier entier), intervalle 60 s (`:127`) ; appelé depuis `DiagnosticService.swift:41-67` (@MainActor). Fichier : 4 335 652 octets.
- **Impact** : 2 encodages de ~4 Mo/min sur le main (à-coups périodiques) ; ~12 Go/jour d'écritures. `load()` est servi depuis un cache mémoire (pas de re-décodage).
- **Effort / risque** : M / moyen.
- **Fichiers** : `Diagnostics/TelemetryHistoryStore.swift`, `Diagnostics/DiagnosticService.swift`.
- **Correctif** : voir S01 (acteur d'écriture, append-only, flush groupé).
- **Test de validation** : `fs_usage -w -f filesys <pid> | grep telemetry-history` 5 min ; aucun frame `JSONEncoder` sur le main.

### CPU-4 — Retour au Dashboard : `ps` + IORegistry synchrones (deux fois) · **P2** · S02
- **Preuve** : `ProcessResourceService.swift:239-243`, `:275-279`, `:347-358` ; la boucle détachée `:245-256` refait immédiatement le même travail ; arrêt du feed 5 s après le départ de l'onglet.
- **Impact** : le changement d'onglet vers le Dashboard attend `ps` (~700 processus) + parcours registre ; travail doublé.
- **Effort / risque** : S / faible.
- **Fichiers** : `Metrics/ProcessResourceService.swift`.
- **Correctif** : retirer `sampleImmediate` de `init` et `startMonitoring` ; afficher le dernier snapshot.
- **Test de validation** : Time Profiler sur Réglages → Dashboard après > 5 s : 0 ms main dans `executePs`/`IORegistryEntryCreateCFProperties`.

### CPU-5 — Revisite du Dashboard = CLI Higgsfield + HTTP relancés · **P2** · S09
- **Preuve** : `HiggsfieldCreditService.swift:67-73`, `:105-160` ; `UsageQuotaService.swift:49-57`, `:80-83` ; `OpenAICostsService.swift:54-58` ; acquisition `DashboardView.swift:134-139`.
- **Impact** : un processus CLI + 2 requêtes HTTP à chaque retour > 5 s ; viole « servi depuis le cache ».
- **Effort / risque** : S / faible.
- **Fichiers** : les trois services ci-dessus.
- **Correctif** : ne rafraîchir que si `now - lastSuccess >= pollingInterval`, sinon dormir le reste.
- **Test de validation** : test unitaire à horloge injectée (2 `startMonitoring` en < 300 s → 1 appel) ; 10 changements d'onglet → 1 lancement `higgsfield` / 5 min.

### CPU-6 — Churn de processus enfants Dashboard visible · **P3** (auditeur P2) · S35
- **Preuve** : `NetworkMetricsService.swift:139`, `:200`, `:267-271` (`nettop` / 3,5 s) ; `ProcessResourceService.swift:222`, `:347-358` (`ps` / 5 s) ; `GpuProcessSampler.swift:29-80`.
- **Impact** : ~29 fork/exec/min, estimé ~1 % d'un cœur, en partie hors du CPU de l'app.
- **Effort / risque** : M / moyen.
- **Fichiers** : `NetworkMetricsService.swift`, `ProcessResourceService.swift`, `GpuProcessSampler.swift`.
- **Correctif** : à mesurer d'abord ; ensuite `proc_pid_rusage`, `nettop` à 10-15 s, GPU par process à 10 s.
- **Test de validation** : CPU app + enfants sur 60 s (`powermetrics --samplers tasks`) avant/après.

### CPU-7 — Double fond translucide sur fenêtre non opaque · **P3** (auditeur P2) · S34
- **Preuve** : `RootView.swift:258` + `DashboardView.swift:116` (23 sites) ; `MoraxTheme.swift:58-120` ; `MoraxCockpitApp.swift:106-110`.
- **Impact** : coût WindowServer/GPU pendant les animations, pas le CPU de l'app.
- **Effort / risque** : S / faible.
- **Fichiers** : `RootView.swift`, `DashboardView.swift`, `MoraxTheme.swift`.
- **Correctif** : un seul `CleanMyMacBackground` au niveau `RootView`.
- **Test de validation** : CPU WindowServer Dashboard au premier plan avant/après (CPU-1 inchangé).

### CPU-8 — Décodage macmon et construction du snapshot sur le main · **P3** · S12
- **Preuve** : `SystemMetricsService.swift:538-566` (isolé MainActor) ; `ProcessRunner.swift:70-80` (une `Task` par chunk).
- **Impact** : < 1 ms par tick ; risque réel de réordonnancement des lignes (voir S26).
- **Effort / risque** : S / faible.
- **Fichiers** : `SystemMetricsService.swift`, `Core/ProcessRunner.swift`.
- **Correctif** : consommation `nonisolated`, saut au MainActor pour publier seulement.
- **Test de validation** : Time Profiler : aucun `JSONDecoder`/`MacmonSample` sur le main.

### CPU-9 — Mini Cockpit : feeds process/usage en compact, poll 1 Hz · **P3** · S10
- **Preuve** : `MiniCockpitStateEngine.swift:399-415` (branches identiques), `:421-432` (1 s), `:365` (comparaison incluant `timestamp`, `ProcessResourceService.swift:48-56`).
- **Impact** : `ps` + IORegistry /5 s et HTTP pour des données non affichées en compact.
- **Effort / risque** : S / faible.
- **Fichiers** : `MiniCockpit/MiniCockpitStateEngine.swift`.
- **Correctif** : compact = `[.system]`, standard + `.process`, étendu + usage ; `withObservationTracking`.
- **Test de validation** : test « compact n'acquiert que `.system` » ; CPU HUD seul vs pass 2 (2,00 %).

### CPU-10 — Consumer `dashboard` acquis à deux endroits · **P3** · S08
- **Preuve** : `RootView.swift:279-289` vs `DashboardView.swift:133-140` ; `TelemetryCoordinator.swift:98-104` remplace la demande.
- **Impact** : ordre-dépendant ; cartes usage/Higgsfield possiblement figées puis churn de refresh.
- **Effort / risque** : S / faible.
- **Fichiers** : `RootView.swift`, `DashboardView.swift`.
- **Correctif** : un seul propriétaire ou IDs distincts.
- **Test de validation** : logs `TelemetryLogger.lifecycle` : aucun « scheduling stop » usage/higgsfield Dashboard affiché.

**Ajouts de la revue (CPU)** : (a) `tabView(for:)` est un `switch` : chaque changement d'onglet détruit et reconstruit toute la hiérarchie (`RootView.swift:324-345`) et relance les acquisitions — amplificateur de S02/S09/S23 ; (b) macmon + ingest à 1,5 s toute la vie de l'app à cause du label (S03).

---

## 2. Démarrage

Lancement chaud 1,3-2,1 s, froid 14,3 s (probablement évaluation syspolicyd du binaire neuf, non vérifié). Avant la première frame : `ps` synchrone, décodage 4,3 Mo, sondes permissions, capacité volumes, blob UserDefaults, IPC SMAppService/Keychain. Amplificateur racine (revue) : `TelemetryCoordinator.init` instancie les 7 feeds, dont les `init` ont des effets de bord (`TelemetryCoordinator.swift:74-82`).

### STARTUP-1 — `ps` + IOKit synchrones au lancement et à chaque retour Dashboard · **P1** · S02
- **Preuve** : `ProcessResourceService.swift:217-218` (@MainActor), `:233-235` et `:242-243` appellent `sampleImmediate()` ; `:347-363` (`run` + `readDataToEndOfFile` + `waitUntilExit`) ; `GpuProcessSampler.swift:29-44`. Jusqu'à 3 `ps` au lancement dont 2 sur le main.
- **Impact** : main bloqué 50-300 ms estimés sous charge avant la 1re frame, puis à chaque retour au Dashboard ; viole « onglets instantanés ».
- **Effort / risque** : S / faible.
- **Fichiers** : `Metrics/ProcessResourceService.swift`, `Metrics/TelemetryCoordinator.swift`.
- **Correctif** : supprimer `sampleImmediate` ; premier échantillon par la boucle détachée ; contrôles du coordinateur paresseux.
- **Test de validation** : signpost sur `startMonitoring` < 1 ms main ; Hangs : aucun blocage > 50 ms sur Réglages → Dashboard après 6 s.

### STARTUP-2 — Décodage synchrone de l'historique 4,3 Mo pendant la 1re frame · **P1** · S01
- **Preuve** : `DiagnosticService.swift:21-27` (`history.load()` dans `init`) ; `TelemetryHistoryStore.swift:147-158` ; atteint dès `SystemMetricsService.init` (`:338-345`) via le label de la barre de menus, avant la fenêtre. 9 980 enregistrements système + 1 000 process.
- **Impact** : 50-150 ms de main estimés au lancement ; puis 2 réécritures complètes/min.
- **Effort / risque** : M / moyen.
- **Fichiers** : `DiagnosticService.swift`, `TelemetryHistoryStore.swift`.
- **Correctif** : `init` sans I/O ; décodage `Task.detached` ; persistance dans un acteur.
- **Test de validation** : signpost `DiagnosticService.init` < 1 ms ; test avec store espion : aucune lecture synchrone dans `init`.

### STARTUP-3 — Sonde permissions 2-3× au lancement puis à chaque activation · **P2** · S14
- **Preuve** : `PermissionsService.swift:97-108` (init + observer `didBecomeActive`) ; `MoraxCockpitApp.swift:68` (2e appel) ; `:59` + `AppSettings.swift:381` (activation → 3e) ; `contentsOfDirectory` Downloads/Desktop/Documents/Volumes (`:140-174`).
- **Impact** : listings sur le main dans `applicationDidFinishLaunching` ; latence iCloud/FileProvider ; répété à chaque ⌘-Tab.
- **Effort / risque** : S / faible.
- **Fichiers** : `Services/PermissionsService.swift`, `App/MoraxCockpitApp.swift`.
- **Correctif** : un seul appel, sondes détachées, `access(R_OK)` au lieu de listings, anti-rebond 30 s, assignation seulement si changement.
- **Test de validation** : compteur de log = 1 appel/lancement ; `fs_usage` : aucun `getdirentries` sur Documents/Desktop depuis le main.

### STARTUP-4 — Capacité de tous les volumes (NAS inclus) sur le main · **P3** (auditeur P2) · S36
- **Preuve** : `SystemMetricsService.swift:392-397`, `:740-782` (`volumeAvailableCapacityForImportantUsageKey`, volumes réseau non exclus, TTL 30 s `:336`), `:661`.
- **Impact** : quelques à dizaines de ms toutes les 30 s ; blocage long sur NAS endormi non démontré.
- **Effort / risque** : S / faible.
- **Fichiers** : `Metrics/SystemMetricsService.swift`.
- **Correctif** : hors main, exclure `volumeIsLocalKey == false`, seul le volume de démarrage pour les jauges.
- **Test de validation** : Time Profiler au lancement NAS monté : aucun `mountedVolumeURLs` sur le main.

### STARTUP-5 — Consumer `dashboard` : deux jeux de feeds concurrents · **P3** (auditeur P2) · S08
- **Preuve** : `RootView.swift:265-286` vs `DashboardView.swift:118-139` ; `TelemetryCoordinator.swift:96-106`.
- **Impact** : l'ordre habituel (onChange parent avant onAppear enfant) donne le sur-ensemble ; le mauvais ordre n'est pas prouvé. Défaut de conception.
- **Effort / risque** : S / faible.
- **Fichiers** : `RootView.swift`, `DashboardView.swift`.
- **Correctif** : propriétaire unique.
- **Test de validation** : `log stream` au lancement : une seule ligne « dashboard acquired » incluant usage/higgsfield, aucun stop usage dans les 10 s.

### STARTUP-6 — Feeds Higgsfield/Usage/OpenAI rafraîchis à chaque démarrage · **P2** · S09
- **Preuve** : `HiggsfieldCreditService.swift:41-42`, `:53-59` (rien restauré), `:67-83`, `:141-142` ; `UsageQuotaService.swift:57-60`, `:79-80`, `:157-161` ; `OpenAICostsService.swift:54-58`.
- **Impact** : à chaque lancement et revisite : processus + réseau + Keychain + re-rendu ; concurrence la 1re frame.
- **Effort / risque** : S / faible.
- **Fichiers** : les trois services.
- **Correctif** : contrôle de fraîcheur ; persister le snapshot Higgsfield comme `UsageQuotaService.restoreCache`.
- **Test de validation** : test horloge injectée ; Dashboard → Storage Map (10 s) → Dashboard : aucun nouveau processus `higgsfield`.

### STARTUP-7 — Lectures Keychain synchrones sur le MainActor · **P3** · S39
- **Preuve** : `KeychainSecret.swift:18-26` ; `UsageQuotaService.swift:23`, `:51`, `:88` ; `OpenAICostsService.swift:27`, `:50-55`, `:74`.
- **Impact** : ≥ 4 IPC securityd au démarrage du feed, quelques ms chacune ; lien avec le lancement froid de 14,3 s spéculatif.
- **Effort / risque** : S / faible.
- **Fichiers** : `UsageQuotaService.swift`, `OpenAICostsService.swift`, `Core/KeychainSecret.swift`.
- **Correctif** : lire une fois hors main, garder en mémoire, invalider à l'écriture depuis Réglages.
- **Test de validation** : Time Profiler au lancement : aucun `SecItemCopyMatching` sur le main.

### STARTUP-8 — Blob CacheTelemetry (410 Ko) décodé depuis UserDefaults au lancement · **P3** · S38
- **Preuve** : `CacheTelemetryService.swift:128`, `:136-143` ; `com.morax.garage.plist` = 414 385 octets ; `collectSnapshot` (`:229`) non `nonisolated` → `Task.detached` revient sur le main, boucle `calculateSize` `:274-294` sur le main.
- **Impact** : quelques à dizaines de ms au lancement ; chaque écriture de préférence réécrit 414 Ko.
- **Effort / risque** : S / faible.
- **Fichiers** : `Metrics/CacheTelemetryService.swift`.
- **Correctif** : `collectSnapshot` `nonisolated` ; fichier dans Application Support décodé hors main.
- **Test de validation** : plist < 10 Ko ; aucun énumérateur FileManager sur le main pendant un refresh forcé.

### STARTUP-9 — IPC `SMAppService` redondants au lancement · **P3** · S40
- **Preuve** : `MoraxCockpitApp.swift:57-59` ; `AppSettings.swift:130-134`, `:390-409` (assignation inconditionnelle → `didSet` → 2e IPC).
- **Impact** : quelques ms sur le chemin critique.
- **Effort / risque** : S / faible.
- **Fichiers** : `Core/AppSettings.swift`, `App/MoraxCockpitApp.swift`.
- **Correctif** : comparer avant d'assigner ; différer après la 1re fenêtre ; supprimer le `activate` en double.
- **Test de validation** : test avec fournisseur de statut injecté : pas de register/unregister si déjà activé.

### STARTUP-10 — Mascotte 1024×1024 relue à chaque `body` · **P3** · S37
- **Preuve** : `MoraxMascotView.swift:13-15`, `:41-51` ; PNG 1 325 523 o dupliqué dans deux `Resources` ; `MoraxMascot.jpg` (385 Ko) non référencé.
- **Impact** : lecture + décodage ~4 Mo RGBA sur le main à chaque re-rendu hôte ; ~1,7 Mo de bundle.
- **Effort / risque** : S / faible.
- **Fichiers** : `Core/DesignSystem/MoraxMascotView.swift`, les deux PNG, le JPG.
- **Correctif** : image réduite chargée une fois (`static let`) ; supprimer doublon et JPG.
- **Test de validation** : Allocations : une seule image mascotte sur plusieurs changements d'onglet ; bundle −1,7 Mo.

### STARTUP-11 — 1re ouverture de Cleanup : décodage synchrone de `cleanup_cache.plist` (600 Ko) · **P3** · S15
- **Preuve** : `CleanupStateService.swift:60-63`, `:107-119`, `:156-157` ; `CachedScanStore.swift:66-67`.
- **Impact** : dizaines de ms estimées au 1er passage sur Cleanup (pas au lancement).
- **Effort / risque** : S / faible.
- **Fichiers** : `Services/CleanupStateService.swift`, `Services/CachedScanStore.swift`.
- **Correctif** : modèle `StorageMapStateService.restoreCacheFromDisk` (`:93-140`).
- **Test de validation** : Hangs sur Dashboard → Cleanup à froid : aucun blocage > 30 ms.

**Ajouts de la revue (démarrage)** : `ingestProcesses` fait 5 scans de 1 000 enregistrements toutes les 5 s sur le main (`DiagnosticService.swift:58-66`) — mettre en cache les références 24 h (rattaché à S01). Hors dimension : 1 640 domaines de préférences `morax-history-tests-*` laissés par les tests.

---

## 3. Réactivité UI/UX

### UIUX-1 — Historique chargé, élagué, encodé et écrit sur le MainActor · **P1** · S01
- **Preuve** : `DiagnosticService.swift:4-5`, `:21-27`, `:41-60` ; `TelemetryHistoryStore.swift:168-177`, `:209-213` ; appels depuis `SystemMetricsService.swift:737` et `ProcessResourceService.swift:367`.
- **Impact** : 2 blocages de dizaines de ms par minute (frames perdues), y compris HUD ou barre de menus seuls ; croît avec la taille.
- **Effort / risque** : M / faible.
- **Fichiers** : `DiagnosticService.swift`, `TelemetryHistoryStore.swift`.
- **Correctif** : `actor TelemetryHistoryWriter` en fire-and-forget, tampon mémoire, décodage initial détaché.
- **Test de validation** : Time Profiler 3 min : aucun `JSONEncoder.encode`/`Data.write` sur le main ; Hangs : plus d'à-coup > 16 ms toutes les 60 s ; test avec writer espion.

### UIUX-2 — Sync Photos : stat du montage SMB sur le main · **P1** · S05
- **Preuve** : `PhotoSyncView.swift:39` ; `PhotoSyncStateService.swift:30`, `:129-131`, `:188-191` ; `PhotoSyncScanner.swift:88-90` ; `nasRoot` par défaut `/Volumes/Storage 2` (`PhotoSyncModels.swift:21`) ; `enqueueSync` → `plan.validate()` (`PhotoSyncCopyPlan.swift:54-61`), en boucle dans `enqueueAll` (`PhotoSyncView.swift:174-178`).
- **Impact** : cas normal bon marché ; montage SMB figé (veille, Wi-Fi) = beachball de plusieurs secondes, multiplié par « Tout synchroniser ».
- **Effort / risque** : S / faible.
- **Fichiers** : `PhotoSyncStateService.swift`, `PhotoSyncScanner.swift`, `PhotoSyncCopyPlan.swift`, `PhotoSyncView.swift`.
- **Correctif** : `refreshVolumeState` async détaché (le scan complet le fait déjà, `:147-148`) ; `validate()` dans la tâche du job.
- **Test de validation** : `nasRoot` vers un montage injoignable : l'onglet s'affiche immédiatement (Hangs) ; test avec `VolumeProbe` lent (2 s) : partie main de `scan(force:false)` < 50 ms.

### UIUX-3 — Liste Cleanup ré-évaluée tiers × catégories × items à chaque case · **P2** (auditeur P1) · S21
- **Preuve** : `CleanupResultsView.swift:131-148`, `:162-163` ; compteurs recalculés 4× (`:89`, `:112-118`, `CleanupStateService.swift:282-288`) ; toggle via binding (`CleanupModalsAndSheets.swift:168`) ; 1 186 items.
- **Impact** : O(sections × N) par clic, limité aux tiers dépliés (`:138`) ; lag non mesuré.
- **Effort / risque** : M / moyen (passer la sélection en `Set<ID>` touche le modèle et le flux corbeille).
- **Fichiers** : `CleanupResultsView.swift`, `CleanupStateService.swift`.
- **Correctif** : index groupé précalculé, compteurs incrémentaux, un item dans un seul `ForEach`.
- **Test de validation** : Instruments SwiftUI : temps main par toggle < 8 ms ; test « chaque item dans exactement une section ».

### UIUX-4 — Layout treemap recalculé dans le `body` · **P3** (auditeur P2) · S20
- **Preuve** : `StorageMapView.swift:473-487`, `:499-500`, `:818-847` ; `TreemapLayoutEngine.swift:56-85`.
- **Impact** : borné par `maxDepth=3` et le seuil de 3 px ; quelques ms par clic.
- **Effort / risque** : S / faible.
- **Fichiers** : `StorageMapView.swift`, `TreemapCanvasView.swift`.
- **Correctif** : mémoïsation clé (nœud actif, taille arrondie, profondeur).
- **Test de validation** : 20 clics sur tuiles : `computeLayout` appelé 0 fois après le premier.

### UIUX-5 — Décodage synchrone des caches au 1er usage, derrière un verrou global · **P3** (auditeur P2) · S15
- **Preuve** : `AppsStateService.swift:26`, `AuditStateService.swift:27`, `EnvironmentStateService.swift:25`, `AIModelsStateService.swift:36`, `PhotoSyncStateService.swift:63`, `CleanupStateService.swift:107-165` ; verrou `CachedScanStore.swift:11`, `:137-141`, `:183-189`.
- **Impact** : caches de 1 à 22 Ko sauf Cleanup (600 Ko) ; contention seulement pendant une écriture de scan « All ».
- **Effort / risque** : M / faible.
- **Fichiers** : `CachedScanStore.swift`, `CleanupStateService.swift`, `AppsStateService.swift`, `AuditStateService.swift`.
- **Correctif** : `restoreCacheFromDisk()` async par service ; verrou par fichier ; une écriture groupée en fin de scan « All ».
- **Test de validation** : scan « All » puis Apps et Audit immédiatement : aucune attente `NSLock` sur le main.

### UIUX-6 — Barre latérale sans clavier ni ⌘, · **P3** (auditeur P2) · S53
- **Preuve** : `RootView.swift:162-185`, `:376`, `:489` ; aucune scène `Settings` (`MoraxCockpitApp.swift:17-31`).
- **Impact** : pas de ↑/↓, pas de trait sélectionné VoiceOver, pas de ⌘1-9 ni ⌘,.
- **Effort / risque** : M / moyen (migration `List(selection:)` sur un style très personnalisé).
- **Fichiers** : `RootView.swift`, `MoraxCockpitApp.swift`.
- **Correctif** : d'abord ⌘, et ⌘1-9 (bon marché) ; migration `List` ensuite.
- **Test de validation** : ⌘, ouvre Réglages, ⌘2 ouvre Sync Photos ; Accessibility Inspector : trait « selected ».

### UIUX-7 — « Ouvrir la fenêtre » du Mini Cockpit mort une fois la fenêtre fermée · **P2** · S22
- **Preuve** : seul récepteur de `.moraxReopenMainWindow` dans `RootView` (`MoraxCockpitApp.swift:19-24`) ; l'app survit à la fermeture (`:85-88`) ; publications `:76-81`, `:101-103`, `DashboardView.swift:277-279`.
- **Impact** : bouton, menu contextuel et double-clic du HUD sans effet après ⌘W ; usage principal « vit dans la barre de menus ».
- **Effort / risque** : S / faible.
- **Fichiers** : `App/MoraxCockpitApp.swift`.
- **Correctif** : `WindowOpener` indépendant de la scène ; scène `Window(id:)` unique.
- **Test de validation** : ⌘W puis bouton HUD, puis clic Dock : la fenêtre réapparaît à chaque fois, sans doublon.

### UIUX-8 — Connexion Higgsfield : `NSAppleScript` synchrone · **P3** (auditeur P2) · S54
- **Preuve** : `HiggsfieldCreditCard.swift:444-464` (`errorDict` ignoré, succès affiché, presse-papiers écrasé).
- **Impact** : gel pendant l'invite TCC ; faux succès si refus.
- **Effort / risque** : S / faible.
- **Fichiers** : `Features/Dashboard/HiggsfieldCreditCard.swift`.
- **Correctif** : `ProcessRunner` ou terminal intégré ; vérifier `errorDict` ; ne pas toucher au presse-papiers.
- **Test de validation** : `tccutil reset AppleEvents`, clic : UI réactive et message d'erreur.

### UIUX-9 — Treemap et boutons icône invisibles pour VoiceOver · **P3** (auditeur P2) · S55
- **Preuve** : `TreemapCanvasView.swift:61-91` ; `AIModelsView.swift:155-161`, `:181-188` ; 42 polices de 5-8,x pt.
- **Impact** : Storage Map inexploitable au clavier/VoiceOver ; l'inspecteur offre un chemin liste.
- **Effort / risque** : M / faible.
- **Fichiers** : `TreemapCanvasView.swift`, `AIModelsView.swift`, `RootView.swift`.
- **Correctif** : label de la case modèle IA (1 ligne) ; enfants d'accessibilité treemap plus tard.
- **Test de validation** : VoiceOver sur AI Models : nom + état annoncés.

### UIUX-10 — Sonde permissions à chaque activation · **P3** · S14
- **Preuve** : `PermissionsService.swift:87-127` ; `isChecking` jamais visible ; 3e appel `PermissionsView.swift:65-67`.
- **Impact** : listings sur le main à chaque ⌘-Tab ; invalidations inutiles.
- **Effort / risque** : S / faible.
- **Fichiers** : `PermissionsService.swift`, `MoraxCockpitApp.swift`.
- **Correctif** : voir STARTUP-3.
- **Test de validation** : 10 cycles ⌘-Tab : aucun `contentsOfDirectory` sur le main ; compteur de body `FullDiskAccessObserver` stable.

### UIUX-11 — États vides trompeurs, état perdu au changement d'onglet · **P3** · S56
- **Preuve** : `AuditView.swift:92-93` ; `AuditStateService.swift:41-66`, `AppsStateService.swift:41-67` sans erreur ; `RootView.swift:324-350` ; `StorageMapView.swift:9-12`, `PhotoSyncView.swift:7-8`.
- **Impact** : « aucun élément » lu comme « système sain » ; sélection et filtres perdus.
- **Effort / risque** : S / faible.
- **Fichiers** : `AuditView.swift`, `AppsView.swift`, `RootView.swift`, `StorageMapView.swift`, `PhotoSyncView.swift`.
- **Correctif** : trois états distincts ; état de vue dans les services ou `@SceneStorage`.
- **Test de validation** : Storage Map → Dashboard → Storage Map : sélection conservée.

### UIUX-12 — UI bilingue, raccourcis empilés · **P3** · S57
- **Preuve** : `RootView.swift:4-17` ; `CleanupView.swift:19`, `:35`, `:150-152`, `:229-233`, `:86-106`.
- **Impact** : cosmétique ; Échap et ⌘[ imprévisibles.
- **Effort / risque** : S / faible.
- **Fichiers** : `RootView.swift`, `CleanupView.swift`, `AppsView.swift`, `AuditView.swift`.
- **Correctif** : UI en français ; un raccourci par contrôle.
- **Test de validation** : dans chaque état Cleanup, Échap et ⌘[ déclenchent une seule action retour.

**Ajouts de la revue (UI/UX)** : S23 (revisite = scan concurrent, P2, confiance haute) ; callback `{}` du HUD depuis Réglages (`GeneralSettingsView.swift:62-65`, P2) ; `openWindow` sur `WindowGroup` peut dupliquer la fenêtre principale et sa télémétrie (`MoraxCockpitApp.swift:21-24`, `:41-45`, P2, confiance moyenne).

---

## 4. Architecture

Couches Kit/App/Menu saines, `TelemetryCoordinator` bien conçu, `CachedScanStore` partagé. La dette porte sur la propriété des résultats de scan et des caches.

### ARCH-1 — `CleanupStateService` écrit via `.shared` au lieu de `self` · **P2** (auditeur P1) · S24
- **Preuve** : 48 références `CleanupStateService.shared` dans le fichier (`startScan` `:371-424`, `estimate` `:449-474`, `estimateAll` `:484-522`, `executeTrash` `:592+`) ; `init(customCacheDirectory:)` `:107`.
- **Impact** : injection cassée pour tous les chemins async ; les tests passent par `.shared` et écrivent dans le vrai `cleanup_cache.plist`. Aucun impact CPU/RAM.
- **Effort / risque** : S / faible.
- **Fichiers** : `Services/CleanupStateService.swift`.
- **Correctif** : `[weak self]` + `MainActor.run`, zéro `.shared` interne.
- **Test de validation** : instance à dossier temporaire → `estimate` peuple l'instance, `.shared` inchangé ; `grep -c` = 1.

### ARCH-2 — Résultats Cleanup dupliqués, plist réécrit en entier par scanner · **P2** (auditeur P1) · S15
- **Preuve** : `CleanupStateService.swift:397-398`, `:418-424` ; `CachedScanStore.swift:180-187` (lecture-décodage-réencodage complet sous verrou global `:11`) ; décodage synchrone `:119`, `:156`.
- **Impact** : la triple copie mémoire est partagée (copy-on-write) ; duplication réelle = union `all` persistée ; N+1 réécritures par scan « All ». Lien au `Malloc Small` spéculatif.
- **Effort / risque** : M / moyen.
- **Fichiers** : `CleanupStateService.swift`, `CachedScanStore.swift`.
- **Correctif** : ne plus persister `all` ; un fichier (ou verrou) par clé ; chargement async.
- **Test de validation** : compteur d'écritures pendant un scan « All » ; `vmmap --summary` avant/après.

### ARCH-3 — Carte cache Dashboard et Cleanup : mêmes scanners, deux pipelines · **P2** (auditeur P1) · S16
- **Preuve** : `CacheTelemetryService.swift:227-292`, `:185-188` vs `CleanupStateService.swift:535-557`. Déclencheurs : boutons utilisateur (`DashboardView.swift:346-349`, `:945-947`) et scan quotidien (`:193-218`).
- **Impact** : mêmes arbres parcourus deux fois ; totaux divergents entre onglets. Pas de boucle.
- **Effort / risque** : M / moyen.
- **Fichiers** : `CacheTelemetryService.swift`, `CleanupStateService.swift`.
- **Correctif** : dépôt unique de résultats (`ScanResultRepository`), agrégation depuis les snapshots.
- **Test de validation** : compteur par scanner : ouvrir Cleanup sur un snapshot < 24 h = 0 scan ; totaux identiques.

### ARCH-4 — Deux propriétaires du consumer `dashboard` · **P2** (auditeur P1) · S08
- **Preuve** : `RootView.swift:265-273`, `:281-290` ; `DashboardView.swift:124-140` ; `TelemetryCoordinator.swift:98-107` ; `isActive` toujours vrai (`RootView.swift:326-327`) : les toggles usage/Higgsfield ne ré-acquièrent jamais.
- **Impact** : le polling usage/OpenAI/Higgsfield dépend de l'ordre des callbacks SwiftUI.
- **Effort / risque** : S / faible.
- **Fichiers** : `RootView.swift`, `DashboardView.swift`, `TelemetryCoordinator.swift`.
- **Correctif** : propriétaire unique `onAppear`/`onDisappear`, recalcul sur changement de réglage ; accueille la garde de visibilité S04.
- **Test de validation** : test coordinateur « deux acquisitions même ID » ; `requestedFeeds` stable en allers-retours d'onglets.

### ARCH-5 — Code mort (`MetaMuseService`, types inutilisés, handler vide) · **P3** (auditeur P2) · S49
- **Preuve** : `.metaMuse` jamais acquis (`TelemetryCoordinator.swift:16`, `:80`) ; `MetricPoint` (`SystemMetricsService.swift:90`) 0 référence ; `CleanupClassification`, `CleanupSnapshot` test-only ; `MoraxCockpitApp.swift:32-36` vide ; `showMetaMuseGauge` inutilisé.
- **Impact** : ~400 lignes compilées et maintenues ; pas de coût runtime (jamais démarré).
- **Effort / risque** : S / faible.
- **Fichiers** : `MetaMuse/MetaMuseService.swift`, `TelemetryCoordinator.swift`, `SystemMetricsService.swift`, `CleanupClassification.swift`, `FileItem.swift`, `MoraxCockpitApp.swift`, `Tests/.../MetaMuseServiceTests.swift`.
- **Correctif** : supprimer, garder `MetaMuseManualQuota`.
- **Test de validation** : `swift build -c release` et `swift test` verts.

### ARCH-6 — Réglages sans effet, clés `@AppStorage` littérales · **P3** (auditeur P2) · S50
- **Preuve** : `keepMenuBarPosition` (`GeneralSettingsView.swift:413`), `macosWidgetsEnabled` (`:435`), `metamuseProjectID/TeamID` (`:133-136`) sans consommateur ; littéraux `DashboardView.swift:7-10`, `RootView.swift:81`.
- **Impact** : interrupteurs inertes ; valeurs `AppSettings` potentiellement périmées.
- **Effort / risque** : S / faible.
- **Fichiers** : `AppSettings.swift`, `GeneralSettingsView.swift`, `DashboardView.swift`, `RootView.swift`.
- **Correctif** : supprimer ou implémenter ; constantes de clés publiques.
- **Test de validation** : `grep -rn '@AppStorage("' Sources` vide.

### ARCH-7 — Helper `MoraxCockpitMenu` en doublon, sans exclusion mutuelle · **P2** · S17
- **Preuve** : `MoraxCockpitApp.swift:39-49` (commentaire : le helper n'est plus nécessaire) ; `MoraxCockpitMenuApp.swift:9-16`, `:26-31` ; `scripts/build_app.sh:158-195` ; `/Applications/Morax Garage Menu.app` installé ; domaine UserDefaults séparé.
- **Impact** : les deux lancés = 2 coordinateurs, 2 macmon, 2 HUD, réglages divergents ; vues SwiftUI poussées dans la Kit.
- **Effort / risque** : M / moyen.
- **Fichiers** : `MoraxCockpitMenuApp.swift`, `MoraxCockpitApp.swift`, `scripts/build_app.sh`, `Package.swift`.
- **Correctif** : retirer la cible ; sinon s'effacer si `com.morax.garage` tourne.
- **Test de validation** : les deux apps lancées : `pgrep macmon | wc -l` = 1.

### ARCH-8 — Trois `Process()` hors `ProcessRunner` · **P3** (auditeur P2) · S35
- **Preuve** : `ProcessResourceService.swift:347-363`, `NetworkMetricsService.swift:267-282`, `ClaudeCodeScanner.swift:24-41` ; pas de registre (`ProcessRunner.swift:98-99`), pas de timeout.
- **Impact** : cohérence ; interblocage `pgrep` théorique (sortie minuscule).
- **Effort / risque** : S / faible.
- **Fichiers** : ces trois fichiers + `Core/ProcessRunner.swift`.
- **Correctif** : passer par `ProcessRunner.run(timeout:)` ; `NSRunningApplication` au lieu de `pgrep`.
- **Test de validation** : `grep -rn 'Process()' Sources` ne touche que `ProcessRunner.swift`.

### ARCH-9 — Calcul de taille dupliqué, règles divergentes · **P2** · S25
- **Preuve** : `TrashService.swift:165-198` (`.skipsHiddenFiles`, taille logique pour un fichier / allouée pour un dossier, pas d'annulation, 38 appelants) ; `AIModelScanner.swift:188-208` (`st_blocks`, cachés inclus).
- **Impact** : totaux Cleanup incohérents avec Storage Map et AI Models ; octets récupérables sous-estimés ; parcours non annulables.
- **Effort / risque** : S / moyen (change tous les totaux et SafetyGate).
- **Fichiers** : `Core/TrashService.swift`, `AIModels/AIModelScanner.swift`.
- **Correctif** : `DiskUsageCalculator` unique avec annulation (à coupler avec S18).
- **Test de validation** : dossier avec fichier caché de 1 Mo → ≥ 1 Mo ; même taille Storage Map/Cleanup.

### ARCH-10 — Persistance diagnostics couplée au chemin chaud · **P3** (auditeur P2) · S01
- **Preuve** : `SystemMetricsService.swift:737`, `ProcessResourceService.swift:367`, `CacheTelemetryService.swift:183` → `DiagnosticService` @MainActor ; `TelemetryHistoryStore.swift:208-214`.
- **Impact** : dépendance directe des services métriques au singleton diagnostics ; coût réel plus faible qu'annoncé (cache mémoire, écritures throttlées).
- **Effort / risque** : M / faible.
- **Fichiers** : `DiagnosticService.swift`, `TelemetryHistoryStore.swift`, `SystemMetricsService.swift`, `ProcessResourceService.swift`.
- **Correctif** : inverser la dépendance (flux de snapshots) ; évaluation décimée à 60 s.
- **Test de validation** : les services métriques compilent sans référencer `DiagnosticService`.

### ARCH-11 — Fichiers > 800 lignes avec logique métier dans les vues · **P3** (auditeur P2) · S51
- **Preuve** : `DashboardView.swift` 1 462 l. (assemblage PaidApiSpend `:38-72`) ; `GeneralSettingsView.swift` 1 119 l. (`testUsageConnection` `:182-197`, `checkInstalledTools` `:1087-1117`) ; `StorageMapView.swift` 1 091 l. (`computeCategoryTotals` `:818-849`) ; `DemoGuideModels.swift` 1 091 l.
- **Impact** : viole le plafond de 800 lignes ; logique non testable ; invalidation grossière.
- **Effort / risque** : L / faible.
- **Fichiers** : ces quatre fichiers.
- **Correctif** : découpe par composant, logique vers les services.
- **Test de validation** : `wc -l` < 800 partout ; tests `displaySpends`/`testConnection`.

### ARCH-12 — Boilerplate copié-collé, `DateFormatter` par appel · **P3** · S52
- **Preuve** : `AppsStateService`/`AuditStateService`/`EnvironmentStateService` quasi identiques ; résultat d'une tâche annulée écrit quand même (`AuditStateService.swift:52-64`) ; formateur « Aujourd'hui à » ×4 ; `FileItem.swift:281-285`, `StorageNode.swift:343-348` ; 15 `DateFormatter()`.
- **Impact** : corrections à dupliquer ; course latente ; allocations en rendu de liste.
- **Effort / risque** : S / faible.
- **Fichiers** : les services d'état, `FileItem.swift`, `StorageNode.swift`, `CacheTelemetryService.swift`, `StorageMapStateService.swift`.
- **Correctif** : `CachedScanModel<Item>` générique avec compteur de génération ; `ScanDateFormatter` statique.
- **Test de validation** : deux chargements successifs → le second gagne.

**Ajouts de la revue (architecture)** : `TelemetryCoordinator.init` instancie les 7 feeds (S02) ; branches Mini Cockpit identiques et `miniCockpitDetail` jamais acquis (S10) ; `findings` réassigné à chaque tick (S80) ; `startScan` et `estimate` écrivent sans compteur de génération (`CleanupStateService.swift:414-424` vs `:449-474`) ; test `testCleanupStateServiceStartScanAndComplete` qui scanne le vrai disque (S24).
