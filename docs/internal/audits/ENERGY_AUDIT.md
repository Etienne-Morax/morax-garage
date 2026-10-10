# ENERGY_AUDIT — Morax Garage

> Audit système 2026-09, branche `audit/system-audit-2026-09`. Lecture seule (vérifications live limitées à `ps` et `stat`). Synthèse priorisée de toutes les dimensions et identifiants `Sxx` : `PERFORMANCE_AUDIT.md`. La vague 1 d'implémentation est en cours ; résultats dans `IMPLEMENTATION_LOG.md`.

## Constat d'ensemble

- Énergie et température **non mesurées** dans la baseline (pas de `powermetrics` sans `sudo`). Proxy : idle wakeups (`top IDLEW`) ≈ 4/s Dashboard au premier plan ; app installée inactive 0,76 % CPU avec un enfant `macmon pipe -i 1500`.
- Points sains : demande par comptage de références dans `TelemetryCoordinator` avec grace de 5 s ; aucune assertion anti-veille (`beginActivity`, `IOPMAssertion`) ; flux macmon piloté par événements (`readabilityHandler`).
- **Manque principal : la visibilité.** Le gate `scenePhase` a été retiré en `778ed13` et rien n'observe occlusion, minimisation, masquage, veille écran ou verrouillage. Le label de barre de menus (CPU + swap par défaut) garde macmon à 1,5 s en permanence.
- **Coût caché le plus lourd** : réécriture complète de `telemetry-history.json` (4,3 Mo) sur le MainActor jusqu'à 2×/min dès qu'un feed tourne ; le `mtime` du fichier correspondait à l'horloge pendant l'audit.

## Tableau

| ID | Sév. | Constat | Synthèse |
|---|---|---|---|
| ENE-1 | **P1** | Télémétrie Dashboard jamais suspendue (fenêtre minimisée, masquée, occultée) | S04 |
| ENE-3 | **P1** | Label barre de menus → macmon plein régime (+ `nettop` si réseau affiché) | S03 |
| ENE-4 | **P1** | Historique 4,3 Mo réécrit sur le MainActor jusqu'à 2×/min | S01 |
| ENE-2 | P2 (auditeur P1) | Aucune gestion veille / verrouillage / écran éteint | S13 |
| ENE-5 | P2 | Mini Cockpit 1 Hz sur le main, détection de changement contournée | S10 |
| ENE-9 | P2 | `ps` + IOKit synchrones sur le main à l'init et à chaque démarrage | S02 |
| ENE-6 | P3 (auditeur P2) | Aucune tolérance de timer ; heartbeat 4 s | S47 |
| ENE-7 | P3 (auditeur P2) | QoS `.userInitiated` pour l'échantillonnage et le scan quotidien | S48 |
| ENE-8 | P3 (auditeur P2) | Pollers HTTP relancés sans contrôle de fraîcheur | S09 |
| ENE-10 | P3 | Helper menu bar : pile de télémétrie dupliquée | S17 |
| ENE-11 | P3 | Deux jeux de feeds sous le même consumer | S08 |

## Constats

