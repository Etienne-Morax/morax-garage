# Morax Garage — Product Validation Gate

Cette checklist est versionnée avec le produit. Chaque ligne doit porter un statut explicite :
`PASS`, `FAIL`, `BLOCKED` ou `NOT TESTED`, ainsi qu'une preuve datée lorsqu'elle est exécutée.
Un build ou une suite de tests verte ne vaut pas validation runtime, UI ou distribution.

## Automated

| Contrôle | Statut baseline 2026-08-21 | Preuve / commande |
| --- | --- | --- |
| Build debug principal | PASS | `swift build --product MoraxCockpit` — 2026-08-21 |
| Build debug menu bar | PASS | `swift build --product MoraxCockpitMenu` — 2026-08-21 |
| Build release principal et menu bar | PASS | `swift build -c release --product ...` — arm64, 2026-08-21 |
| Tests unitaires et intégration | PASS | `swift test` — 162 tests, 0 échec, 31.8 s — 2026-08-21 |
| Architecture arm64 | PASS | binaire Release vérifié avec `file` — 2026-08-21 |
| Architecture x86_64 | PASS | `swift build -c release --triple x86_64-apple-macosx14.0 --product ...` — 2026-08-21 |
| Bundle universal | PASS | `scripts/build_app.sh`, `lipo -archs` → `x86_64 arm64` — 2026-08-21 |
| Ressources SwiftPM | PASS | 4 resource bundles embarqués dans `dist` — 2026-08-21 |
| Chemins destructifs produit | PASS | `SafetyGate`/`TrashService` inchangés pour le produit ; audit scripts effectué |
| Tests safety symlink/TOCTOU/limites | PASS | `SafetyGateTests`, `TrashServiceTests` |

## Runtime

| Scénario | Statut | Preuve attendue |
| --- | --- | --- |
| Cold launch | PASS | bundle `dist` lancé le 2026-08-21, PID runtime observé |
| Lancement depuis Finder | NOT TESTED | lancement via `open`, pas Finder manuel |
| Menu bar | BLOCKED | cible menu bar construite, inspection visuelle dédiée non confirmée |
| Fermeture de la fenêtre principale | NOT TESTED | `ps` confirme l'arrêt des feeds sans consommateur |
| Réouverture | NOT TESTED | feeds relancés une seule fois |
| Sleep / wake | NOT TESTED | snapshots et processus après réveil |
| Permission refusée | NOT TESTED | état explicable, aucune panne globale |
| Permission accordée | NOT TESTED | rescan explicite et état mis à jour |
| Outil externe absent | PASS au niveau des tests/contrats | fallback et état indisponible couverts partiellement |
| Outil externe présent | PASS partiel | `/opt/homebrew/bin/macmon` et `/usr/bin/nettop` présents ; mode runtime variable |
| Erreur de subprocess | PASS au niveau des tests | `ProcessRunnerTests`, tests de statut |
| Timeout subprocess | PASS | `ProcessRunnerTests.testProcessTimeout` |

## UI et accessibilité

| Scénario | Statut |
| --- | --- |
| Light Mode | NOT TESTED | écran observé en sombre uniquement |
| Dark Mode | PASS partiel | écran sombre observé via Computer Use, 2026-08-21 |
| Redimensionnement | NOT TESTED |
| Retina | NOT TESTED |
| Écran externe | NOT TESTED |
| Navigation clavier | NOT TESTED |
| VoiceOver / labels de base | NOT TESTED |
| Loading / empty / error | BLOCKED | états partiels visibles ; matrice complète non exécutée |

## Safety

- Toute suppression utilisateur doit passer par `TrashService`, après revalidation par
  `SafetyGate`, et produire une entrée `OperationLog`.
- Les symlinks sont résolus immédiatement avant l'opération ; les chemins hors racine sont
  refusés.
- Les fichiers déplacés ou modifiés après scan doivent être revalidés ; ajouter un test de
  contrat pour chaque nouveau scanner.
- Les chemins protégés, les lots importants, les erreurs partielles et les données manquantes
  doivent produire un résultat explicable, jamais une réussite inventée.
- Un gros fichier n'est pas automatiquement un fichier récupérable. Les catalogues, projets,
  médias et modèles IA restent informatifs/protégés tant qu'une règle de confiance n'est pas
  démontrée.
- Aucun test ne doit utiliser une opération destructive sur la machine de développement ; les
  tests isolent leurs temporaires dans des répertoires dédiés.

## Distribution

