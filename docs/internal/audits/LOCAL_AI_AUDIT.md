# LOCAL_AI_AUDIT — Morax Garage

Date : 2026-09-28. Branche `audit/system-audit-2026-09`. Audit en lecture seule.
Source : dimension `ai_observability` de l'audit système, avec les verdicts du relecteur. Les sévérités sont les **sévérités ajustées**. Contexte : [ARCHITECTURE_MAP.md](ARCHITECTURE_MAP.md) §9, [BASELINE_V0.md](BASELINE_V0.md) §« Fonctions IA ».

## 1. Constat principal : l'app ne fait aucune inférence

Morax Garage n'exécute aucun modèle. Il n'y a ni CoreML, ni MLX, ni llama.cpp, ni client HTTP vers `localhost:11434`. Une recherche de `11434|api/ps|lmstudio|mlx|llama|tokens/s|MLModel|coreml` dans `Sources/` ne trouve aucun client de runtime (AIO-5).

Les métriques suivantes sont donc **non applicables** à l'app. Elles n'ont pas été mesurées et ne doivent pas figurer dans un benchmark de Morax Garage :

| Métrique | Statut |
|---|---|
| Temps de chargement du modèle | N/A : aucun modèle chargé |
| TTFT (time to first token) | N/A |
| Tokens/s (prefill, génération) | N/A |
| Taille et occupation du KV cache | N/A |
| Taux de succès des appels d'outils, erreurs, retries d'inférence | N/A : aucun agent ni outil LLM dans l'app |

Même si l'app observait un runtime, `eval_count` et `eval_duration` ne sont renvoyés par Ollama qu'à l'appelant de la requête. Les tokens/s d'un autre client ne sont **pas observables passivement** sans proxy, et aucun proxy n'est recommandé.

## 2. Ce que l'app observe réellement

| Domaine | Mécanisme | Preuve |
|---|---|---|
| Inventaire disque des modèles | Ollama (`~/.ollama/models` manifests + blobs), Hugging Face (`~/.cache/huggingface/hub`), LM Studio (`~/.lmstudio/models`, `~/.cache/lm-studio/models`) | `AIModelScanner.swift:17-23,28,122,153-154` |
| Fraîcheur de l'inventaire | Cache avec TTL de 24 h, conforme à la règle « servi depuis le cache » | `CachedScanStore.swift:26`, `AIModelsStateService.swift:75-76` |
| Désinstallation | `ollama rm`, ou la Corbeille en repli, derrière `SafetyGate` | `AIModelUninstaller.swift:100-150,181` |
| Dépense OpenAI facturée | `GET /v1/organization/costs` avec une clé admin (trousseau), poll toutes les 5 min, jusqu'à 10 pages | `OpenAICostsService.swift:19,57-58,96-99` |
| Quotas Claude / Codex | Flux NAS `{base}/api/usage/quotas`, `X-Internal-Key`, session éphémère, timeout de 8 s | `UsageQuotaService.swift:57-58,92-99` |
| Crédits Higgsfield | CLI `higgsfield account status --json` toutes les 300 s | `HiggsfieldCreditService.swift:14-27,142` |
| Meta Muse | Pourcentage saisi à la main (`@AppStorage`) ; le service automatique est du code mort | `MetaMuseCreditCard.swift:12-13` |
| Télémétrie système utile à l'IA | macmon (CPU, GPU, RAM, swap, températures, puissance dont l'ANE), `ps` toutes les 5 s, temps GPU par processus via IOKit | `MacmonModels.swift:19-23,66-70`, `ProcessResourceService.swift:349-350`, `GpuProcessSampler.swift:32-60` |

Rien n'observe un runtime **en cours d'exécution** : processus Ollama ou LM Studio, modèle chargé, `size_vram`, `expires_at` du keep-alive.

## 3. Constats (sévérité ajustée)

