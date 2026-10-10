# SECURITY_PRIVACY_AUDIT — Morax Garage

Date : 2026-09-28. Branche `audit/system-audit-2026-09`, commit `6fe676e`. Audit en lecture seule, sans modification de code.
Sources : dimensions `security`, `reliability` (volet sûreté des données) et `dependencies` (volet supply chain) de l'audit système, avec les verdicts du relecteur contradictoire. Les sévérités affichées sont les **sévérités ajustées** ; aucun constat n'a été réfuté dans ces trois dimensions. Contexte : [ARCHITECTURE_MAP.md](ARCHITECTURE_MAP.md) §6-7, [BASELINE_V0.md](BASELINE_V0.md).

Échelle : P1 = à corriger avant le prochain usage réel de la fonction concernée ; P2 = prochain lot ; P3 = hygiène.

## Synthèse

La base est saine :
- les secrets sont dans le trousseau de session, jamais en clair, en UserDefaults ou dans l'historique git ;
- tous les `Process` utilisent un tableau d'arguments et un exécutable absolu : pas de `/bin/sh -c`, pas d'injection d'option rsync ;
- les suppressions passent uniquement par `FileManager.trashItem`, derrière `SafetyGate` ;
- ATS n'est pas assoupli, les sessions réseau sont éphémères, aucun port n'est en écoute.

Le risque dominant n'est pas une faille exploitable à distance. C'est la **surface de l'accès complet au disque (FDA)** : une app signée ad hoc, sans hardened runtime, qui lance automatiquement des binaires résolus depuis des dossiers inscriptibles par l'utilisateur. Le relecteur a rétrogradé ces points parce qu'un attaquant local qui tourne sous le compte a d'autres chemins. Côté données, le seul P1 concerne l'intégrité : PhotoSync peut annoncer à tort qu'un SSD est libérable.

| ID | Sév. | Sujet | Effort |
|---|---|---|---|
| REL-1 | **P1** | PhotoSync : une empreinte tronquée donne un faux « synced » / « readyToFreeSSD » | S |
| SEC-1 | P2 | App ad hoc sans hardened runtime alors qu'elle détient FDA | S (décision) |
| REL-2 | P2 | `ProcessRunner.run` : interblocage de pipe, pas d'escalade SIGKILL | M |
| REL-6 | P2 | Historique de télémétrie écrasé après un échec de décodage ; deux écrivains | M |
| DEP-1 | P2 | Contrainte SwiftTerm `from: "1.0.7"` (Package.resolved désormais suivi) | S |
| DEP-2 | P2 | Les shaders Metal de SwiftTerm imposent le toolchain Metal à tout build | M (décision) |
| SEC-2..8, REL-5/8/9, DEP-3/10, ajouts relecteur | P3 | Voir détail | S-M |

---

## 1. Décisions à prendre par le propriétaire

Ces points ne sont pas des correctifs de code. Ils engagent un coût, un compte ou un choix produit, donc rien n'a été changé.

### D1 — Identité de signature (SEC-1, SEC-7)
- **État (mis à jour 2026-10-08)** : Compte individuel Apple Developer Program payant actif (Team ID : **NU43RNA6U9**). `scripts/install.sh` a été corrigé pour utiliser `MORAX_SIGN_IDENTITY` avec hardened runtime (`--options runtime --timestamp`) et ne plus écraser systématiquement la signature avec `--sign -`. Les builds sur machine sont valables **1 an** (au lieu de 7 jours).
- **Conséquence** : les autorisations TCC (FDA) et les ACL du trousseau restent stables dès qu'une identité de développement ou Developer ID (NU43RNA6U9) est spécifiée.
- **Configuration** : `Config/Signing.xcconfig` centralise `DEVELOPMENT_TEAM = NU43RNA6U9` et `CODE_SIGN_STYLE = Automatic`.