### ENE-1 — Télémétrie Dashboard jamais suspendue quand la fenêtre n'est pas visible · **P1** · S04
- **Preuve** : `RootView.swift:327` (`isActive` dépend seulement de l'onglet ; la condition `scenePhase != .background` de `b8c5841` a disparu en `778ed13`) ; `MoraxCockpitApp.swift:33-37` (`onChange(of: scenePhase)` vide) ; libération seulement sur `onDisappear` (`RootView.swift:268-270`), qui ne se déclenche pas sur minimisation, ⌘H ou occlusion ; aucun observer (grep `occlusion|didMiniaturize|didHide` vide). Restent actifs : macmon 1,5 s (`SystemMetricsService.swift:324`, `:543-547`), `nettop` / 3,5 s (`NetworkMetricsService.swift:139`, `:195`, `:263-281`), `ps` + IOKit / 5 s (`ProcessResourceService.swift:222`, `:305-312`), plus les écritures d'historique.
- **Impact** : une fois minimisée, le rendu SwiftUI s'arrête (le coût n'est pas les 18,6 % du premier plan), mais les 3 flux d'échantillonnage et leurs processus enfants continuent indéfiniment. Viole « CPU bas quand rien n'est visible ».
- **Effort / risque** : S / faible.
- **Fichiers** : `Sources/MoraxCockpit/App/RootView.swift`, `App/MoraxCockpitApp.swift`, `Features/Dashboard/DashboardView.swift`.
- **Correctif** : observer de fenêtre (`NSViewRepresentable`) sur `occlusionState.contains(.visible)`, `didMiniaturize`/`didDeminiaturize`, `NSApplication.didHide`/`didUnhide` ; injecter `isWindowVisible` dans le propriétaire unique de la demande Dashboard (S08). L'occlusion ne bascule pas sur simple perte de focus : évite la régression de `b8c5841`. La grace de 5 s absorbe le scintillement.
- **Test de validation** : Dashboard ouvert puis minimisé : sous ~6 s, log `TelemetryLogger.lifecycle` « stopping feed 'network'/'process' » ; `pgrep -f 'nettop -P'` vide pendant 30 s ; `top -l 60 -s 1 -pid <pid>` minimisé avant/après ; test coordinateur avec source de visibilité factice.

### ENE-2 — Aucune gestion veille / verrouillage / écran éteint · **P2** (auditeur P1) · S13
- **Preuve** : grep `screensDidSleep|sessionDidResignActive|willSleep|didWake` vide ; le label acquiert `.system` par défaut (`MoraxMenuBarView.swift:133-143` ; `AppSettings.swift:334-336`, `:345-346`) ; le Mini Cockpit acquiert `[.system,.process,.usage,.openAICosts]` quand visible (`MiniCockpitStateEngine.swift:401-419`) ; `macmon pipe -i 1500` vivant pendant l'audit.
- **Impact** : macmon 1,5 s, heartbeat 4 s (`SystemMetricsService.swift:400-415`) et boucle 1 Hz du HUD (opt-in) continuent écran éteint, session verrouillée ou utilisateur basculé. Forte overlap avec ENE-3 : une fois macmon retiré du chemin label, le coût nocturne résiduel est un échantillon natif. « Bloque l'idle profond » non mesuré.
- **Effort / risque** : S / faible.
- **Fichiers** : `Metrics/TelemetryCoordinator.swift`, `Core/DesignSystem/MoraxMenuBarView.swift`, `MiniCockpit/MiniCockpitStateEngine.swift`.
- **Correctif** : drapeau global `suspended` dans `TelemetryCoordinator` piloté par `screensDidSleep/Wake`, `sessionDidResignActive/BecomeActive`, `willSleep/didWake` : `stopNow()` sur tous les feeds, `reconcile` à la reprise (les demandes sont déjà conservées). Valable pour l'app et le helper.
- **Test de validation** : `pmset displaysleepnow`, 10 s, `pgrep macmon` vide ; au réveil, macmon relancé et label mis à jour en ≤ 2 échantillons ; test avec `NotificationCenter` injecté.

### ENE-3 — Le label toujours visible entretient macmon à 1,5 s (et `nettop`) · **P1** · S03
- **Preuve** : intervalle global unique `SystemMetricsService.swift:324` passé à macmon (`:543-547`) quel que soit le consumer ; le label demande `.system` pour CPU/RAM/disque/swap (`MoraxMenuBarView.swift:133-143`), déjà calculés nativement (`sampleNativeMetrics` `:577-640`) ; si `menuBarShowNetwork` (défaut faux), `.network` lance `pollNettop` (`NetworkMetricsService.swift:161-165`, fork/exec `:195`, `:265-281`) alors que le label n'utilise que les compteurs `getifaddrs` (`:284-330`) ; chaque ligne macmon remplace `currentSnapshot` → redessin du status item toutes les 1,5 s.
- **Impact** : c'est le régime permanent de l'app fenêtre fermée (état le plus fréquent) : échantillonnage IOReport puissance/GPU/thermique que rien n'affiche. Par défaut, macmon seul (`nettop` uniquement si l'option réseau est activée).
- **Effort / risque** : M / moyen.
- **Fichiers** : `Metrics/SystemMetricsService.swift`, `Metrics/NetworkMetricsService.swift`, `Metrics/TelemetryCoordinator.swift`, `Core/DesignSystem/MoraxMenuBarView.swift`.
- **Correctif** : niveau de demande « lite » (feed dédié ou cadence par consumer) : label seul → natif `host_statistics` + `getifaddrs` toutes les 3-5 s avec tolérance, sans macmon, `nettop` ni heartbeat ; macmon 1,5 s seulement avec Dashboard, popover ou HUD, ou si `menuBarShowTemperature` est activé. Publier au label seulement si les valeurs arrondies changent.
- **Test de validation** : fenêtre fermée, label seul : `pgrep macmon` et `pgrep nettop` vides ; `top -l 120 -s 1` < 0,3 % CPU moyen ; `powermetrics --samplers tasks -i 5000` < 1 wakeup/s (app + enfants) ; ouverture du popover → macmon en < 1 s.

