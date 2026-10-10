# MINI COCKPIT ARCHITECTURE DESIGN DOCUMENT

**Projet :** Morax Garage (Morax Cockpit)  
**Composant :** Mini Cockpit / Always-On System HUD  
**Date :** 2026-08-24  

---

## 1. Vue d'Ensemble Architecturale

Le **Mini Cockpit** est un HUD flottant compact natif macOS (260–280 px de large), conçu pour rester affiché en permanence à l'écran sans perturber le travail de l'utilisateur ni consommer de ressources notables.

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Morax Garage / Menu Bar                         │
│   (Option dans menu barre des menus, réglages & raccourcis d'ouverture)│
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Active / Masque
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                      MiniCockpitWindowController                       │
│    - NSPanel AppKit (.nonactivatingPanel, .floating, .canJoinAllSpaces)│
│    - Persistance de position (UserDefaults)                            │
│    - Gestion multi-écrans & validation géométrique                     │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Héberge
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                         MiniCockpitHUDView                             │
│    - SwiftUI natif (Glance Mode & Expanded Detail Mode)                │
│    - Jauges CPU & RAM, Badge de Santé, Sparkline Canvas                │
│    - Interaction : Clic (Déplier), Double-Clic (Ouvrir Cockpit)        │
│    - Menu contextuel AppKit/SwiftUI (Clic droit)                       │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Observe
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                     MiniCockpitStateEngine & Model                     │
│    - Evaluation d'état (NORMAL / CHARGÉ / SATURÉ) avec hystérésis      │
│    - Rejet des pics transitoires (fenêtre temporelle multi-samples)    │
│    - MiniSparklineBuffer (Buffer circulaire fixe 30 points)            │
│    - Change detection & suppression des redraws inutiles               │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Acquiert / Libère
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                 TelemetryCoordinator & SystemMetrics                   │
│    - TelemetryConsumer.miniCockpit (.system / .process)                │
│    - Échantillonnage natif Darwin (Mach host ticks, vm_statistics64)   │
│    - macmon streaming si disponible                                    │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Choix Architectural : Unification dans `MoraxCockpitKit`

### Stratégie Adoptée
Plutôt que d'isoler le Mini Cockpit dans un 3ème exécutable indépendant (Option C) ou de contraindre son utilisation à `MoraxCockpitMenu` seul (Option A), le contrôleur de fenêtre et l'interface sont intégrés dans **`MoraxCockpitKit`**.

### Bénéfices :
1. **Zéro duplication de code :** `MoraxCockpitApp` et `MoraxCockpitMenuApp` partagent exactement le même contrôleur de fenêtre et les mêmes vues.
2. **Survie à la fermeture :** Dans l'app principale, le `MiniCockpitWindowController` reste actif même si la fenêtre Dashboard principale `main_window` est fermée.
3. **Zéro processus supplémentaire :** Aucun binaire auxiliaire en arrière-plan n'est requis.
4. **Coordination de flux transparente :** `TelemetryCoordinator.shared` gère le cycle de vie des sondes pour tous les consommateurs.

---

## 3. Moteur d'Évaluation de Santé (`MiniCockpitEvaluator`) & Hystérésis

### États Définis
- **`NORMAL`** : Le système fonctionne dans ses plages nominales. Couleur : `electricCyan` / `successGreen`.
- **`CHARGÉ`** : Une ressource (CPU, Mémoire, Swap) est sous tension soutenue. Couleur : `warningAmber`.
- **`SATURÉ`** : Une contrainte forte persistante compromet la réactivité du Mac. Couleur : `oxbloodRed`.

### Algorithme d'Hystérésis et Rejet des Pics Transitoires
Pour éviter qu'un pic CPU fugace (par exemple 100% pendant 500 ms lors du lancement d'un script) ne fasse clignoter l'indicateur en rouge :

1. **Échantillonnage glissant** : L'évaluateur maintient un historique des $N=5$ derniers échantillons de CPU.
2. **Seuils d'Entrée vs Sortie (Hystérésis)** :
   - **Passage à `CHARGÉ`** : CPU soutenu $\ge 75\%$ sur au moins 3 échantillons consécutifs OU Pression mémoire = `warning` OU Swap $> 2\text{ Go}$.
   - **Passage à `SATURÉ`** : CPU soutenu $\ge 90\%$ sur au moins 3 échantillons consécutifs OU Pression mémoire = `critical` OU (Swap $> 2\text{ Go}$ ET Pression $\ge \text{warning}$).
   - **Retour à `NORMAL`** : CPU moyen $< 65\%$ sur au moins 2 échantillons ET Pression mémoire = `normal`.
3. **Sécurité d'indisponibilité** : Si la télémétrie est indisponible ou non initialisée, l'état retourne `unavailable` et ne déclare jamais un faux `NORMAL`.

---

## 4. Historique Ultra-Léger : `MiniSparklineBuffer`

Pour dessiner l'historique d'activité CPU dans le HUD :
- Structure `MiniSparklineBuffer` basée sur un tableau à taille fixe (30 points, correspondant à 30–45s d'activité).
- Aucun appel mémoire dynamique répété (`append` réutilise le buffer circulaire).
- Rendu vectoriel via SwiftUI `Canvas` (CoreGraphics direct sous-jacent) : extrêmement rapide, consommant moins de $0.01\%$ CPU par rafraîchissement.

---

## 5. Gestion de la Fenêtre Flottante (`MiniCockpitWindowController`)

- Type de fenêtre : `NSPanel` AppKit personnalisé avec style `[.borderless, .nonactivatingPanel, .fullSizeContentView]`.
- Niveaux de fenêtre configurables :
  - `Always on Top` activé $\to$ `window.level = .floating`.
  - `Always on Top` désactivé $\to$ `window.level = .normal`.
- Espaces de travail virtuels (Mission Control / Spaces) :
  - `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`.
- Déplacement naturel : `isMovableByWindowBackground = true`.
- Persistance géométrique : Enregistre `(x, y)` dans `UserDefaults` à chaque fin de déplacement (`NSWindow.didMoveNotification`).
- Sécurité multi-écrans : Si les coordonnées mémorisées se trouvent en dehors de tous les écrans actuellement branchés (ex: écran externe déconnecté), la fenêtre est automatiquement recentrée dans le coin supérieur droit de `NSScreen.main`.

---

## 6. Niveaux d'Information & Interaction Utilisateur

### Niveau 1 : Glance (Toujours Visible)
- Dimensions : $\approx 270 \times 88\text{ pt}$.
- CPU : Pourcentage + Mini jauge + Sparkline 30s.
- RAM : Utilisée / Totale + Pourcentage + Barre d'état mémoire.
- Badge d'État : NORMAL / CHARGÉ / SATURÉ.
- Badge SWAP : Visible uniquement si Swap $> 2\text{ Go}$.

### Niveau 2 : Detail (Déplié au Clic / Survol)
- Dimensions : $\approx 270 \times 180\text{ pt}$.
- Détail du Swap en Mo/Go.
- Température CPU/GPU si disponible.
- Top Processus CPU (Nom, %, Icône).
- Top Processus RAM (Nom, Mo/Go, Icône).
- Bouton interactif direct : `Ouvrir Morax Garage`.

### Niveau 3 : Clic Droit / Menu Contextuel
- `Ouvrir Morax Garage` (Double-clic ou menu)
- `Toujours au premier plan` (Cochable)
- `Afficher sur tous les Spaces` (Cochable)
- `Mode Compact / Déplié`
- `Cadence de rafraîchissement` (1s / 2s / 5s)
- `Masquer le Mini Cockpit`
- `Quitter Morax Garage`