| ID | Sév. | Constat | Effort |
|---|---|---|---|
| AIO-1 | P2 | Les flux lents (quotas, OpenAI, Higgsfield) refont un appel à chaque redémarrage, sans contrôle de fraîcheur ; le snapshot Higgsfield n'est jamais persisté | S |
| AIO-2 | P2 | Le consommateur `"dashboard"` a deux propriétaires aux ensembles de flux différents | S |
| AIO-3 | P2 | `/bin/ps` synchrone et parcours IOKit sur le MainActor à l'init et à chaque démarrage, puis un 2ᵉ `ps` immédiat | S |
| AIO-5 | P3 | Aucune observation des runtimes IA en cours (disque seulement) | M |
| AIO-6 | P3 | Mémoire GPU unifiée et empreinte réelle des runners LLM non mesurées (RSS au lieu de `phys_footprint`) | S |
| AIO-8 | P3 | Logging fragmenté : 2 subsystems, aucun signpost, chemins en `.public` | S |
| AIO-9 | P3 | Le polling Higgsfield modifie le workspace du CLI (jusqu'à 3 processus par poll) | S |
| AIO-4 | P3 | `MetaMuseService` : environ 360 lignes de code mort au design lourd | S |
| Relecteur | P3 | Le « backoff » de `UsageQuotaService` **accélère** le polling après un échec | S |
| Relecteur | P3 | `HiggsfieldCreditService.updateInterval(_:)` casse la boucle de polling (code mort) | S |
| AIO-7 | — | Recommandation de routage : classée hors périmètre (pas un défaut). Traitée séparément dans [MODEL_ROUTING_RECOMMENDATIONS.md](MODEL_ROUTING_RECOMMENDATIONS.md) | — |

### AIO-1 — P2 — Appels répétés au retour sur le dashboard
- **Preuve** : `TelemetryCoordinator.swift:60` arrête un flux 5 s après le départ de son dernier consommateur. Au redémarrage, `refresh()` est appelé tout de suite sans regarder `capturedAt` : `UsageQuotaService.swift:79-80`, `OpenAICostsService.swift:57-58`, `HiggsfieldCreditService.swift:72-74`. Le dossier Higgsfield ne persiste rien (`:42`).
- **Nuance du relecteur** : quand le Mini Cockpit est visible, il garde `.usage` et `.openAICosts` (`MiniCockpitStateEngine.swift:409-416`). Le vrai coût est le lancement du CLI Higgsfield à chaque retour sur le dashboard après plus de 5 s.
- **Correctif** : `firstDelay = max(0, pollingInterval - (now - lastCapturedAt))` avant le premier rafraîchissement, en gardant le bouton manuel. Persister le snapshot Higgsfield en JSON dans Application Support.
- **Validation** : horloge injectée et faux exécuteur. Démarrer, arrêter, redémarrer en moins de 60 s doit donner 1 appel réseau et 1 lancement de CLI, pas 2.

### AIO-2 — P2 — Deux propriétaires pour `"dashboard"`
- **Preuve** : `RootView.swift:282-286` acquiert `[.system,.network,.process]`, `DashboardView.swift:133-139` acquiert le même ID avec `.usage/.openAICosts/.higgsfield`, et `acquire` remplace la demande précédente (`TelemetryCoordinator.swift:96-104`).
- **Impact** : la course est réelle au lancement, car l'ordre des `onAppear` parent/enfant n'est pas garanti ; Higgsfield peut alors ne jamais démarrer. Il manque aussi un `onChange` pour `showUsageQuotas`/`showHiggsfieldGauge`, et `DashboardView` n'a pas d'`onDisappear` (relecteur).
- **Correctif** : un seul propriétaire (`DashboardView`), responsable aussi de la libération.

### AIO-3 — P2 — `ps` synchrone sur le main thread
- **Preuve** : `ProcessResourceService.swift:233-236` (init) et `:238-245` (`startMonitoring`) appellent `sampleImmediate()`, qui exécute `executePs()` (`:347-362` : `readDataToEndOfFile` puis `waitUntilExit`) et `GpuProcessSampler.collectRawEntries()` sur le MainActor. La boucle détachée relance `ps` aussitôt.
- **Correctif** : supprimer `sampleImmediate()` et laisser la tâche détachée produire le premier snapshot (S). À plus long terme, remplacer `ps` par `proc_listallpids` + `proc_pid_rusage(RUSAGE_INFO_V4)`, ce qui donne aussi `ri_phys_footprint` (voir AIO-6).

### AIO-5 — P3 — Pas de visibilité sur un modèle chargé en mémoire
- **Constat** : l'app ne voit pas qu'Ollama garde un modèle de 17-19 Go en mémoire unifiée (keep-alive). Sur cette machine de 32 Go, c'est la cause la plus probable de pression mémoire quand un modèle a servi récemment (voir l'inventaire dans MODEL_ROUTING_RECOMMENDATIONS.md).
- **Avis du relecteur** : c'est une demande de fonctionnalité, pas un défaut. Elle va au backlog, pas en P2.

### AIO-6 — P3 — Mesure mémoire imprécise pour les runners LLM
`NativeGpuSampler.swift:29-62` ne lit que l'utilisation GPU. Le même dictionnaire `PerformanceStatistics` expose probablement `In use system memory`, mais cette présence sur toutes les générations AGX **n'est pas vérifiée**. La RAM par processus vient de la RSS de `ps` (`ProcessResourceService.swift:349-350,153`), mesure médiocre pour les allocations Metal.

### AIO-8 — P3 — Observabilité interne
- **Preuve** : deux subsystems, `com.morax.cockpit` (`TelemetryLogger.swift:5-7`) et `com.morax.garage` (`TelemetryHistoryStore.swift:138`), pour le bundle ID `com.morax.garage`. Seuls 9 fichiers Swift sur 120 loguent. Il n'y a aucun `OSSignposter`. Les échecs de polling (`UsageQuotaService.swift:108-113`, Higgsfield) n'atteignent que l'état de l'UI.
- **Impact** : impossible de filtrer toute l'app avec un seul prédicat `log stream`, ni de mesurer le coût des scans dans Instruments.

### AIO-9 — P3 — Effet de bord du polling Higgsfield
`HiggsfieldCreditService.swift:141-155,256,287` : `workspace list` puis `workspace set <id>`, dont le résultat est ignoré, lancés depuis la boucle de 5 min. La logique de repli « stale » est copiée 4 fois (`:125-137`, `:201-211`, `:220-230`, `:236-246`). Voir aussi REL-9 dans SECURITY_PRIVACY_AUDIT.md.