### ENE-4 — Historique 4,3 Mo réécrit sur le MainActor jusqu'à 2×/min · **P1** · S01
- **Preuve** : `DiagnosticService.swift:41-51` (`ingest` à chaque échantillon via `SystemMetricsService.swift:735-738`) et `:58-63` (`ingestProcesses` toutes les 5 s via `ProcessResourceService.swift:365-368`) ; `TelemetryHistoryStore.swift:168-177` (prune + `write`), `:209-215` (encodage + écriture atomique du fichier entier), `:127` (60 s par flux) ; @MainActor (`DiagnosticService.swift:5`) ; fichier 4 336 275 octets, `mtime` = heure courante ; scan de tous les `processRecords` par app top-RAM toutes les 5 s (`:64-68`).
- **Impact** : jusqu'à ~6-12 Go/jour d'écritures SSD (fichier temporaire + rename) tant que le label ou le Dashboard est actif ; encodages multi-Mo sur le main ; réveils disque et CPU.
- **Effort / risque** : M / moyen.
- **Fichiers** : `Diagnostics/TelemetryHistoryStore.swift`, `Diagnostics/DiagnosticService.swift`.
- **Correctif** : acteur hors MainActor ; tampon mémoire, flush toutes les 10-15 min et à `applicationWillTerminate` ; JSON Lines append-only (ou SQLite) ; compaction ≤ 1×/jour (idéalement `NSBackgroundActivityScheduler`) ; références RAM 24 h mises en cache et recalculées au flush. Corriger aussi la compaction bloquée (MEM-4).
- **Test de validation** : `sudo fs_usage -w -f filesys <pid> | grep telemetry-history` 10 min : ≤ 1 écriture (vs ~20) ; octets écrits/heure (`iostat`) ; aucun `JSONEncoder` main au repos ; test : N appends en 60 s → ≤ 1 écriture ; tests `TelemetryHistoryStore` existants verts.

### ENE-5 — Mini Cockpit : poll 1 Hz sur le MainActor, sparklines poussées sans contrôle · **P2** · S10
- **Preuve** : `MiniCockpitStateEngine.swift:422-435` (boucle `Task.sleep` 1 s sur des services déjà `@Observable`) ; `:358-389` branche `else` qui pousse dans `cpuSparkline`/`gpuSparkline` (`:285-286`), lus par `MiniCockpitHUDView.swift:387-403` ; `syncTelemetryDemand` `:408-419` à branches identiques (usage/OpenAI même en compact) ; aucune pause sur occlusion ou autre Space (`MiniCockpitWindowController.swift:161-167`).
- **Impact** : réveil main permanent à 1 Hz + re-rendu d'un panneau translucide flottant, même entièrement couvert. Limité aux utilisateurs qui activent le HUD.
- **Effort / risque** : S / faible.
- **Fichiers** : `MiniCockpit/MiniCockpitStateEngine.swift`, `MiniCockpit/MiniCockpitWindowController.swift`.
- **Correctif** : push depuis `SystemMetricsService` (callback ou `withObservationTracking`) ; sparkline seulement si `timestamp` avance ; `stop()/start()` sur `didChangeOcclusionState` ; compact sans usage/OpenAI.
- **Test de validation** : HUD visible au repos, SwiftUI : ≤ 40 évaluations/60 s (vs ≥ 60) ; HUD couvert par une fenêtre plein écran : consumer `miniCockpit` libéré dans le log.

