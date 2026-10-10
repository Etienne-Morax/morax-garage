# MEMORY_AUDIT — Morax Garage

> Audit système 2026-09, branche `audit/system-audit-2026-09`. Lecture seule. Synthèse priorisée de toutes les dimensions et identifiants `Sxx` : `PERFORMANCE_AUDIT.md`. La vague 1 d'implémentation est en cours ; résultats dans `IMPLEMENTATION_LOG.md`.

## Constat d'ensemble

- **Baseline** (`BASELINE_V0.md`) : 138 Mo de footprint au lancement ; l'app installée, fenêtre inactive, monte à **262 Mo dont 192 Mo `Malloc Small` dirty**.
- **Mesures disque** : `storage_map_cache.plist` 29,5 Mo (79 862 nœuds, plafond 80k) ; `telemetry-history.json` 4,3 Mo (9 979/10 000 enregistrements, 7 124 à `sampleCount=2`) ; `~/Library/Caches` 454 616 fichiers (dont `claude-cli-nodejs` 319 616, `Google` 87 370) ; blob UserDefaults cache-telemetry 412 Ko.
- **Hypothèse** (non prouvée) : les 192 Mo sont de la fragmentation laissée par des pics transitoires, pas une structure vivante. Candidat principal : le scan quotidien des caches (MEM-1). Autres contributeurs : encode/décodage du snapshot Storage Map (MEM-3) et réécriture JSON de l'historique chaque minute (MEM-4). Seule grosse structure vivante : l'arbre Storage Map (MEM-2).
- Rien ne réagit à la pression mémoire (`MemoryPressureMonitor` sert seulement à afficher une jauge).
- Aucun cycle de rétention trouvé (observers sur singletons, `[weak self]`, objets IOKit libérés).
- Déjà en place et vérifié : budget 80k nœuds / profondeur 12, seuil de repli 1 Mo, `autoreleasepool` dans `StorageScanner` (`:178`), limites `NSCache` noms/icônes.

**À faire avant tout correctif** : confirmer l'attribution avec `vmmap --summary`, `heap -s` et `MallocStackLogging=1` + `malloc_history`, juste après le lancement puis après ouverture de Storage Map.

## Tableau

| ID | Sév. | Constat | Synthèse |
|---|---|---|---|
| MEM-1 | P2 (auditeur P1) | `calculateSize` sans `autoreleasepool`, task group non borné | S18 |
| MEM-2 | P2 (auditeur P1) | Arbre Storage Map 80k nœuds résident à vie | S19 |
| MEM-4 | P2 | Compaction de l'historique bloquée + réécriture 4,3 Mo sur le main | S01 |
| MEM-3 | P3 (auditeur P2) | Pics transitoires encode/décodage du snapshot Storage Map | S41 |
| MEM-5 | P3 | Blob 412 Ko dans UserDefaults | S38 |
| MEM-6 | P3 | `Bundle(url:)` gardés à vie | S42 |
| MEM-7 | P3 | Mascotte 1024×1024 décodée à chaque `body` | S37 |
| MEM-8 | P3 | Terminal et shell retenus à vie | S43 |

## Constats

### MEM-1 — Scan quotidien des caches : ~450k fichiers, sans `autoreleasepool`, en parallèle · **P2** (auditeur P1) · S18
- **Preuve** : `TrashService.swift:180-197` (boucle `NSDirectoryEnumerator` + `resourceValues`, aucun pool) ; seul pool du code : `StorageScanner.swift:178`. `SystemCacheScanner.swift:101-105` lance un `calculateSize` par dossier (239) sans borne ; `CacheTelemetryService.swift:228-238` lance 5 scanners en `async let`. `Google` non exclu : `knownControlledNames` contient `Google/Chrome` mais compare `lastPathComponent` (`SystemCacheScanner.swift:72-98`) → cache Chrome parcouru deux fois. Corrections de la revue : le scan ne tourne que si le snapshot a > 24 h (`CacheTelemetryService.swift:172`, `:194-199`), pas à chaque lancement ; la boucle d'`AppCacheScanner.swift:40-55` porte sur les profils, le parcours est dans `calculateSize` (`:65`).
- **Impact** : pic transitoire estimé à des centaines de Mo (320k NSURL dans un seul appel) réparti sur les magazines malloc par CPU, qui restent dirty après vidage. Cohérent avec les 192 Mo, **non mesuré**.
- **Effort / risque** : S / faible.
- **Fichiers** : `Sources/MoraxCockpitKit/Core/TrashService.swift`, `Scanners/SystemCacheScanner.swift`, `Metrics/CacheTelemetryService.swift`, `Scanners/AppCacheScanner.swift`, `PhotoSync/PhotoSyncScanner.swift`.
- **Correctif** : pool dans la boucle (ou vidage tous les ~1 000 éléments), idéalement parcours `readdir/lstat` comme `StorageScanner` ; task group borné à 2-3 ; exclure `Google` par préfixe relatif. Un seul correctif dans `calculateSize` couvre ~20 appelants, dont l'inventaire Apps (revue : `AppsService.swift:50-53`, `:104`, Xcode.app).
- **Test de validation** : refresh forcé avec `MallocStackLogging=1` ; `footprint -p` et `vmmap --summary` avant, au pic, 60 s après → pic −100 Mo, `Malloc Small` dirty < 30 Mo après scan. Test unitaire sur fixture de 200k fichiers bornant le delta de `phys_footprint`.