### D2 — Hardened runtime (SEC-1, P2)
- **État (mis à jour 2026-10-08)** : `--options runtime` et `--timestamp` sont désormais appliqués automatiquement dans `build_app.sh` et `install.sh` dès qu'une identité de signature est fournie via `MORAX_SIGN_IDENTITY`.

### D3 — Notarisation
- **État (mis à jour 2026-10-08)** : Débloquée. Le compte payant NU43RNA6U9 permet de configurer `xcrun notarytool store-credentials morax-notary` et de signer en `Developer ID Application`. Le pipeline `scripts/package_release.sh` automatise le packaging DMG, la soumission `notarytool`, le stapling du ticket et la vérification Gatekeeper.

### D4 — Terminal intégré avec FDA (SEC-3, P3)
`TerminalView.swift:117-124` lance `$SHELL -l` avec tout l'environnement de l'app, comme enfant de Morax Garage. Toute commande tapée ou collée hérite donc de l'attribution FDA. C'est équivalent à accorder FDA à Terminal/iTerm. Options :
- (a) garder et **étiqueter** l'onglet « shell avec accès complet au disque » (coût quasi nul) ;
- (b) retirer SwiftTerm, ce qui règle aussi DEP-2, DEP-3 et REL-10 ;
- (c) lancer le shell comme processus responsable séparé. À éviter : cela passe par une SPI privée ou `launchctl asuser`, donc de la complexité et du risque.

### D5 — SwiftTerm : garder, vendorer ou retirer (DEP-2, P2)
Détail au §4. C'est un choix produit : retirer SwiftTerm supprime la dépendance au toolchain Metal, un crash connu (DEP-3) et la surface D4, mais fait perdre le terminal intégré.

### D6 — Identifiants d'infrastructure dans le dépôt (SEC-8, P3)
L'hôte tailnet `<your-usage-cockpit-host>` (`AppSettings.swift:351-352`) et les IDs projet/équipe Meta (`MetaMuseModels.swift:191-192`) sont commités. Ce ne sont pas des secrets : l'hôte n'est joignable que depuis le tailnet. Décision à prendre seulement si le dépôt doit devenir public : dans ce cas, valeurs par défaut vides et config git-ignorée.

---

## 2. Sûreté des données (fiabilité)

### REL-1 — P1 — PhotoSync peut déclarer une copie complète à partir d'une empreinte tronquée
- **Preuve** :
  - `PhotoSyncScanner.swift:105-107` : l'errorHandler de l'énumérateur logue puis `return true` ;
  - `:117` : `try? resourceValues … else { continue }` ;
  - `:129` : l'empreinte est renvoyée sans compteur d'erreurs ;
  - `:135-145` : `compare()` ne parcourt que `reference.files`, donc une source tronquée devient `.synced` ;
  - `PhotoSyncModels.swift:140-148` : `stage()` renvoie alors `.readyToFreeSSD` ;
  - `PhotoSyncStateService.swift:313-322` : `completeJob` s'appuie sur la même empreinte.
- **Impact** : un sous-dossier illisible ou une erreur d'E/S sur le SSD suffit pour que le badge « Libérables du SSD » (`PhotoSyncView.swift:117`) invite à effacer des RAW non archivés. L'app ne supprime rien elle-même, mais ce badge est la promesse de sûreté du produit.
- **Correctif** : ajouter `errorCount`/`isComplete` à `FolderFingerprint`, revérifier le volume (`st_dev`) après le parcours, et ajouter un statut `.unverifiable` qui ramène `stage()` à `.unknown`. Même règle dans `completeJob`.
- **Validation** : test avec un sous-dossier `chmod 000` dans la source, dont le résultat attendu est `.unverifiable` et non `.synced`.