### ENE-6 — Aucune tolérance de timer ; heartbeat 4 s même macmon sain · **P3** (auditeur P2) · S47
- **Preuve** : grep `tolerance` ne trouve aucun timer ; `Task.sleep(nanoseconds:)` partout : `SystemMetricsService.swift:403`, `:444`, `:483`, `:497` ; `NetworkMetricsService.swift:263`, `:328` ; `ProcessResourceService.swift:256` ; `MiniCockpitStateEngine.swift:432` ; `CacheTelemetryService.swift:205` ; `HiggsfieldCreditService.swift:77`. Heartbeat `SystemMetricsService.swift:400-415` : saut MainActor toutes les 4 s.
- **Impact** : 4-5 cadences indépendantes (1 / 1,5 / 3,5 / 4 / 5 s) non coalescées ; gain marginal face aux coûts dominants (processus, IOReport, réécritures).
- **Effort / risque** : S / faible.
- **Fichiers** : `SystemMetricsService.swift`, `NetworkMetricsService.swift`, `ProcessResourceService.swift`, `MiniCockpitStateEngine.swift`.
- **Correctif** : opportuniste pendant S03/S04 : `Task.sleep(for:tolerance:)` (~20 %), cadences multiples d'une base (1,5 / 3 / 6 s), heartbeat transformé en échéance réarmée à chaque échantillon.
- **Test de validation** : `sudo powermetrics --samplers tasks --show-process-wakeups -i 5000 -n 12` : < 2 wakeups/s Dashboard visible, < 0,5/s label seul.

### ENE-7 — Échantillonnage et scan quotidien en QoS `.userInitiated` · **P3** (auditeur P2) · S48
- **Preuve** : `Task.detached(priority: .userInitiated)` : `SystemMetricsService.swift:421`, `NetworkMetricsService.swift:161`, `ProcessResourceService.swift:245`, `CacheTelemetryService.swift:177` ; scan lancé au démarrage (`MoraxCockpitApp.swift:72`, `CacheTelemetryService.swift:192-194`) avec boucle horaire maison.
- **Impact** : cœurs P et priorité de timer élevée pour du travail de fond ; les boucles passent l'essentiel du temps bloquées en I/O ou en sommeil ; le scan tourne au plus 1×/24 h. Gain marginal.
- **Effort / risque** : S / faible.
- **Fichiers** : `SystemMetricsService.swift`, `NetworkMetricsService.swift`, `ProcessResourceService.swift`, `CacheTelemetryService.swift`.
- **Correctif** : `.utility` pour les boucles ; `.userInitiated` réservé au bouton de refresh (`DashboardView.swift:347-351`). Migration `NSBackgroundActivityScheduler` optionnelle.
- **Test de validation** : Instruments, colonne QoS : threads d'échantillonnage en Utility ; lancement avec cache > 24 h sans régression du temps à la 1re fenêtre.

### ENE-8 — Pollers HTTP relancés à chaque redémarrage de feed · **P3** (auditeur P2) · S09
- **Preuve** : `UsageQuotaService.swift:49-59`, `:79-81` ; `OpenAICostsService.swift:54-58` ; `HiggsfieldCreditService.swift:67-72` ; déclenché par `TelemetryCoordinator.reconcile` (`:136-139`) ; `usage-quotas.json` persisté mais âge jamais vérifié.
- **Impact** : au plus une requête par endpoint par revisite après > 5 s (pas une boucle) ; le snapshot en cache est déjà affiché. Énergie négligeable, mais contraire à la règle « servi depuis le cache ».
- **Effort / risque** : S / faible.
- **Fichiers** : `UsageQuotaService.swift`, `OpenAICostsService.swift`, `HiggsfieldCreditService.swift`.
- **Correctif** : `lastSuccessAt` ; au démarrage, dormir le reste de l'intervalle ; bouton manuel = chemin forcé.
- **Test de validation** : horloge injectée : redémarrage < 300 s après un succès → 0 requête (stub `URLProtocol`) ; 10 changements d'onglet en 2 min → 1 requête par endpoint.