| Contrôle | Statut |
| --- | --- |
| Developer ID Application | BLOCKED — identité non fournie ; bundle ad hoc |
| Hardened Runtime | BLOCKED | signature ad hoc sans option runtime |
| Entitlements | NOT TESTED — aucun fichier d'entitlements suivi |
| Notarisation | BLOCKED — profil notarytool non fourni |
| Stapling | NOT TESTED | `stapler validate` indique aucun ticket |
| Gatekeeper | FAIL pour l'ad hoc | `spctl -a -vv dist/Morax Garage.app` → source=no usable signature |
| Installation propre | NOT TESTED | aucune installation dans `/Applications` |

## Règle de sortie

La phase n'est validée que lorsque les contrôles pertinents sont `PASS` et que les contrôles non
exécutables restent nommés `BLOCKED` ou `NOT TESTED`. Les preuves doivent distinguer le code
source, le build, le bundle installé, le runtime et l'acceptation manuelle.

## Addendum Phase 4 — 2026-08-21

Les statuts ci-dessous supersèdent les valeurs baseline lorsqu’elles diffèrent.

| Contrôle | Statut Phase 4 | Preuve / limitation |
| --- | --- | --- |
| Suite complète | PASS | `swift test` — 164 tests, 0 échec, 30,17 s |
| Tests DiagnosticService + history | PASS | 12/12 ciblés |
| Build debug/release des deux produits | PASS | `swift build --product ...` et `swift build -c release --product ...` |
| Bundle Universal | PASS | `scripts/build_app.sh`; `lipo -archs` → `x86_64 arm64` pour les deux bundles |
| Findings système/processus/cache coexistants | PASS | `DiagnosticServiceIntegrationTests`, identifiants stables et mise à jour par catégorie |
| Session principale unique | PASS | anciennes instances fermées; PID runtime observés `97516`, puis `98342` après relaunch |
| Needs Attention état vide | PASS | arbre AX et capture `/tmp/morax-garage-phase4-dashboard.png` exposent `Needs Attention`, `OK` et le message vide |
| Menu bar + fermeture/réouverture principale | PASS | helper PID `97787` resté vivant quand l’app principale a été fermée |
| Menu bar popover détaillé | BLOCKED | lancement confirmé; ouverture/rafraîchissement visuels pas entièrement inspectés |
| Dark Mode / AX de base | PASS | capture et arbre AX runtime |
| Light Mode / resize / clavier / Retina | NOT TESTED | non exécutés séparément |
| Sleep/wake et scénarios TCC | NOT TESTED | aucun cycle ou changement de permission effectué |
| Performance runtime | PASS partial | cockpit 0,0 % CPU, 161 MB RSS, 1 subprocess macmon; snapshots ponctuels |
| Developer ID | BLOCKED | signature ad hoc, Team ID absent |
| Hardened Runtime | BLOCKED | aucune signature Developer ID/runtime prouvée |
| Notarisation | BLOCKED | aucun credential/profil autorisé utilisé |
| Stapling | NOT TESTED | aucun ticket; `stapler validate` le confirme |
| Gatekeeper | FAIL attendu pour ad hoc | `spctl -a -vv` rejette le bundle sans signature utilisable |

Le test de performance `SystemCacheScanner` a dépassé ponctuellement son seuil lors de la
première revalidation (18,09 s > 15 s), puis la suite complète a passé à la seconde exécution
(16,27 s). Cet événement reste documenté comme sensibilité/flakiness, sans relèvement artificiel
du seuil.
## Phase 2 revalidation — 2026-08-21

| Check | Status | Evidence / limitation |
| --- | --- | --- |
| Checkpoint revalidation | PASS | Branch `codex/morax-garage-improvement`; 143 tests before Phase 2; debug builds passed |
| Memory pressure source | PASS | `DispatchSourceMemoryPressure`; initial state remains unavailable until macOS emits an event |
| Local bounded history | PASS | Versioned atomic JSON, 60 s write gate, 30-day purge, corruption fallback, unit tests |
| Dashboard diagnostics | PASS | `Needs Attention` card consumes `DiagnosticService` findings and shows evidence/confidence |
| Cleanup classification | PASS | Presentation-only mapping reusing `RiskTier`; no deletion path added |
| Cold launch / window lifecycle | NOT TESTED | No manual runtime session recorded |
| Menu bar / light-dark / accessibility | NOT TESTED | Requires live app inspection |
| Permission denied / granted | NOT TESTED | Existing permission paths not exercised in this pass |
| Missing external tool / subprocess error | NOT TESTED | Automated fallback code exists; no live failure injection recorded |
| Release build (`MoraxCockpit`, `MoraxCockpitMenu`) | PASS | Fresh `swift build -c release --product ...` completed for host arm64 |
| Universal artifact | NOT TESTED | No universal toolchain/archive was produced in this pass |
| Developer ID / notarization / Gatekeeper | NOT TESTED | Credentials and external publication intentionally not used |

Allowed status vocabulary for this gate: PASS, FAIL, BLOCKED, NOT TESTED.
