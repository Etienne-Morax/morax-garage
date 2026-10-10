# GPU_AUDIT — Morax Garage

> Audit système 2026-09, branche `audit/system-audit-2026-09`. Lecture seule. Synthèse priorisée de toutes les dimensions et identifiants `Sxx` : `PERFORMANCE_AUDIT.md`. La vague 1 d'implémentation est en cours ; résultats dans `IMPLEMENTATION_LOG.md`.

## Constat d'ensemble

- Mesure GPU per-process **indisponible** dans la baseline (pas de `powermetrics`/Instruments sans `sudo`) : toutes les magnitudes sont des estimations ; la preuve de code est précise.
- Pas de `TimelineView`, pas de `drawingGroup`, pas d'animation continue permanente. Canvas pour la sparkline et le treemap. Déjà corrigé (non repris) : grille Dashboard sans `LazyVGrid`, séparation du survol treemap (`580d68a`).
- Deux familles de problèmes :
  - **Architecture d'échantillonnage** : macmon (IOReport) actif 24/7 pour le label de la barre de menus ; décodage et publication inconditionnelle sur le main ; `ps` + parcours IORegistry synchrones.
  - **Rendu** : spring sur 6 jauges à chaque échantillon avec arc non animable ; backdrops behind-window empilés sous des dégradés quasi opaques ; HUD clair avec matériau ; layout treemap dans le `body`.

## Tableau

| ID | Sév. | Constat | Synthèse |
|---|---|---|---|
| GPU-1 | **P1** | macmon 24/7 pour le label barre de menus et le Mini Cockpit | S03 |
| GPU-3 | **P1** | `ps` + IORegistry complet synchrones sur le main | S02 |
| GPU-2 | P2 (auditeur P1) | Décodage macmon sur le main, publication sans égalité | S12 |
| GPU-4 | P2 | Spring sur 6 jauges, arc non animable, blur | S11 |
| GPU-7 | P2 | Mini Cockpit 1 Hz, sparkline sans détection de changement | S10 |
| GPU-8 | P2 | Treemap : layout dans le `body`, Canvas redessiné au survol | S20 |
| GPU-5 | P3 (auditeur P2) | Backdrops behind-window empilés | S34 |
| GPU-6 | P3 (auditeur P2) | HUD clair : `.thinMaterial` + opacité 0,94 | S44 |
| GPU-9 | P3 | Radar de scan en `repeatForever` | S45 |
| GPU-10 | P3 | ~30 ombres décoratives | S46 |

## Constats

### GPU-1 — macmon (sous-processus IOReport) actif 24/7 pour un simple « CPU 12 % » · **P1** · S03
- **Preuve** : `MoraxMenuBarView.swift:133-138` insère `.system` si CPU/RAM/Disk/Swap/Temp affichés ; `AppSettings.swift:321-337` : `menuBarEnabled` et `menuBarShowCpu` vrais par défaut ; `SystemMetricsService.swift:421-450` lance toujours macmon pour `.system`, `:543-546` `macmon pipe -i 1500` ; `sampleNativeMetrics` (`:578-650`, `NativeGpuSampler.swift:12-66`) fournit déjà CPU/RAM/GPU % mais ne sert que de repli. Le Mini Cockpit (`MiniCockpitStateEngine.swift:405-414`) ne lit que cpu/gpu/ram/swap. Seuls température, puissance et fréquence GPU (cadrans 4-5, `DashboardView.swift:740-800`) exigent macmon. Baseline : macmon est l'enfant de l'app installée inactive.
- **Impact** : processus permanent + pipe + découpe de lignes + décodage JSON toutes les 1,5 s, toute la journée. Plus gros coût évitable en configuration par défaut.
- **Effort / risque** : M / faible.
- **Fichiers** : `Metrics/SystemMetricsService.swift`, `Metrics/TelemetryCoordinator.swift`, `Core/DesignSystem/MoraxMenuBarView.swift`, `MiniCockpit/MiniCockpitStateEngine.swift`.
- **Correctif** : scinder en `.system` (Darwin natif, 2-3 s) et `.hardware` (macmon) ; seuls le hero Dashboard et l'option température acquièrent `.hardware`.
- **Test de validation** : barre de menus seule (fenêtre fermée, HUD caché) : `pgrep -fl macmon` vide ; `top -pid <app> -stats cpu,idlew` 120 s < V0 (0,76 %) ; test coordinateur : feeds du label sans température ne démarrent pas `.hardware`.