### ENE-9 — `ps` + parcours GPU IOKit synchrones sur le main (init et démarrage du feed) · **P2** · S02
- **Preuve** : `ProcessResourceService.swift:232-235` (`init` → `sampleImmediate`), `:237-242` (`startMonitoring` → idem), `:275-278`, `:347-358` (`waitUntilExit`), classe @MainActor (`:216-217`) ; `TelemetryCoordinator.swift:74-82` instancie le service au lancement, dans l'app et dans le helper, même si seul `.system` est demandé.
- **Impact** : blocage main (spawn + IORegistry) au lancement et à chaque retour Dashboard ; spawn inutile au lancement du helper.
- **Effort / risque** : S / faible.
- **Fichiers** : `Metrics/ProcessResourceService.swift`, `Metrics/TelemetryCoordinator.swift`.
- **Correctif** : supprimer l'échantillon synchrone ; contrôles du coordinateur paresseux (closures résolvant `.shared` au 1er démarrage).
- **Test de validation** : Time Profiler au lancement et au retour Dashboard : aucun `executePs`/`waitUntilExit` sur le main ; signpost changement d'onglet → 1re frame.

### ENE-10 — Le helper barre de menus duplique toute la pile de télémétrie · **P3** · S17
- **Preuve** : l'app principale a son `MenuBarExtra` et restaure le HUD (`MoraxCockpitApp.swift:39-49`, `:77-82`) ; `MoraxCockpitMenuApp.swift:10-17`, `:26-31` recrée label, HUD et son propre `TelemetryCoordinator.shared` ; `scripts/build_app.sh:158-166` ; `/Applications/Morax Garage Menu.app` installé (non lancé pendant l'audit).
- **Impact** : si les deux tournent : 2 flux macmon, 2 labels, potentiellement 2 HUD et 2 écrivains concurrents sur `telemetry-history.json` (voir S27) → coût au repos doublé.
- **Effort / risque** : S / faible.
- **Fichiers** : `Sources/MoraxCockpitMenu/MoraxCockpitMenuApp.swift`, `App/MoraxCockpitApp.swift`, `scripts/build_app.sh`.
- **Correctif** : cesser de construire et livrer le helper ; à défaut, s'effacer si `com.morax.garage` tourne (`NSRunningApplication` + `didLaunchApplicationNotification`).
- **Test de validation** : les deux apps lancées : `pgrep -fl macmon` = exactement 1 processus.

### ENE-11 — RootView et DashboardView écrivent des feeds contradictoires sous le même consumer · **P3** · S08
- **Preuve** : `RootView.swift:281-289` (`[.system,.network,.process]`) vs `DashboardView.swift:132-140` (+ usage/OpenAI/Higgsfield) ; `TelemetryCoordinator.swift:98-106` remplace la demande.
- **Impact** : churn possible start/stop des feeds HTTP et processus, cartes figées selon l'ordre des callbacks ; non observé.
- **Effort / risque** : S / faible.
- **Fichiers** : `RootView.swift`, `DashboardView.swift`.
- **Correctif** : propriétaire unique, qui porte aussi la garde de visibilité d'ENE-1.
- **Test de validation** : log au lancement avec `showUsageQuotas=true` : aucun « scheduling stop for 'usage' » Dashboard affiché ; test : un ID de consumer = un seul site d'appel.

## Ajouts de la revue

- Chaque append relance l'élagage complet (filtre + tri + regroupement sur 10k) et l'encodage du fichier entier (`TelemetryHistoryStore.swift:168-177`) : contributeur plausible au `Malloc Small` dirty de l'app installée ; à vérifier par diff `heap`/`vmmap` avant/après S01.
- `updateSnapshot` appelle `DiagnosticService.shared.ingest` (évaluation du moteur + remplacement des `findings` observés) à chaque échantillon de 1,5 s, même label seul (`SystemMetricsService.swift:736-738`) : décimer l'évaluation (une fois par écriture d'historique). Aggrave ENE-3 ; voir S80.
- Le `CacheSnapshot` complet est encodé dans UserDefaults après chaque scan (`CacheTelemetryService.swift:187-189`) : à déplacer dans Application Support (S38).