### REL-2 — P2 — `ProcessRunner.run` peut rester bloqué indéfiniment
- **Preuve** : `ProcessRunner.swift:140-143` ne lit stdout/stderr que dans `terminationHandler`, donc un enfant qui dépasse environ 64 Ko bloque en `write()`. Au timeout ou à l'annulation, seul `terminate()` (SIGTERM) est envoyé (`:165-173`, `:186-191`), et le groupe de tâches attend une continuation qui ne reprend qu'à la terminaison.
- **Ajout du relecteur** : un petit-enfant qui hérite du pipe (brew pendant son auto-update) bloque aussi la lecture.
- **Impact** : spinner infini ou faux timeout (`brew outdated --json=v2` avec des centaines de paquets). La sûreté est en jeu parce que `ollama rm` (`AIModelUninstaller.swift:110`) passe par ce chemin.
- **Correctif** : vider les pipes au fil de l'eau, envoyer SIGTERM puis SIGKILL après 2 s, reprendre la continuation une seule fois même sans terminaison, et plafonner la taille de sortie. Ce correctif couvre aussi DEP-9 et REL-3.

### REL-6 — P2 — Perte silencieuse de l'historique de télémétrie
- **Preuve** : `TelemetryHistoryStore.swift:159-166` met en cache un fichier **vide** quand le décodage échoue (le log annonce pourtant « existing file retained »). L'`append()` suivant (`:170-173`, `:209-214`) écrase 30 jours d'historique. Deux processus écrivent le même fichier, l'app et le helper `MoraxCockpitMenu`, chacun avec son cache statique jamais revalidé (`:136`, `:146-149`).
- **Correctif** : renommer le fichier corrompu en `*.corrupt-<ts>.json` avant toute écriture, garder un seul écrivain (l'app principale) ou poser un `flock()` sur un fichier verrou annexe, et encoder hors du MainActor.

### REL-5 + ajout relecteur — P3 — File PhotoSync bloquée sur un partage SMB figé
- `PhotoSyncStateService.swift:281-302` n'a pas de chien de garde d'inactivité sur rsync, et l'annulation n'envoie que SIGTERM. L'utilisateur peut débloquer la file via `cancelJob` (`:243-249`).
- **Plus grave, relevé par le relecteur** : `reverify` et `scan` (`:341-349`) parcourent le NAS via SMB sans timeout, dans un `Task.detached`. Si le partage se fige, `completeJob` ne se termine jamais et même l'annulation laisse la file en reverify.
- **Correctif** : timeout et contrôle de disponibilité du volume autour de `reverify`, observation de `NSWorkspace.didUnmountNotification`, et escalade SIGKILL (REL-2).

### REL-8 — P3 — Écritures de cache dans le désordre, erreurs avalées
`CachedScanStore.swift:90-97` lance un `Task.detached` par sauvegarde : le verrou (`:181-188`) sérialise les écritures mais pas leur ordre. `:178-180` et `StorageMapStateService.swift:205-206,216-217` contiennent un `catch` vide (« handled silently »), contraire à la règle « ne jamais avaler une erreur ». Correctif : un acteur série par fichier avec un numéro de génération, un log des échecs, et déplacer de côté un fichier indécodable avant de le réécrire.

### REL-9 / AIO-9 — P3 — Le polling Higgsfield modifie la configuration du CLI
`HiggsfieldCreditService.swift:280-289` lance `workspace set <id>` à chaque rafraîchissement (toutes les 300 s), et en choisit un sans le dire si aucun n'est sélectionné. Le résultat est ignoré (`_ = try?`). C'est un effet de bord persistant sur l'outil de l'utilisateur, déclenché par un chemin censé être en lecture seule, qui peut facturer un autre workspace. Correctif : ne jamais faire de `set` depuis le polling. `setWorkspace(id:)` explicite existe déjà (`:402-412`).

### REL-10 — P3 — Terminal mort après `exit`
Il n'y a pas de `processDelegate` (`TerminalView.swift:108-127`) : les boutons rapides écrivent alors dans un pty mort. Implémenter `processTerminated` suffit. Voir aussi D4 et D5.

---

## 3. Sécurité applicative

### SEC-2 + ajout relecteur — P3 — Résolution des binaires lancés automatiquement
- `ToolRegistry.swift:41-43,60` place en tête `~/Library/Application Support/Morax Garage/bin`, que rien ne remplit, puis `/opt/homebrew/bin`, `~/.local/bin`, `~/.cargo/bin`, `~/.npm-global/bin` et `$PATH`, y compris ses entrées relatives (`:62-77`). macmon, brew, hf et muse y sont résolus et lancés sans action de l'utilisateur, avec l'attribution FDA.
- **Cause racine selon le relecteur** : tous ces dossiers sont inscriptibles par l'utilisateur, donc réordonner la liste ne ferme rien.
- **Correctif utile** : épingler `macmon` sur son chemin Cellar Homebrew et le vérifier (hash enregistré ou `codesign`), supprimer le dossier géré (code mort), ignorer les entrées `PATH` non absolues. Voir aussi DEP-10.

### SEC-4 — P3 — Le bouton « Quick Look Preview » ouvre ou exécute le fichier
`StorageMapInspectorView.swift:210-213` → `quickLook()` → `NSWorkspace.shared.open(node.url)` (`:574-577`). Sur un `.command`, `.app` ou `.pkg`, cela lance le fichier au lieu de l'afficher. Correctif : `QLPreviewPanel`, ou renommer le bouton « Ouvrir » et refuser les UTI exécutables. C'est surtout un bug d'UX : il faut un clic et Gatekeeper protège les fichiers en quarantaine.

### SEC-5 — P3 — Le confinement `scanRoot` de SafetyGate n'est jamais activé
`SafetyGate.swift:249-258` ne vérifie le confinement que `if let scanRoot`, et tous les appelants de production passent `nil` (`CleanupStateService.swift:594`, `AIModelUninstaller.swift:181`, `CleanupStagingService.swift:40`). Le relecteur note que `trashItem` sur un lien symbolique déplace le lien et non sa cible, donc le danger est limité. Durcissement utile : entrées de denylist par préfixe pour `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.kube` et `~/Library/Cookies` (`SafetyGate.swift:100-105` ne protège que les dossiers eux-mêmes), et passer la racine du scanner jusqu'à `trashBatch`.

### SEC-6 — P3 — Clé interne envoyée sans contrôle https
`AppSettings.swift:255-257` accepte n'importe quelle URL, et `UsageQuotaService.swift:93-95` y pose `X-Internal-Key`. Les redirections gardent l'en-tête, et le test de connexion utilise `URLSession.shared` (`GeneralSettingsView.swift:180-188`). Correctif : accepter uniquement `https`, retirer l'en-tête sur une redirection vers une autre origine, et passer le test par la session éphémère.

### SEC-7 — P3 — Trousseau
`KeychainSecret.swift:15` ne pose ni `kSecUseDataProtectionKeychain` ni `kSecAttrAccessible`. `GeneralSettingsView.swift:15,17` lit les deux secrets, dont la clé admin OpenAI de portée organisation, dans des initialiseurs `@State`. Correctif peu coûteux : charger les secrets dans `.task` et afficher un masque. La migration vers le trousseau data-protection demande un chemin de migration : faible gain, à différer. Les invites répétées disparaissent avec D1.

### SEC-8 / AIO-8 — P3 — Vie privée dans les logs
- `PhotoSyncScanner.swift:106` et `PhotoSyncStateService.swift:297` loguent des chemins clients et des lignes rsync en `privacy: .public`.
- `OperationLog.swift:81-107` écrit des chemins absolus sans rotation : `pruneOlderThan` (`:139`) n'a aucun appelant. Un nom de fichier contenant `\n` peut forger une ligne de log.
- **Correctif** : `.private(mask: .hash)`, prune au lancement, échappement de `\n` dans `formattedLine`.

---

## 4. Dépendances et supply chain

### DEP-1 — P2 — Version de SwiftTerm non contrainte
- **Déjà corrigé depuis l'audit** : `Package.resolved` est suivi par git (`6fe676e`) et épingle SwiftTerm 1.18.0 (rev `7691f85b`).
- **Reste à faire** : `Package.swift:15` déclare toujours `from: "1.0.7"` (toute version < 2.0.0). Un `swift package update` passerait en 1.20.0 sans revue, soit environ 1 300 lignes modifiées. Passer à `.upToNextMinor(from:)` ou `exact:` pour que chaque montée de version soit un choix explicite.

### DEP-2 — P2 — Toolchain Metal exigé pour un renderer jamais utilisé (décision D5)
SwiftTerm compile `Apple/Metal/Shaders.metal` (`.build/checkouts/SwiftTerm/Package.swift:88-90`), alors que `useMetalRenderer = false` n'est jamais activé par l'app (`MacTerminalView.swift:219`). BASELINE_V0.md:62 documente un échec de `swift test` : le relecteur l'attribue à un chemin de cryptex figé dans `.build`, pas à un toolchain absent. Options par ordre de préférence :
- (a) retirer SwiftTerm ;
- (b) vendorer SwiftTerm sans Metal ;
- (c) court terme : dans `release-preflight.sh`, vérifier `xcrun -f metal` et renvoyer vers `xcodebuild -downloadComponent MetalToolchain` en cas d'échec.

### DEP-3 — P3 — Crash connu dans SwiftTerm 1.18.0
Force-unwrap `newData!` sur un payload DECRQSS non ASCII (`Terminal.swift:1118`). Le terminal tourne dans le processus principal, donc **toute l'app** quitte. Corrigé par `a4916989` (v1.19.0+). Le déclenchement demande une sortie hostile dans le terminal intégré. À traiter avec DEP-1 : passage délibéré à 1.20.0 épinglé, revue du diff `Mac/` et smoke test du terminal. Aucune mise à jour aveugle.

### Ajout relecteur — P3 — macmon : dépendance runtime critique non épinglée
`SystemMetricsService.swift:427` résout macmon à chaque démarrage de boucle, sans contrôle de version ni de schéma JSON. macmon n'est vérifié ni dans `build_app.sh` ni dans `release-preflight.sh`. Un `brew upgrade macmon` qui change le format de `macmon pipe` dégrade silencieusement toute la télémétrie (lignes comptées corrompues, puis backoff). Correctif : contrôle de version dans `ToolRegistry.detect` (`:150-157`) et test de parsing sur un échantillon figé. Cela recoupe SEC-2 (épinglage du chemin).

### DEP-10 — P3 — Résolution d'outils incohérente
`GeneralSettingsView.swift:1087-1109` code en dur les chemins brew/mo. `AIModelUninstaller.swift:51-55` a sa propre liste ollama, qui ignore `/Applications/Ollama.app/Contents/Resources/ollama` et ToolRegistry. Correctif : tout faire passer par `ToolRegistry` et ignorer les entrées `PATH` relatives.

### Hors périmètre sécurité, pour mémoire
DEP-6 (binaires non strippés : 37,3 Mo contre 15,6 Mo) et DEP-11 (tranche x86_64 compilée à chaque build) n'ont pas d'impact sécurité. Ils sont traités dans le plan de performance.

---

## 5. Ordre de traitement recommandé

1. **REL-1** : statut `.unverifiable` dans PhotoSync (S, P1).
2. **D2** : `--options runtime` dans `build_app.sh` et `install.sh`, et `install.sh` qui respecte `MORAX_SIGN_IDENTITY` (S, après smoke test).
3. **REL-2** : `ProcessRunner` (vidage des pipes, SIGKILL, reprise unique), ce qui couvre DEP-9, REL-3 et une partie de REL-5 (M).
4. **REL-6** : fichier corrompu mis de côté et écrivain unique (M).
5. **REL-9**, **SEC-6**, **SEC-4**, **SEC-8** (logs), **DEP-1** (contrainte) : lot de petits correctifs S.
6. Décisions propriétaire **D1**, **D4**, **D5**, puis selon le choix DEP-2/DEP-3.

Chaque correctif doit arriver avec le test de validation décrit dans son constat (règle projet : un test qui échoue sans le correctif).