### GPU-2 — Décodage macmon, mémoire et volumes sur le main ; republication sans égalité · **P2** (auditeur P1) · S12
- **Preuve** : classe `@Observable @MainActor` (`SystemMetricsService.swift:318-320`) ; `streamFromMacmon` (`:538`, décodage `:561`) ; `createSnapshot` (`:660-730`) appelle `getDiskVolumes()` (`:661`, `:740-780`, volumes réseau inclus, TTL 30 s) ; `updateSnapshot` (`:735-738`) assigne toujours (nouvelle `Date`).
- **Impact** : décodage d'une ligne par 1,5 s = microsecondes ; seul blocage crédible : capacité d'un volume SMB (tous les 30 s). La publication inconditionnelle force le re-rendu du label et du hero à chaque échantillon.
- **Effort / risque** : M / moyen.
- **Fichiers** : `Metrics/SystemMetricsService.swift`.
- **Correctif** : priorité à la publication conditionnelle sur valeurs quantifiées (CPU/GPU 1 %, RAM 50 Mo, puissance 0,1 W, comme le Mini Cockpit) ; boucle et décodage `nonisolated` ; volumes hors main, volumes non locaux exclus.
- **Test de validation** : Time Profiler main : ni `JSONDecoder`/`MacmonSample` ni `mountedVolumeURLs` ; SwiftUI View Body sur `MoraxMenuBarLabel`/`AutomotiveGauge` 60 s à charge stable : moins d'évaluations.