### Ajouts du relecteur (P3)
- `UsageQuotaService.swift:62-64` : `nextPollInterval = min(900, 2^n*5)` donne 10, 20, 40, 80 puis 160 s, **plus court** que l'intervalle normal de 300 s. Quand l'endpoint tombe, l'app envoie environ 5 requêtes supplémentaires en 5 min. Correctif : `max(pollingInterval, …)` avec du jitter.
- `HiggsfieldCreditService.swift:88-98` : `updateInterval(_:)` remplace la boucle par un sommeil suivi d'un seul rafraîchissement, donc le polling s'arrête alors que `isRunning` reste vrai. Aucun appelant : à supprimer.
- `HiggsfieldCreditService.swift:125-137` : quand le CLI est absent, chaque poll réécrit l'état avec une nouvelle struct, ce qui invalide le dashboard (`@Observable`) sans changement réel.

## 4. Lacunes d'observabilité

1. **Runtimes locaux** : ni processus, ni modèle chargé, ni occupation VRAM ou mémoire unifiée, ni expiration du keep-alive.
2. **Mémoire** : les runners Metal sont mesurés en RSS plutôt qu'en `phys_footprint`, et la mémoire GPU n'est pas exposée.
3. **Coûts et quotas** : fraîcheur non respectée au redémarrage (AIO-1), backoff inversé, échecs non journalisés, snapshot Higgsfield volatil.
4. **Instrumentation** : aucun signpost, subsystems éclatés, pas de compteur d'échecs ou de retries par flux dans les logs.
5. **Performance de l'inférence** : hors de portée de l'app par construction (§1). Elle ne peut se mesurer que côté client, avec le banc décrit dans MODEL_ROUTING_RECOMMENDATIONS.md §5.

## 5. Recommandations et coûts

Coûts : **effort** de développement (S < ½ j, M ≈ 1-2 j) et **coût runtime**, estimé et non mesuré, à valider avec `scripts/bench/bench_runtime.sh` avant/après.

| # | Recommandation | Constats | Effort | Coût runtime | Priorité |
|---|---|---|---|---|---|
| R1 | Contrôle de fraîcheur au démarrage de chaque flux lent, snapshot Higgsfield persisté | AIO-1 | S | Négatif : supprime des appels réseau et des lancements de CLI | 1 |
| R2 | Un seul propriétaire de `"dashboard"` (acquisition et libération), plus `onChange` sur les réglages | AIO-2 | S | Nul | 1 |
| R3 | Supprimer `sampleImmediate()` | AIO-3 | S | Négatif : 1 `ps` de moins par démarrage, main thread libéré | 1 |
| R4 | Corriger le backoff (`max(pollingInterval, …)` + jitter) ; supprimer `updateInterval` | Relecteur | S | Négatif en cas de panne | 2 |
| R5 | Plus aucun `workspace set` dans le polling ; factoriser le repli stale | AIO-9 | S | Négatif : jusqu'à 2 processus de moins par poll | 2 |
| R6 | Un seul subsystem (le bundle ID) et des catégories par domaine ; `.error` avec `failureCount` dans chaque `catch` de poll ; chemins en `.private(mask: .hash)` ; `OSSignposter` autour des scans | AIO-8 | S | Quasi nul : signposts gratuits hors enregistrement | 2 |
| R7 | Supprimer `MetaMuseService`, `MuseExportRunner`, le flux `.metaMuse` et leurs tests ; garder la saisie manuelle | AIO-4 | S | Nul (code mort) | 3 |
| R8 | Lire `In use system memory` dans le même appel IORegistry, **après vérification** sur M1 Max ; `ri_phys_footprint` pour le top N | AIO-6 | S | Quasi nul | 3 |
| R9 | *Backlog, décision propriétaire* : flux `.localAI` à la demande (voir ci-dessous) | AIO-5 | M | < 0,1 % CPU visé, **à mesurer** ; 0 requête sans runtime détecté | 4 |

Détail de R9, si elle est retenue :
- le flux n'est acquis que par l'onglet Modèles IA ou une carte du dashboard ;
- (1) détecter les runtimes dans la sortie `ps` déjà collectée (`ollama`, `llama-server`, LM Studio, `python` avec un argument `mlx`), sans nouveau processus ;
- (2) seulement si un runtime est présent, envoyer `GET http://127.0.0.1:11434/api/ps` (`name`, `size`, `size_vram`, `expires_at`) avec un timeout de 1 s toutes les 15 s, via une session éphémère ;
- (3) afficher explicitement que les tokens/s ne sont pas observables passivement.

Validation : stub `URLProtocol` pour `/api/ps`, fixture `ps` qui contient `ollama`, `top` sur 60 s avec et sans le flux actif.

Ne **pas** ajouter : de proxy d'inférence, de benchmark intégré qui charge des modèles, ni de polling de `/api/ps` en permanence. Ces trois choix contrediraient le budget CPU/RAM du produit.