### MEM-2 — Arbre Storage Map (80k nœuds) résident à vie après la 1re visite · **P2** (auditeur P1) · S19
- **Preuve** : `StorageMapStateService.swift:10` (`rootNode` sur le singleton), libéré seulement par `clearCache()` (`:298-299`) ; budget `:44` ; `StorageNode.swift:245-291` : `id: UUID`, `url`, `path` (copie de `url.path`, `:291`), `name`, `fileExtension`, dictionnaire `categoryBreakdown` par dossier. 79 862 nœuds, chemins de 100 caractères en moyenne. Le treemap ne dessine que quelques milliers de tuiles (seuil 3 px, `TreemapLayoutEngine.swift:49`).
- **Impact** : estimé 30-55 Mo (0,4-0,7 Ko/nœud) pour toute la vie du processus, y compris en mode barre de menus seule.
- **Effort / risque** : M / moyen.
- **Fichiers** : `StorageMap/StorageNode.swift`, `StorageMap/StorageMapStateService.swift`, `Features/StorageMap/StorageMapView.swift`.
- **Correctif** : privilégier (a) supprimer `url` stocké (dérivé de `path`) et remplacer l'UUID par un index entier — aucun changement de comportement. La libération à l'onglet caché ou le budget réduit à 10-20k contredisent « onglets instantanés » (re-décodage de 30 Mo) : à arbitrer par le propriétaire.
- **Test de validation** : cache existant chargé, `heap <pid> -s` (StorageNode, NSURL, `_StringStorage`) avant/après ; `phys_footprint` après visite puis 5 min hors onglet ; test : totaux identiques après repli.

### MEM-3 — Encode/décodage récursif du snapshot 80k nœuds ; `url` + `path` doublent le fichier · **P3** (auditeur P2) · S41
- **Preuve** : `StorageNode.swift:560-561`, `:583-584` (les deux champs encodés/décodés ; `url` encodé en dictionnaire `{'relative': …}`) ; décodage complet `StorageMapStateService.swift:112` (+ repli JSON `:117`) ; encodage complet `:190-218` ; `nodeCount` récursif jusqu'à 16× dans `collapseToCacheBudget` (`StorageNode.swift:437-443`, coût CPU).
- **Impact** : pic transitoire plusieurs fois la taille du fichier (29,5 Mo) à la 1re visite après lancement et en fin de scan ; événements rares et déclenchés par l'utilisateur.
- **Effort / risque** : M / faible (S pour le seul retrait de `url`).
- **Fichiers** : `StorageMap/StorageNode.swift`, `StorageMap/StorageMapStateService.swift`.
- **Correctif** : ne plus encoder `url` (gain immédiat) ; format plat reporté faute de mesure.
- **Test de validation** : taille du fichier (−50 % attendu), durée et pic de décodage (Allocations « All Heap ») ; test d'aller-retour.

### MEM-4 — Compaction de l'historique bloquée au plafond de 10k ; 4,3 Mo ré-encodés sur le main · **P2** · S01
- **Preuve** : `TelemetryHistoryStore.swift:225` gèle tout enregistrement `sampleCount > 1`. Mécanisme (revue) : `pruned()` tourne à chaque append (`:170-171`) ; un enregistrement franchissant 24 h devient un seau à `sampleCount=1`, s'apparie la minute suivante (`sampleCount=2`) puis est gelé (`:233-240`) → ~1 enregistrement / 2 min au lieu de 1 / 5 min, jamais de seaux horaires. Rétention prévue ~3,8k enregistrements ; observé 9 979 sur ~23 jours. Écriture complète `:209-215`, depuis `DiagnosticService` @MainActor (`:47`, `:63`, `:79`), active aussi au repos car `menuBarShowCpu` est vrai par défaut (`AppSettings.swift:335`).
- **Impact** : 10-20 Mo d'allocations transitoires et un à-coup main par minute, indéfiniment ; cache mémoire ~2,5× plus gros que prévu.
- **Effort / risque** : S / faible.
- **Fichiers** : `Diagnostics/TelemetryHistoryStore.swift`, `Diagnostics/DiagnosticService.swift`.
- **Correctif** : compacter par âge quel que soit `sampleCount`, moyennes pondérées (idempotent) ; écriture dans un acteur ; flux groupés toutes les 5 min ou append-only.
- **Test de validation** : simuler des appends à 1/min sur 8+ jours (pas une purge unique) → ~3,8k enregistrements, stable à la 2e purge ; `ingest` < 1 ms main (Time Profiler).