### GPU-3 — `ps` synchrone + copie de tout l'IORegistry sur le main · **P1** · S02
- **Preuve** : `ProcessResourceService.swift:217-218` (@MainActor), `init` `:233-236` et `startMonitoring` `:243` → `sampleImmediate` (`:275-305`) → `executePs` (`:347-363`, bloquant) + `GpuProcessSampler.collectRawEntries` (`GpuProcessSampler.swift:29-104`, `IORegistryEntryCreateCFProperties` complet `:60` pour lire 2 clés). `TelemetryCoordinator.swift:74-82` force l'instance au lancement ; grace 5 s (`:60`). Nuance : si le HUD est visible il tient `.process`, pas de blocage au changement d'onglet.
- **Impact** : dizaines à centaines de ms sur le main à chaque retour au Dashboard et au lancement.
- **Effort / risque** : S / faible.
- **Fichiers** : `Metrics/ProcessResourceService.swift`, `Metrics/GpuProcessSampler.swift`.
- **Correctif** : supprimer `sampleImmediate` ; `IORegistryEntryCreateCFProperty` sur `IOUserClientCreator` et `AppUsage` seulement ; à terme `proc_pidinfo`.
- **Test de validation** : signpost Storage Map → Dashboard (> 5 s d'absence), Hangs/Animation Hitches avant/après ; test : `startMonitoring` ne lance aucun `Process` (runner injecté).

### GPU-4 — `AutomotiveGauge` : spring par échantillon sur 6 cadrans, arc non animable, blur · **P2** · S11
- **Preuve** : `AutomotiveGauge.swift:214`, `:227` (spring sur `fraction`) ; `CleanGaugeArcShape` (`:538-550`) sans `animatableData` → l'arc saute, le point (ombre `:225`) interpole et se détache ; glow `.blur(radius: 4)` (`:187-197`) ; ombre du cadran `:283-300` ; 6 instances (`DashboardView.swift:693-823`). Réduire les animations respecté. Non isolé en pass 2 (`PERFORMANCE_PASS2_FINAL_REPORT.md:40-46`).
- **Impact** : animation quasi continue du hero (commits CA jusqu'à 120 Hz), re-rastérisation blur/ombres par échantillon ; part du CPU Dashboard **non mesurée**.
- **Effort / risque** : M / faible.
- **Fichiers** : `Features/Dashboard/AutomotiveGauge.swift`, `DashboardView.swift`.
- **Correctif** : (a) supprimer le spring ou `easeOut(0.25)`, arc animable si conservé ; (b) glow statique ; (c) couches statiques isolées (`drawingGroup`/`compositingGroup`) ; (d) ne pas animer < 1 % de course.
- **Test de validation** : Instruments Core Animation FPS + SwiftUI : d'un flux continu à ~1 salve par échantillon ; `top` 60 s vs V0 (18,6 %) ; visuel : point collé à l'arc.

### GPU-5 — Backdrops behind-window empilés sous des dégradés à 84-92 % · **P3** (auditeur P2) · S34
- **Preuve** : `RootView.swift:258` + chaque onglet (`DashboardView.swift:116`, `StorageMapView.swift:93`, `CleanupView.swift:74`… 23 occurrences) ; Réglages ajoute une 3e couche (`SettingsView.swift:83`, sous-onglets conservés à opacité 0 `:73-79`) ; `MoraxTheme.swift:68-73` ; fenêtre forcée non opaque (`RootView.swift:608-615`) ; backdrop sidebar `:245`.
- **Impact** : 2-3 flous plein écran recalculés par WindowServer quand l'arrière-plan change ; gain visuel quasi nul. Coût côté WindowServer, non démontré dans le CPU de l'app.
- **Effort / risque** : S / faible.
- **Fichiers** : `RootView.swift`, `Core/DesignSystem/MoraxTheme.swift`, `DashboardView.swift`, `SettingsView.swift`.
- **Correctif** : un seul fond au niveau `RootView` ; `state: .followsWindowActiveState`. Remplacer par un fond opaque = décision produit.
- **Test de validation** : Instruments Core Animation « Color Offscreen-Rendered » : backdrops 2-3 → 1 ; CPU WindowServer avec une vidéo derrière la fenêtre.

### GPU-6 — HUD mode clair : matériau behind-window + opacité de groupe 0,94 · **P3** (auditeur P2) · S44
- **Preuve** : `MiniCockpitLiquidGlass.swift:139-153` (`.thinMaterial` sous dégradé blanc 0,80-0,94 ; la branche sombre `:113-114` l'évite déjà) ; `MiniCockpitHUDView.swift:94` (`.opacity(isHovered ? 1.0 : 0.94)`) ; panneau flottant, tous Spaces, non opaque (`MiniCockpitWindowController.swift:65-75`, `:155-168`).
- **Impact** : mode clair uniquement, petit panneau ; flou recalculé quand le contenu derrière change ; passe offscreen à chaque mise à jour.
- **Effort / risque** : S / faible.
- **Fichiers** : `MiniCockpit/MiniCockpitLiquidGlass.swift`, `MiniCockpit/MiniCockpitHUDView.swift`.
- **Correctif** : comme en sombre, sans matériau ; opacité appliquée au fond seulement.
- **Test de validation** : Core Animation « Offscreen-Rendered » / « Blended Layers » sur le HUD clair ; CPU WindowServer avec vidéo sous le HUD.

### GPU-7 — Mini Cockpit : poll 1 Hz, sparklines poussées sans contrôle · **P2** · S10
- **Preuve** : `MiniCockpitStateEngine.swift:419-431` (1 s contre une source à 1,5 s) ; branche `else` `:384-388` pousse dans `cpuSparkline`/`gpuSparkline` observés (`:285-286`) → points dupliqués ~1 fois sur 3 et invalidation chaque seconde ; en mode étendu tout le `body` est ré-évalué (`MiniCockpitHUDView.swift:378-410`) ; aucune pause occlusion/veille (grep vide).
- **Impact** : re-rendus 1 Hz que la détection de changement devait éviter ; historique faussé ; HUD actif même couvert ou écran verrouillé.
- **Effort / risque** : S / faible.
- **Fichiers** : `MiniCockpitStateEngine.swift`, `MiniCockpitHUDView.swift`, `MiniCockpitWindowController.swift`.
- **Correctif** : pousser seulement si `snapshot.timestamp` change ; observation au lieu du poll ; sous-vue dédiée aux sparklines ; pause sur `didChangeOcclusionState` et `screensDidSleep`.
- **Test de validation** : test : deux `updateMetrics` même timestamp → un seul point ; SwiftUI : évaluations du HUD/min en baisse ; app plein écran couvrant le HUD : wakeups stoppés (`top -stats idlew`).

### GPU-8 — Treemap : layout dans le `body`, Canvas de base redessiné au survol · **P2** · S20
- **Preuve** : `StorageMapView.swift:473-495` (`computeLayout` dans le `GeometryReader`) ; `TreemapCanvasView.swift:40-41`, `:69` (`hoverLocation` @State écrit à chaque mouvement), `:103-107` (lu pour l'infobulle) → closure du Canvas de base recréée, toutes les tuiles + textes redessinés (`:61-65`, `:162-199`), contrairement au commentaire `:59-60` ; hit-test linéaire (`:248-262`).
- **Impact** : clic ou survol = layout complet + redessin complet sur le main ; redessin continu pendant le déplacement du pointeur. Coût borné par `maxDepth`.
- **Effort / risque** : M / faible.
- **Fichiers** : `StorageMapView.swift`, `TreemapCanvasView.swift`, `StorageMap/TreemapLayoutEngine.swift`.
- **Correctif** : mémoïser le layout ; couche de base en sous-vue `Equatable` sans état de survol ; infobulle et surbrillance dans une vue sœur.
- **Test de validation** : Time Profiler + SwiftUI : au survol, `drawLeaves`/`drawContainers` ne sont plus appelés ; `computeLayout` absent sur simple sélection ; test de mémoïsation (même clé → même tableau).

### GPU-9 — Radar de scan Storage Map : 2 `repeatForever` + ombre · **P3** · S45
- **Preuve** : `StorageMapView.swift:1029-1086` (`easeInOut(1.6).repeatForever`, `linear(2.0).repeatForever`, `.shadow(radius: 8)` `:1072`), affiché pendant tout `isScanning` ; aucun `accessibilityReduceMotion` dans StorageMap.
- **Impact** : rafraîchissement plein régime pendant le scan (vue 100×100) ; marginal.
- **Effort / risque** : S / faible.
- **Fichiers** : `Features/StorageMap/StorageMapView.swift`.
- **Correctif** : `ProgressView` système ou `TimelineView` à 30 fps ; sans ombre ; respecter Réduire les animations.
- **Test de validation** : Core Animation FPS pendant un scan ; durée du scan d'un même dossier avant/après.

### GPU-10 — ~30 ombres décoratives sur des éléments rafraîchis · **P3** · S46
- **Preuve** : `AutomotiveGauge.swift:225`, `:295` ; `NetworkTelemetryCard.swift:43`, `:210`, `:241` ; `TopAppsTelemetryCards.swift:152`, `:311`, `:468` ; `DashboardView.swift:243`, `:1133-1300` ; `MoraxTheme.swift:229-236`.
- **Impact** : non mesuré ; la revue note que les ombres SwiftUI passent par le renderer display-list/Metal, pas par des passes offscreen CALayer, et que la plupart des lignes changent toutes les 5 s.
- **Effort / risque** : S / faible.
- **Fichiers** : `NetworkTelemetryCard.swift`, `TopAppsTelemetryCards.swift`, `DashboardView.swift`, `MoraxTheme.swift`.
- **Correctif** : finition optionnelle après GPU-4 (retirer les lueurs ≤ 3 px).
- **Test de validation** : « Color Offscreen-Rendered » avant/après ; CPU WindowServer + app 60 s.

## Ajouts de la revue

- `MoraxMenuBarLabel` lit tout `currentSnapshot` (`MoraxMenuBarView.swift:50-100`) : l'élément de barre d'état est re-rendu toutes les 1,5 s même si la chaîne « CPU %.0f%% » ne change pas. C'est le cas toujours visible derrière GPU-2 ; publier des valeurs quantifiées pour le label.
- `WindowLiquidGlassConfigurator.updateNSView` planifie un `DispatchQueue.main.async` à chaque mise à jour de `RootView` (`RootView.swift:600-606`) — mineur, à traiter avec GPU-5.
- `getDiskVolumes` est appelé dans la boucle macmon sur le MainActor (`SystemMetricsService.swift:661`, `:740-780`) : un NAS figé bloque à la fois le main et le flux de télémétrie. Exclure les volumes non locaux ; la barre de menus n'utilise que `diskVolumes.first` (`MoraxMenuBarView.swift:96`). Voir S36.