### MEM-5 — Snapshot cache-telemetry (412 Ko) dans UserDefaults · **P3** · S38
- **Preuve** : `CacheTelemetryService.swift:138-139` (décodage à l'init), `:186-189` (réécriture après chaque scan) ; clé de 412 220 octets, toutes les autres < 500 octets ; détails par élément construits `:240-310`.
- **Impact** : domaine de préférences gonflé en mémoire dans l'app et `cfprefsd` ; chaque écriture de préférence le traverse. Petit mais permanent.
- **Effort / risque** : S / faible.
- **Fichiers** : `Metrics/CacheTelemetryService.swift`.
- **Correctif** : `CachedScanStore` dans Application Support ; totaux en mémoire, détails chargés à l'ouverture de la feuille ; supprimer l'ancienne clé.
- **Test de validation** : `defaults read com.morax.garage | wc -c` −400 Ko ; test d'aller-retour.

### MEM-6 — `Bundle(url:)` conservés par Foundation · **P3** · S42
- **Preuve** : `ProcessResourceService.swift:95` (par `.app` vu), `AppsService.swift:92` (par bundle inventorié). Le buffer `[CChar](4096)` de `GpuProcessSampler.swift:186` est négligeable (revue).
- **Impact** : croissance bornée par le nombre d'apps distinctes, ~1-2 Mo ; gain marginal.
- **Effort / risque** : S / faible.
- **Fichiers** : `ProcessResourceService.swift`, `AppsService.swift`.
- **Correctif** : lire `Info.plist` directement ou `NSRunningApplication.localizedName`.
- **Test de validation** : `heap <pid> | grep NSBundle` stable après 30 min de Dashboard + un inventaire Apps.

### MEM-7 — Mascotte 1024×1024 relue et décodée pour un affichage à 32-38 pt · **P3** · S37
- **Preuve** : `MoraxMascotView.swift:13-14` appelle `loadMascotImage()` dans `body` → `NSImage(contentsOf:)` (`:41-50`) à chaque ré-évaluation ; hôtes `RootView.swift:119`, `MoraxMenuBarView.swift:184`, Réglages, Cleanup, `ScannerSelectionView`.
- **Impact** : ~4 Mo de bitmap par instance vivante + I/O + décodage à chaque rendu hôte.
- **Effort / risque** : S / faible.
- **Fichiers** : `Core/DesignSystem/MoraxMascotView.swift`, `Resources/MoraxMascot.png`.
- **Correctif** : asset 128 px chargé une fois (`static let`) ; supprimer le JPG inutilisé.
- **Test de validation** : ouvrir le popover 10 fois : pas de +4 Mo par ouverture (Allocations).

### MEM-8 — Terminal intégré et shell retenus à vie · **P3** · S43
- **Preuve** : `TerminalView.swift:93-127` (`TerminalController.shared`, `$SHELL -l`, jamais arrêté) ; scrollback SwiftTerm 500 lignes.
- **Impact** : quelques Mo + un processus enfant persistant. Persistance probablement voulue.
- **Effort / risque** : S / faible.
- **Fichiers** : `Features/Terminal/TerminalView.swift`.
- **Correctif** : action explicite « Fermer la session » ou délai opt-in ; pas d'arrêt automatique (perte d'état shell).
- **Test de validation** : après fermeture de session, `pgrep -P <pid>` ne liste plus le shell.

## Ajouts de la revue

- Inventaire Apps : un `calculateSize` par `.app` dans un task group non borné (`AppsService.swift:50-53`, `:104`) — même mécanisme que MEM-1, couvert par le même correctif.
- La réécriture de l'historique (4,3 Mo + tampons d'encodeur, 2×/min sur le main) est un autre contributeur plausible au `Malloc Small` dirty (`TelemetryHistoryStore.swift:168-177`) : à vérifier par diff `heap`/`vmmap` avant/après S01.
