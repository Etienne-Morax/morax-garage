import Foundation
import SwiftUI

// MARK: - Demo Feature Item
public struct DemoFeatureItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let iconName: String
    public let description: String
    public let tip: String?
    
    public init(id: String = UUID().uuidString, title: String, iconName: String, description: String, tip: String? = nil) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.description = description
        self.tip = tip
    }
}

// MARK: - Demo Capability Item
public struct DemoCapabilityItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let actionTitle: String
    public let trigger: String
    public let impact: String
    public let safetyLevel: String // e.g. "Lecture Seule", "Corbeille Réversible", "Dry-Run"
    
    public init(id: String = UUID().uuidString, actionTitle: String, trigger: String, impact: String, safetyLevel: String) {
        self.id = id
        self.actionTitle = actionTitle
        self.trigger = trigger
        self.impact = impact
        self.safetyLevel = safetyLevel
    }
}

// MARK: - Demo Real World Example
public struct DemoRealWorldExample: Hashable, Sendable {
    public let title: String
    public let context: String
    public let stepByStep: [String]
    public let metricsGain: String
    public let safetyNote: String
    
    public init(title: String, context: String, stepByStep: [String], metricsGain: String, safetyNote: String) {
        self.title = title
        self.context = context
        self.stepByStep = stepByStep
        self.metricsGain = metricsGain
        self.safetyNote = safetyNote
    }
}

// MARK: - Demo Page Guide
public struct DemoPageGuide: Identifiable, Hashable, Sendable {
    public let id: String
    public let pageRawValue: String
    public let title: String
    public let subtitle: String
    public let iconName: String
    public let badgeText: String
    public let purpose: String
    public let whyItMatters: String
    public let features: [DemoFeatureItem]
    public let capabilities: [DemoCapabilityItem]
    public let example: DemoRealWorldExample
    public let safetyGuarantee: String
    
    public init(
        id: String,
        pageRawValue: String,
        title: String,
        subtitle: String,
        iconName: String,
        badgeText: String,
        purpose: String,
        whyItMatters: String,
        features: [DemoFeatureItem],
        capabilities: [DemoCapabilityItem],
        example: DemoRealWorldExample,
        safetyGuarantee: String
    ) {
        self.id = id
        self.pageRawValue = pageRawValue
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.badgeText = badgeText
        self.purpose = purpose
        self.whyItMatters = whyItMatters
        self.features = features
        self.capabilities = capabilities
        self.example = example
        self.safetyGuarantee = safetyGuarantee
    }
}

// MARK: - Demo Scenario
public struct DemoScenarioStep: Identifiable, Hashable, Sendable {
    public let id: String
    public let stepNumber: Int
    public let title: String
    public let detail: String
    public let pageTarget: String
    public let iconName: String
    
    public init(id: String = UUID().uuidString, stepNumber: Int, title: String, detail: String, pageTarget: String, iconName: String) {
        self.id = id
        self.stepNumber = stepNumber
        self.title = title
        self.detail = detail
        self.pageTarget = pageTarget
        self.iconName = iconName
    }
}

public struct DemoScenarioOutcome: Hashable, Sendable {
    public let storageReclaimed: String
    public let performanceGain: String
    public let safetyAssurance: String
    
    public init(storageReclaimed: String, performanceGain: String, safetyAssurance: String) {
        self.storageReclaimed = storageReclaimed
        self.performanceGain = performanceGain
        self.safetyAssurance = safetyAssurance
    }
}

public struct DemoScenario: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let tag: String
    public let iconName: String
    public let accentColorHex: String
    public let narrative: String
    public let steps: [DemoScenarioStep]
    public let outcome: DemoScenarioOutcome
    
    public init(
        id: String,
        title: String,
        tag: String,
        iconName: String,
        accentColorHex: String,
        narrative: String,
        steps: [DemoScenarioStep],
        outcome: DemoScenarioOutcome
    ) {
        self.id = id
        self.title = title
        self.tag = tag
        self.iconName = iconName
        self.accentColorHex = accentColorHex
        self.narrative = narrative
        self.steps = steps
        self.outcome = outcome
    }
}

// MARK: - Safety Principle
public struct DemoSafetyPrinciple: Identifiable, Hashable, Sendable {
    public let id: String
    public let ruleNumber: Int
    public let title: String
    public let shortSummary: String
    public let deepExplanation: String
    public let iconName: String
    public let forbiddenPractices: [String]
    public let moraxStrictPractice: String
    public let technicalJustification: String
    
    public init(
        id: String,
        ruleNumber: Int,
        title: String,
        shortSummary: String,
        deepExplanation: String,
        iconName: String,
        forbiddenPractices: [String],
        moraxStrictPractice: String,
        technicalJustification: String
    ) {
        self.id = id
        self.ruleNumber = ruleNumber
        self.title = title
        self.shortSummary = shortSummary
        self.deepExplanation = deepExplanation
        self.iconName = iconName
        self.forbiddenPractices = forbiddenPractices
        self.moraxStrictPractice = moraxStrictPractice
        self.technicalJustification = technicalJustification
    }
}

// MARK: - FAQ Item
public struct DemoFAQItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let category: String
    public let question: String
    public let answer: String
    public let pageLink: String?
    
    public init(id: String = UUID().uuidString, category: String, question: String, answer: String, pageLink: String? = nil) {
        self.id = id
        self.category = category
        self.question = question
        self.answer = answer
        self.pageLink = pageLink
    }
}

// MARK: - Demo Guide Service
public final class DemoGuideService: Sendable {
    public static let shared = DemoGuideService()
    
    public let pageGuides: [DemoPageGuide]
    public let scenarios: [DemoScenario]
    public let safetyPrinciples: [DemoSafetyPrinciple]
    public let faqItems: [DemoFAQItem]
    
    public init() {
        self.pageGuides = DemoGuideService.buildPageGuides()
        self.scenarios = DemoGuideService.buildScenarios()
        self.safetyPrinciples = DemoGuideService.buildSafetyPrinciples()
        self.faqItems = DemoGuideService.buildFAQItems()
    }
    
    public func guide(for pageRawValue: String) -> DemoPageGuide? {
        pageGuides.first { $0.pageRawValue == pageRawValue }
    }
    
    // MARK: - Static Data Builders
    private static func buildPageGuides() -> [DemoPageGuide] {
        return [
            // 1. Dashboard
            DemoPageGuide(
                id: "dashboard",
                pageRawValue: "Dashboard",
                title: "Digital Cockpit & Télémétrie",
                subtitle: "Surveillance temps réel des ressources matérielles et des caches",
                iconName: "gauge.with.needle",
                badgeText: "TEMPS RÉEL",
                purpose: "Fournir une vue panoramique instantanée de la charge matérielle (CPU, GPU, RAM, Swap, Disque, Réseau, Puissance en Watts et Températures) avec un accent crucial sur le Swap SSD.",
                whyItMatters: "Sur macOS, le goulot d'étranglement le plus violent lors de montages vidéo ou de compilations lourdes est l'écriture continue dans le Swap SSD quand la mémoire unifiée sature.",
                features: [
                    DemoFeatureItem(
                        title: "Binnacle 5 Cadrans Automobiles",
                        iconName: "gauge.with.dots.needle.bottom.50percent",
                        description: "Aiguilles animées haute précision : Performance CPU, Cœurs GPU, Mémoire Vive, Pression Swap SSD, et Espace Disque disponible.",
                        tip: "Surveillez l'aiguille de Swap : toute valeur persistante supérieure à 2 Go indique un ralentissement SSD."
                    ),
                    DemoFeatureItem(
                        title: "Télémétrie Réseau en Direct",
                        iconName: "network",
                        description: "Débit descendant/ascendant en direct (Ko/s, Mo/s), sparkline dynamique 30 secondes, et comptage des sockets TCP/UDP actifs via nettop.",
                        tip: "Détecte immédiatement un processus en arrière-plan saturant la bande passante."
                    ),
                    DemoFeatureItem(
                        title: "Ventilation des Caches par Domaine",
                        iconName: "externaldrive.badge.timemachine",
                        description: "Mesure directe de la taille occupée par les Caches Navigateurs (Safari, Chrome), Caches Système et Caches Applicatifs.",
                        tip: "Cliquez sur une tuile pour ouvrir la feuille d'inspection détaillée du domaine."
                    ),
                    DemoFeatureItem(
                        title: "Historique Glissant 60 Minutes",
                        iconName: "chart.xyaxis.line",
                        description: "Graphique continu conservé en mémoire vive retraçant l'évolution de la consommation CPU et de la puissance totale (Watts).",
                        tip: "Idéal pour mesurer l'impact thermique et énergétique d'une longue session de travail."
                    )
                ],
                capabilities: [
                    DemoCapabilityItem(
                        actionTitle: "Actualisation manuelle instantanée",
                        trigger: "Bouton d'actualisation dans l'en-tête du cockpit",
                        impact: "Force un re-calcul immédiat de tous les compteurs natifs et des caches système",
                        safetyLevel: "Lecture Seule (Zéro impact disque)"
                    ),
                    DemoCapabilityItem(
                        actionTitle: "Inspection de domaine de cache",
                        trigger: "Clic sur une carte de cache (ex: Navigateurs)",
                        impact: "Affiche le détail précis des chemins et sous-dossiers concernés",
                        safetyLevel: "Lecture Seule"
                    ),
                    DemoCapabilityItem(
                        actionTitle: "Bascule vers le flux macmon",
                        trigger: "Détection automatique du binaire macmon",
                        impact: "Active les métriques matérielles approfondies (températures par capteur, clusters E/P)",
                        safetyLevel: "Lecture Seule via Pipe"
                    )
                ],
                example: DemoRealWorldExample(
                    title: "Surveillance d'un Export Vidéo DaVinci Resolve 4K",
                    context: "Pendant l'export d'une timeline avec étalonnage lourd, le système ralentit.",
                    stepByStep: [
                        "1. Ouvrez le Dashboard et observez le cadran SWAP : l'aiguille monte à 12 Go (rouge).",
                        "2. Observez le cadran GPU : charge à 98% et puissance totale à 48 Watts.",
                        "3. Diagnostic immédiat : la mémoire unifiée est saturée par les rendus non purgés, forçant macOS à swapper sur le disque.",
                        "4. Solution recommandée : naviguer vers l'onglet 'Cleanup & Cache' pour purger le cache de rendu DaVinci Resolve."
                    ],
                    metricsGain: "Passage du Swap de 12 Go à 0 Mo et retour des performances maximales",
                    safetyNote: "Toutes les métriques sont échantillonnées en mémoire vive sans aucune écriture intrusive sur disque."
                ),
                safetyGuarantee: "Le Dashboard opère à 100% en lecture seule. Aucune modification système, aucune télémétrie réseau distante."
            ),
            
            // 2. Storage Map
            DemoPageGuide(
                id: "storageMap",
                pageRawValue: "Storage Map",
                title: "Storage Map & Cartographie Treemap",
                subtitle: "Visualisation proportionnelle et interactive de l'espace disque",
                iconName: "square.grid.3x3.square",
                badgeText: "VISUALISATION",
                purpose: "Offrir une représentation visuelle sous forme de treemap dynamique de l'espace occupé sur vos disques, avec zoom hiérarchique et mise en scène immédiate des dossiers volumineux.",
                whyItMatters: "Trouver manuellement un dossier de 80 Go enfoui dans `~/Library/Application Support` ou `~/Projects` via le Finder est fastidieux. La Treemap rend chaque gigaoctet immédiatement visible et cliquable.",
                features: [
                    DemoFeatureItem(
                        title: "Moteur de Pavage Squarified Treemap",
                        iconName: "rectangle.split.2x2",
                        description: "Algorithme mathématique optimisant le ratio d'aspect des rectangles pour une lisibilité parfaite des proportions de disque.",
                        tip: "Plus le rectangle est grand, plus le dossier ou fichier occupe de place sur votre disque."
                    ),
                    DemoFeatureItem(
                        title: "Navigation Hiérarchique & Breadcrumbs",
                        iconName: "chevron.right.2",
                        description: "Double-cliquez sur n'importe quel sous-dossier pour plonger à l'intérieur. Le fil d'Ariane permet de remonter instantanément.",
                        tip: "Cliquez sur 'Zoom Arrière' ou sur n'importe quel segment du fil d'Ariane pour remonter."
                    ),
                    DemoFeatureItem(
                        title: "8 Catégories Intelligentes avec Code Couleur",
                        iconName: "paintpalette",
                        description: "Classification automatique par type de contenu : Caches (Ambre), Projets Dev (Bleu), Médias (Violet), Applications (Vert), Installateurs (Orange)...",
                        tip: "Cliquez sur une catégorie en bas pour filtrer instantanément la carte."
                    ),
                    DemoFeatureItem(
                        title: "File de Staging de Nettoyage",
                        iconName: "tray.and.arrow.down",
                        description: "Ajoutez des fichiers volumineux à une liste d'attente de nettoyage sans les supprimer immédiatement.",
                        tip: "Révélez le fichier dans le Finder ou envoyez-le vers la Corbeille en toute confiance."
                    )
                ],
                capabilities: [
                    DemoCapabilityItem(
                        actionTitle: "Scan d'un répertoire sur mesure",
                        trigger: "Bouton 'Autre dossier...' ou raccourcis Accueil / Bibliothèque",
                        impact: "Parcourt l'arborescence et calcule les tailles réelles",
                        safetyLevel: "Lecture Seule avec protection anti-boucle symlink"
                    ),
                    DemoCapabilityItem(
                        actionTitle: "Inspection détaillée",
                        trigger: "Simple clic sur un rectangle de la Treemap",
                        impact: "Affiche le volet d'inspection à droite avec date, taille et chemin absolu",
                        safetyLevel: "Lecture Seule"
                    ),
                    DemoCapabilityItem(
                        actionTitle: "Ajout au Staging de Nettoyage",
                        trigger: "Bouton 'Mettre en Staging' dans l'inspecteur",
                        impact: "Conserve l'élément dans la file d'attente visible en haut de l'écran",
                        safetyLevel: "Réversible (suppression uniquement sur confirmation explicite)"
                    )
                ],
                example: DemoRealWorldExample(
                    title: "Repérage d'un dossier DerivedData d'Xcode oublié de 42 Go",
                    context: "Votre disque SSD interne est presque plein sans raison apparente.",
                    stepByStep: [
                        "1. Ouvrez Storage Map et cliquez sur le préréglage 'Bibliothèque (~/Library)'.",
                        "2. Dès la fin du scan, un énorme rectangle bleu 'Developer' saute aux yeux.",
                        "3. Double-cliquez sur 'Developer', puis sur 'Xcode' : le sous-dossier 'DerivedData' affiche 42 Go.",
                        "4. Cliquez sur 'Révéler dans Finder' ou ajoutez-le au staging pour le déplacer vers la Corbeille."
                    ],
                    metricsGain: "42 Go d'espace SSD instantanément récupérés",
                    safetyNote: "Le scanner résout les liens symboliques et ignore formellement les répertoires système protégés."
                ),
                safetyGuarantee: "Aucune suppression directe : tout élément envoyé au nettoyage transite obligatoirement par la Corbeille de macOS."
            ),
            
            // 3. Cleanup & Cache
            DemoPageGuide(
                id: "cleanup",
                pageRawValue: "Cleanup & Cache",
                title: "Nettoyage Déterministe & Gestion des Caches",
                subtitle: "7 scanners spécialisés avec protection SafetyGate et Corbeille réversible",
                iconName: "trash",
                badgeText: "SÉCURISÉ",
                purpose: "Identifier et recycler de manière ciblée les fichiers temporaires, caches de montage vidéo, artefacts de build développeur et gros installateurs sans aucun risque d'effacement accidentel.",
                whyItMatters: "Les outils de nettoyage génériques suppriment aveuglément des bases de données ou des fichiers système cruciaux. Morax Garage utilise une liste d'exclusion inviolable et ne supprime JAMAIS sans passer par la Corbeille.",
                features: [
                    DemoFeatureItem(
                        title: "Scanner DaVinci Resolve Dédié",
                        iconName: "film",
                        description: "Cible spécifiquement les répertoires CacheClip (rendus), Proxies, Optimized Media et Gallery Stills.",
                        tip: "IMPORTANT : Les bases de données de projets (.drp, databases) sont formellement exclues du scanner."
                    ),
                    DemoFeatureItem(
                        title: "Scanner d'Artefacts Développeur",
                        iconName: "chevron.left.forwardslash.chevron.right",
                        description: "Détecte les répertoires node_modules, .next, target (Rust), .venv et DerivedData.",
                        tip: "Protection automatique : les projets modifiés il y a moins de 7 jours sont désélectionnés par défaut."
                    ),
                    DemoFeatureItem(
                        title: "Protection SafetyGate & Liste Noire",
                        iconName: "shield.checkered",
                        description: "Vérifie chaque chemin avant toute action : protection des répertoires /System, ~/Library/Keychains, MobileSync et du dossier Home lui-même.",
                        tip: "Si un chemin est interdit, l'opération est refusée et consignée dans le journal d'audit."
                    ),
                    DemoFeatureItem(
                        title: "Journal d'Opérations (Operation Log)",
                        iconName: "doc.plaintext",
                        description: "Historique auditable horodaté de chaque fichier déplacé vers la Corbeille avec taille, chemin et résultat.",
                        tip: "Consultable à tout moment avec filtrage d'erreurs et copie dans le presse-papiers."
                    )
                ],
                capabilities: [
                    DemoCapabilityItem(
                        actionTitle: "Scan Déterministe (Dry-Run)",
                        trigger: "Sélection d'un scanner puis clic sur 'Lancer le Scan'",
                        impact: "Analyse en lecture seule et présente l'arborescence des éléments trouvés",
                        safetyLevel: "100% Inoffensif (Tout est désélectionné par défaut)"
                    ),
                    DemoCapabilityItem(
                        actionTitle: "Sélection Manuelle Granulaire",
                        trigger: "Cochage individuel ou par catégorie",
                        impact: "Met à jour en direct le total d'octets récupérables",
                        safetyLevel: "Sous contrôle total de l'utilisateur"
                    ),
                    DemoCapabilityItem(
                        actionTitle: "Déplacement Sécurisé vers la Corbeille",
                        trigger: "Confirmation explicite dans la feuille de dialogue",
                        impact: "Déplace les éléments par lots de 5 000 via FileManager.trashItem",
                        safetyLevel: "100% Réversible dans la Corbeille macOS"
                    )
                ],
                example: DemoRealWorldExample(
                    title: "Nettoyage post-production d'un court-métrage (135 Go)",
                    context: "Un projet DaVinci Resolve a généré 135 Go de fichiers de rendu de timeline obsolètes.",
                    stepByStep: [
                        "1. Choisissez 'DaVinci Resolve' dans la liste des scanners et lancez le scan.",
                        "2. Le scanner découvre 135 Go répartis entre CacheClip et Optimized Media.",
                        "3. Tous les éléments sont présentés désélectionnés par sécurité.",
                        "4. Vous cochez le dossier CacheClip du projet terminé et cliquez sur 'Déplacer vers la Corbeille'.",
                        "5. La feuille de confirmation récapitule la liste exacte et demande validation.",
                        "6. Les fichiers sont déplacés dans la Corbeille : votre base de projet .drp reste intacte."
                    ],
                    metricsGain: "135 Go récupérés sur le SSD en 3 secondes avec sécurité totale",
                    safetyNote: "Jamais de commande 'rm' ou 'unlink'. En cas d'erreur de sélection, faites un simple 'Remettre' depuis la Corbeille."
                ),
                safetyGuarantee: "Règle absolue #1 : Aucune suppression définitive. Tout passe par FileManager.trashItem."
            ),
            
            // 4. Permissions
            DemoPageGuide(
                id: "permissions",
                pageRawValue: "Permissions",
                title: "Autorisations Système & Sécurité TCC",
                subtitle: "Audit de transparence des autorisations macOS et Accès Disque Complet",
                iconName: "lock.shield",
                badgeText: "SÉCURITÉ",
                purpose: "Offrir une visibilité totale et un contrôle transparent sur les autorisations macOS (Full Disk Access, Téléchargements, Documents) requises pour analyser les caches système.",
                whyItMatters: "macOS protège strictement les dossiers `~/Library/Caches` et les disques externes via son système TCC (Transparency, Consent, and Control). Morax Garage n'impose aucune autorisation au lancement et explique chaque besoin.",
                features: [
                    DemoFeatureItem(
                        title: "Bannière Accès Disque Complet (FDA)",
                        iconName: "key.fill",
                        description: "Statut en direct de l'accès disque complet avec guide illustré étape par étape pour l'activer dans Réglages Système.",
                        tip: "Débloque la visibilité sur les caches DaVinci Resolve et les répertoires système protégés."
                    ),
                    DemoFeatureItem(
                        title: "Demandes d'Autorisation Paresseuses (Lazy Grants)",
                        iconName: "hourglass.badge.plus",
                        description: "L'application ne demande AUCUNE autorisation au démarrage. L'accès à un dossier n'est sollicité que lors du premier scan initié par l'utilisateur.",
                        tip: "Vous pouvez utiliser l'application même sans donner d'accès aux dossiers non nécessaires."
                    ),
                    DemoFeatureItem(
                        title: "Raccourci 1-Clic vers Réglages Système",
                        iconName: "arrow.up.forward.app",
                        description: "Ouvre directement la section exacte 'Confidentialité et sécurité > Accès complet au disque' de macOS.",
                        tip: "Évite de devoir chercher manuellement dans les sous-menus de macOS."
                    ),
                    DemoFeatureItem(
                        title: "Re-vérification à Chaud",
                        iconName: "arrow.clockwise.circle",
                        description: "Actualise instantanément l'état de validation dès que vous modifiez une case dans macOS.",
                        tip: "Pas besoin de redémarrer Morax Garage pour détecter les nouvelles autorisations."
                    )
                ],
                capabilities: [
                    DemoCapabilityItem(
                        actionTitle: "Vérifier le statut TCC",
                        trigger: "Bouton 'Re-check Permissions'",
                        impact: "Sonde la lisibilité des dossiers clés sans bloquer l'UI",
                        safetyLevel: "Lecture Seule"
                    ),
                    DemoCapabilityItem(
                        actionTitle: "Ouvrir Réglages Système",
                        trigger: "Bouton 'Ouvrir Réglages' sur une carte d'autorisation",
                        impact: "Ouvre l'URL système x-apple.systempreferences:...",
                        safetyLevel: "Action Système Standard"
                    ),
                    DemoCapabilityItem(
                        actionTitle: "Déclencher l'invite de dossier",
                        trigger: "Bouton 'Demander l'accès'",
                        impact: "Affiche le dialogue natif macOS 'Morax Garage souhaite accéder à vos fichiers'",
                        safetyLevel: "Sous consentement de l'utilisateur"
                    )
                ],
                example: DemoRealWorldExample(
                    title: "Activation de l'Accès Disque Complet pour nettoyer les caches Resolve",
                    context: "Le scan DaVinci Resolve indique que certains caches sous ~/Library ne sont pas lisibles.",
                    stepByStep: [
                        "1. Rendez-vous sur la page 'Permissions'.",
                        "2. La bannière ambre indique 'Accès disque complet recommandé'.",
                        "3. Cliquez sur 'Ouvrir Réglages Système'.",
                        "4. Activez l'interrupteur pour 'Morax Garage' et revenez sur l'application.",
                        "5. Le statut passe instantanément au vert 'Autorisé'."
                    ],
                    metricsGain: "Déblocage de 100% des scanners de cache applicatifs",
                    safetyNote: "Morax Garage ne stocke aucun identifiant et ne s'exécute jamais en tant qu'administrateur (root)."
                ),
                safetyGuarantee: "Règle #2 : Zéro daemon d'arrière-plan avec privilèges élevés. Morax reste confiné à votre session utilisateur."
            ),
            
            // 5. Mole Terminal
            DemoPageGuide(
                id: "terminal",
                pageRawValue: "Mole Terminal",
                title: "Mole Terminal & Console Interactive",
                subtitle: "Émulateur de terminal complet pour l'outil CLI Mole sans auto-exécution",
                iconName: "terminal",
                badgeText: "TERMINAL",
                purpose: "Héberger un vrai shell de connexion (zsh/bash) permettant d'utiliser l'utilitaire de nettoyage avancé Mole (tw93/mole) tout en garantissant une isolation totale des licences.",
                whyItMatters: "Mole est un outil open source puissant mais soumis à la licence GPL-3.0. En l'intégrant via un terminal interactif où vous gardez la main, Morax respecte rigoureusement la licence et vous protège des commandes accidentelles.",
                features: [
                    DemoFeatureItem(
                        title: "Véritable Émulateur SwiftTerm",
                        iconName: "terminal.fill",
                        description: "Héberge votre propre shell de session avec coloration syntaxique, historique et accès à votre variable PATH complète.",
                        tip: "Prend en charge toutes vos commandes CLI habituelles."
                    ),
                    DemoFeatureItem(
                        title: "Boutons d'Actions Rapides Sécurisés",
                        iconName: "keyboard",
                        description: "Boutons prédéfinis pour 'mo clean --dry-run', 'mo purge --dry-run', 'mo status'.",
                        tip: "Sécurité : les boutons INSÈRENT la commande dans le shell SANS appuyer sur Entrée. Vous restez maître du déclenchement."
                    ),
                    DemoFeatureItem(
                        title: "Détection Automatique de Mole",
                        iconName: "checkmark.seal",
                        description: "Vérifie si Mole est installé sur votre Mac et propose la commande d'installation Homebrew en cas d'absence.",
                        tip: "Installez avec : brew install tw93/tap/mole"
                    ),
                    DemoFeatureItem(
                        title: "Prise en charge du Copier / Coller et Redimensionnement",
                        iconName: "arrow.up.left.and.arrow.down.right",
                        description: "Supporte les raccourcis clavier standards macOS (Cmd+C, Cmd+V, Cmd+K pour effacer).",
                        tip: "S'adapte automatiquement à la largeur de votre fenêtre."
                    )
                ],
                capabilities: [
                    DemoCapabilityItem(
                        actionTitle: "Insertion de commande de simulation (dry-run)",
                        trigger: "Clic sur 'mo clean (dry-run)'",
                        impact: "Écrit le texte dans votre invite sans l'exécuter",
                        safetyLevel: "Aucun risque (Validation manuelle obligatoire)"
                    ),
                    DemoCapabilityItem(
                        actionTitle: "Diagnostic du système via Mole",
                        trigger: "Clic sur 'mo status'",
                        impact: "Pré-remplit la commande d'état",
                        safetyLevel: "Lecture Seule"
                    ),
                    DemoCapabilityItem(
                        actionTitle: "Saisie libre dans le terminal",
                        trigger: "Frappe au clavier dans la zone noire",
                        impact: "Exécute toute commande shell de votre choix",
                        safetyLevel: "Environnement utilisateur standard"
                    )
                ],
                example: DemoRealWorldExample(
                    title: "Exécution d'une simulation de purge complète via Mole",
                    context: "Vous voulez purger les caches système résiduels après une mise à jour macOS.",
                    stepByStep: [
                        "1. Allez sur l'onglet 'Mole Terminal'.",
                        "2. Cliquez sur le bouton 'mo purge (dry-run)' en haut à droite.",
                        "3. La commande 'mo purge --dry-run' s'affiche dans votre invite zsh.",
                        "4. Appuyez sur la touche Entrée de votre clavier pour lancer la simulation.",
                        "5. Mole liste les fichiers ciblés sans rien supprimer.",
                        "6. Si la liste vous convient, lancez la commande réelle en pleine connaissance de cause."
                    ],
                    metricsGain: "Nettoyage profond sécurisé avec rapport visuel dans le terminal",
                    safetyNote: "Morax n'intercepte pas et ne modifie pas les flux stdout de Mole."
                ),
                safetyGuarantee: "Règle #3 : Aucun binaire Mole n'est embarqué dans l'application. Vous conservez le contrôle total de vos paquets."
            ),
            
            // 6. Applications
            DemoPageGuide(
                id: "apps",
                pageRawValue: "Applications",
                title: "Inventaire des Applications & Relais Pearcleaner",
                subtitle: "Calcul des tailles réelles et désinstallation propre sans résidus",
                iconName: "app.badge",
                badgeText: "INVENTAIRE",
                purpose: "Lister toutes les applications installées sur votre Mac (/Applications et ~/Applications) avec leur taille réelle sur disque, date de dernier usage et délégation de désinstallation à Pearcleaner.",
                whyItMatters: "Glisser une application vers la Corbeille laisse souvent plusieurs gigaoctets de caches et résidus dans `~/Library/Application Support`. Morax s'associe au meilleur outil dédié (Pearcleaner) sans réinventer la roue.",
                features: [
                    DemoFeatureItem(
                        title: "Calcul Exhaustif de la Taille Disque",
                        iconName: "chart.bar.xaxis",
                        description: "Parcourt l'ensemble du bundle .app pour donner la taille réelle exacte (y compris les ressources internes volumineuses).",
                        tip: "Triez ou recherchez facilement les applications les plus gourmandes."
                    ),
                    DemoFeatureItem(
                        title: "Recherche & Filtrage Instantané",
                        iconName: "magnifyingglass",
                        description: "Recherche en temps réel par nom d'application ou par identifiant de bundle (ex: com.blackmagic-design...).",
                        tip: "Tapez quelques lettres pour isoler immédiatement une app."
                    ),
                    DemoFeatureItem(
                        title: "Passage de Relais à Pearcleaner",
                        iconName: "arrow.up.right.square",
                        description: "Ouvre l'application cible directement dans Pearcleaner pour une désinstallation complète de tous ses résidus cachés.",
                        tip: "Si Pearcleaner n'est pas installé, Morax propose la commande d'installation Homebrew ou révèle l'app dans le Finder."
                    ),
                    DemoFeatureItem(
                        title: "Révélation dans le Finder",
                        iconName: "folder",
                        description: "Met en surbrillance l'application dans son dossier source dans le Finder en un clic.",
                        tip: "Pratique pour inspecter manuellement les propriétés du fichier."
                    )
                ],
                capabilities: [
                    DemoCapabilityItem(
                        actionTitle: "Recherche d'application",
                        trigger: "Saisie dans la barre de recherche",
                        impact: "Filtre la liste en mémoire instantanément",
                        safetyLevel: "Lecture Seule"
                    ),
                    DemoCapabilityItem(
                        actionTitle: "Révélation Finder",
                        trigger: "Bouton 'Finder'",
                        impact: "Ouvre une fenêtre Finder sur l'application",
                        safetyLevel: "Action Système Inoffensive"
                    ),
                    DemoCapabilityItem(
                        actionTitle: "Désinstallation avec Pearcleaner",
                        trigger: "Bouton 'Uninstall with Pearcleaner'",
                        impact: "Transmet l'URL de l'application à Pearcleaner",
                        safetyLevel: "Désinstallation contrôlée par Pearcleaner"
                    )
                ],
                example: DemoRealWorldExample(
                    title: "Désinstallation propre d'une suite logicielle d'essai de 15 Go",
                    context: "Une version d'évaluation d'un logiciel 3D n'est plus utilisée et occupe 15 Go.",
                    stepByStep: [
                        "1. Ouvrez l'onglet 'Applications' et filtrez la liste.",
                        "2. Repérez l'application affichant '14.8 Go sur le disque'.",
                        "3. Cliquez sur le bouton 'Uninstall with Pearcleaner'.",
                        "4. Pearcleaner s'ouvre automatiquement et identifie les 3 Go supplémentaires de caches cachés dans ~/Library.",
                        "5. Vous validez la désinstallation complète en 1 clic."
                    ],
                    metricsGain: "17.8 Go d'espace récupérés sans aucun fichier fantôme résiduel",
                    safetyNote: "Morax n'effectue jamais de désinstallation directe hasardeuse : il délègue à un spécialiste éprouvé."
                ),
                safetyGuarantee: "Le cockpit ne supprime aucune application lui-même afin d'éliminer tout risque d'endommager vos logiciels."
            ),
            
            // 7. Homebrew
            DemoPageGuide(
                id: "brew",
                pageRawValue: "Homebrew",
                title: "Mises à Jour Homebrew (Formules & Casks)",
                subtitle: "Surveillance des paquets obsolètes et copie de commandes sécurisées",
                iconName: "mug",
                badgeText: "PAQUETS",
                purpose: "Vérifier en arrière-plan les formules CLI et applications Casks gérées par Homebrew qui disposent d'une mise à jour disponible.",
                whyItMatters: "Exécuter des mises à jour automatiques en arrière-plan peut casser vos environnements de développement ou introduire des ruptures de compatibilité. Morax vous informe et vous laisse exécuter les mises à jour dans votre terminal.",
                features: [
                    DemoFeatureItem(
                        title: "Détection Non-Intrusive (brew outdated)",
                        iconName: "clock.arrow.circlepath",
                        description: "Interroge Homebrew au format JSON structuré pour lister précisément les versions actuelles et nouvelles.",
                        tip: "Aucun téléchargement ni écriture n'est lancé en douce."
                    ),
                    DemoFeatureItem(
                        title: "Distinction Claire Formules vs Casks",
                        iconName: "shippingbox",
                        description: "Classe distinctement les utilitaires de ligne de commande (Node, Python, Ffmpeg) et les applications graphiques (VS Code, VLC).",
                        tip: "Permet de prioriser les mises à jour critiques."
                    ),
                    DemoFeatureItem(
                        title: "Boutons 'Copier la Commande'",
                        iconName: "doc.on.doc",
                        description: "Copie en 1 clic la commande d'upgrade globale 'brew upgrade' ou ciblée par paquet (ex: 'brew upgrade ffmpeg').",
                        tip: "Collez la commande dans le Mole Terminal ou votre terminal favori quand vous êtes prêt."
                    ),
                    DemoFeatureItem(
                        title: "Indicateur de Version et Statut",
                        iconName: "tag",
                        description: "Affiche le saut de version (ex: 3.4.1 -> 3.5.0) pour évaluer l'importance de la mise à jour.",
                        tip: "Utile pour repérer les mises à jour majeures."
                    )
                ],
                capabilities: [
                    DemoCapabilityItem(
                        actionTitle: "Actualisation du rapport de versions",
                        trigger: "Bouton 'Refresh'",
                        impact: "Lance 'brew outdated --json=v2' en sous-processus asynchrone",
                        safetyLevel: "Lecture Seule"
                    ),
                    DemoCapabilityItem(
                        actionTitle: "Copie de la commande globale",
                        trigger: "Bouton 'Copy brew upgrade'",
                        impact: "Place la chaîne de commande dans votre presse-papiers",
                        safetyLevel: "Presse-papiers uniquement"
                    ),
                    DemoCapabilityItem(
                        actionTitle: "Copie d'une commande individuelle",
                        trigger: "Bouton de copie sur la ligne d'un paquet",
                        impact: "Copie 'brew upgrade <nom_du_paquet>'",
                        safetyLevel: "Presse-papiers uniquement"
                    )
                ],
                example: DemoRealWorldExample(
                    title: "Mise à jour sélective de FFMPEG sans casser un projet Node.js en cours",
                    context: "Homebrew signale 8 paquets obsolètes, mais vous êtes au milieu d'un sprint de développement.",
                    stepByStep: [
                        "1. Consultez la page 'Homebrew'.",
                        "2. Vous constatez que 'ffmpeg' dispose d'un correctif de sécurité important, alors que 'node' a une mise à jour majeure potentiellement risquée.",
                        "3. Au lieu de faire un 'brew upgrade' aveugle, cliquez sur 'Copier' sur la ligne de ffmpeg.",
                        "4. Collez la commande dans l'onglet 'Mole Terminal' et validez.",
                        "5. ffmpeg est mis à jour sans perturber votre version de Node.js."
                    ],
                    metricsGain: "Maintien de la stabilité de l'environnement sans casser de dépendances",
                    safetyNote: "Morax Garage ne lancera JAMAIS de commande 'brew upgrade' de manière autonome."
                ),
                safetyGuarantee: "L'application ne modifie aucun fichier Homebrew : l'exécution des upgrades reste sous votre responsabilité."
            ),
            
            // 8. Audit
            DemoPageGuide(
                id: "audit",
                pageRawValue: "Persistence Audit",
                title: "Audit des Points de Persistance (Lecture Seule)",
                subtitle: "Inspection sécurisée des LaunchAgents, LaunchDaemons et détection d'orphelins",
                iconName: "shield.lefthalf.filled",
                badgeText: "SÉCURITÉ",
                purpose: "Inspecter tous les programmes configurés pour démarrer automatiquement avec votre session macOS et détecter les agents orphelins (fichiers plist pointant vers des exécutables supprimés).",
                whyItMatters: "Après une infection ou la désinstallation manuelle de logiciels, de nombreux fichiers de démarrage résiduels continuent de tourner en tâche de fond. Cet audit offre une visibilité totale sans risque de suppression accidentelle.",
                features: [
                    DemoFeatureItem(
                        title: "Inspection Multi-Emplacements",
                        iconName: "folder.badge.gearshape",
                        description: "Parcourt ~/Library/LaunchAgents, /Library/LaunchAgents, /Library/LaunchDaemons et les éléments de démarrage SMAppService.",
                        tip: "Tous les emplacements standards de démarrage macOS sont audités."
                    ),
                    DemoFeatureItem(
                        title: "Détection Automatique d'Orphelins (Orphaned Items)",
                        iconName: "exclamationmark.triangle.fill",
                        description: "Vérifie si le fichier binaire référencé dans le .plist existe encore physiquement sur le disque.",
                        tip: "Un élément orphelin tente de se lancer inutilement et peut ralentir le démarrage."
                    ),
                    DemoFeatureItem(
                        title: "Filtre 'Orphelins Uniquement'",
                        iconName: "line.3.horizontal.decrease.circle",
                        description: "Bascule instantanément l'affichage pour n'afficher que les agents dont l'exécutable est introuvable.",
                        tip: "Permet un audit rapide sans se perdre dans la liste complète."
                    ),
                    DemoFeatureItem(
                        title: "Mode Strictement Lecture Seule",
                        iconName: "eye.fill",
                        description: "Aucun bouton de modification ou suppression destructive : vue conçue pour l'investigation sereine.",
                        tip: "Évite tout plantage de service système par manipulation hâtive."
                    )
                ],
                capabilities: [
                    DemoCapabilityItem(
                        actionTitle: "Filtrage par emplacement",
                        trigger: "Sélecteur d'emplacement (ex: LaunchAgents Utilisateur)",
                        impact: "Restreint la liste aux fichiers du répertoire sélectionné",
                        safetyLevel: "Lecture Seule"
                    ),
                    DemoCapabilityItem(
                        actionTitle: "Filtrage des orphelins",
                        trigger: "Case à cocher 'Orphans Only'",
                        impact: "Isole les services fantômes",
                        safetyLevel: "Lecture Seule"
                    ),
                    DemoCapabilityItem(
                        actionTitle: "Copie du chemin absolu",
                        trigger: "Sélection d'un élément d'audit",
                        impact: "Permet de localiser manuellement le fichier .plist pour examen",
                        safetyLevel: "Lecture Seule"
                    )
                ],
                example: DemoRealWorldExample(
                    title: "Détection d'un LaunchAgent résiduel d'un logiciel désinstallé",
                    context: "Votre Mac affiche parfois une alerte 'processus non trouvé' au démarrage de la session.",
                    stepByStep: [
                        "1. Rendez-vous sur la page 'Persistence Audit'.",
                        "2. Cochez la case 'Orphans Only'.",
                        "3. L'audit signale en rouge un fichier 'com.oldapp.helper.plist'.",
                        "4. L'inspecteur indique : 'Binaire cible introuvable : /Applications/OldApp.app/Contents/MacOS/Helper'.",
                        "5. Vous copiez le chemin du .plist pour le supprimer manuellement en toute connaissance de cause."
                    ],
                    metricsGain: "Démarrage plus propre et élimination des alertes fantômes",
                    safetyNote: "L'application ne touche pas à vos LaunchDaemons : l'audit est 100% passif."
                ),
                safetyGuarantee: "Zéro modification automatique : Morax Garage est une loupe d'observation de sécurité."
            ),
            
            // 9. Environment
            DemoPageGuide(
                id: "environment",
                pageRawValue: "Environment",
                title: "Environnement & Outils Orchestrés",
                subtitle: "Détection des outils CLI partenaires sans aucun binaire embarqué",
                iconName: "wrench.and.screwdriver",
                badgeText: "SYSTÈME",
                purpose: "Vérifier la présence, l'emplacement et la version des 5 outils système clés (macmon, Mole, Pearcleaner, Homebrew, Stats) orchestrés par Morax Garage.",
                whyItMatters: "Morax Garage respecte une éthique stricte : il n'embarque aucun exécutable tiers dans son paquet pour garantir votre sécurité et la conformité des licences. Cette page vous aide à installer les compléments recommandés.",
                features: [
                    DemoFeatureItem(
                        title: "Détection Hors PATH Finder",
                        iconName: "magnifyingglass.circle",
                        description: "Résout les chemins réels (/opt/homebrew/bin, /usr/local/bin, /Applications) même lorsque l'app est lancée depuis le Finder sans PATH hérité.",
                        tip: "Garantit une détection infaillible sur Apple Silicon et Intel."
                    ),
                    DemoFeatureItem(
                        title: "Vérification des Numéros de Version",
                        iconName: "number",
                        description: "Interroge les binaires officiels (ex: macmon --version, mo --version) pour confirmer la compatibilité.",
                        tip: "Vérifiez en un coup d'œil si vos outils sont à jour."
                    ),
                    DemoFeatureItem(
                        title: "Commandes d'Installation Homebrew en 1 Clic",
                        iconName: "doc.on.clipboard",
                        description: "Pour chaque outil absent, un bouton permet de copier instantanément la commande officielle 'brew install ...'.",
                        tip: "Collez la commande dans Mole Terminal pour équiper votre Mac en quelques secondes."
                    ),
                    DemoFeatureItem(
                        title: "Transparence des Rôles & Licences",
                        iconName: "text.book.closed",
                        description: "Détaille le rôle de chaque outil dans le cockpit et sa licence (MIT, GPL-3.0, BSD, Apache 2.0).",
                        tip: "Transparence absolue sur la manière dont vos outils sont sollicités."
                    )
                ],
                capabilities: [
                    DemoCapabilityItem(
                        actionTitle: "Diagnostic complet de l'environnement",
                        trigger: "Bouton 'Refresh' ou chargement de la page",
                        impact: "Sonde le système de fichiers pour détecter les 5 outils",
                        safetyLevel: "Lecture Seule"
                    ),
                    DemoCapabilityItem(
                        actionTitle: "Copie de commande d'installation",
                        trigger: "Bouton 'Copy Install Command'",
                        impact: "Place la commande exacte dans le presse-papiers",
                        safetyLevel: "Presse-papiers uniquement"
                    )
                ],
                example: DemoRealWorldExample(
                    title: "Installation de macmon pour débloquer la télémétrie complète",
                    context: "Sur le Dashboard, les métriques de température et puissance indiquent que macmon est absent.",
                    stepByStep: [
                        "1. Ouvrez l'onglet 'Environment'.",
                        "2. La carte 'macmon' apparaît en statut 'Non installé'.",
                        "3. Cliquez sur 'Copy: brew install vladkens/tap/macmon'.",
                        "4. Ouvrez l'onglet 'Mole Terminal', collez la commande et appuyez sur Entrée.",
                        "5. Revenez sur le Dashboard : les cadrans de température et de Watts s'animent en direct !"
                    ],
                    metricsGain: "Accès à la télémétrie thermique et énergétique complète du processeur (détaillée sur Apple Silicon)",
                    safetyNote: "Les outils sont installés dans votre préfixe Homebrew standard, sans aucune modification obscure."
                ),
                safetyGuarantee: "Règle #3 : Aucun binaire précompilé n'est téléchargé ou exécuté à votre insu."
            )
        ]
    }
    
    private static func buildScenarios() -> [DemoScenario] {
        return [
            DemoScenario(
                id: "davinci_resolve_clean",
                title: "Post-Production Vidéo & DaVinci Resolve",
                tag: "VIDÉASTE / ÉTALONNAGE",
                iconName: "film.stack",
                accentColorHex: "#C8463A",
                narrative: "Après avoir finalisé le montage et l'étalonnage d'un documentaire en 4K/6K ProRes, votre SSD sature avec 140 Go de fichiers temporaires de rendu, tout en devant impérativement protéger vos fichiers de projets .drp.",
                steps: [
                    DemoScenarioStep(
                        stepNumber: 1,
                        title: "Constat sur le Dashboard",
                        detail: "Le cadran d'Espace Disque indique seulement 18 Go libres sur le SSD interne, et l'aiguille de Swap montre 8 Go de pression.",
                        pageTarget: "Dashboard",
                        iconName: "gauge.with.needle"
                    ),
                    DemoScenarioStep(
                        stepNumber: 2,
                        title: "Localisation visuelle dans Storage Map",
                        detail: "Le scan du dossier Vidéos révèle un énorme bloc violet correspondant au répertoire CacheClip de DaVinci Resolve.",
                        pageTarget: "Storage Map",
                        iconName: "square.grid.3x3.square"
                    ),
                    DemoScenarioStep(
                        stepNumber: 3,
                        title: "Scan Déterministe DaVinci Resolve",
                        detail: "Dans Cleanup & Cache, lancez le scanner DaVinci Resolve. 140 Go de rendus obsolètes sont identifiés.",
                        pageTarget: "Cleanup & Cache",
                        iconName: "trash"
                    ),
                    DemoScenarioStep(
                        stepNumber: 4,
                        title: "Validation et Envoi à la Corbeille",
                        detail: "Sélectionnez les caches des anciennes timelines, validez la confirmation. Les éléments partent dans la Corbeille de macOS.",
                        pageTarget: "Cleanup & Cache",
                        iconName: "checkmark.shield"
                    )
                ],
                outcome: DemoScenarioOutcome(
                    storageReclaimed: "140 Go d'espace SSD libérés",
                    performanceGain: "Disparition totale du Swap et fluidité maximale restaurée",
                    safetyAssurance: "Bases de données de projets (.drp) 100% intactes grâce aux filtres stricts du scanner"
                )
            ),
            
            DemoScenario(
                id: "fullstack_dev_clean",
                title: "Développeur Full-Stack & Projets Rust / Node",
                tag: "DÉVELOPPEUR WEB & LOGICIEL",
                iconName: "laptopcomputer.and.arrow.down",
                accentColorHex: "#2563EB",
                narrative: "Vous développez plusieurs projets Next.js, Rust et Python. Les dossiers node_modules et target accumulent plus de 50 Go d'artefacts sur les projets anciens, mais vous ne voulez surtout pas toucher à vos dépôts actifs de la semaine.",
                steps: [
                    DemoScenarioStep(
                        stepNumber: 1,
                        title: "Lancement du scanner Developer Artefacts",
                        detail: "Sélectionnez le scanner Développeur dans l'onglet Cleanup & Cache sur vos dossiers ~/Projects et ~/GitHub.",
                        pageTarget: "Cleanup & Cache",
                        iconName: "chevron.left.forwardslash.chevron.right"
                    ),
                    DemoScenarioStep(
                        stepNumber: 2,
                        title: "Protection automatique des projets récents",
                        detail: "Morax analyse la date de dernière modification : tous les projets modifiés il y a moins de 7 jours sont automatiquement décochés.",
                        pageTarget: "Cleanup & Cache",
                        iconName: "clock.badge.checkmark"
                    ),
                    DemoScenarioStep(
                        stepNumber: 3,
                        title: "Nettoyage sélectif",
                        detail: "Vous validez le déplacement vers la Corbeille des répertoires 'target' et 'node_modules' des archives inactives depuis 6 mois.",
                        pageTarget: "Cleanup & Cache",
                        iconName: "trash"
                    )
                ],
                outcome: DemoScenarioOutcome(
                    storageReclaimed: "52 Go d'espace récupérés",
                    performanceGain: "Indexation Spotlight et temps de recherche divisés par deux",
                    safetyAssurance: "Zéro risque de devoir re-télécharger les dépendances de votre projet en cours"
                )
            ),
            
            DemoScenario(
                id: "security_audit_clean",
                title: "Audit de Sécurité & Hygiène Post-Incident",
                tag: "SÉCURITÉ & TRANSPARENCE",
                iconName: "shield.lefthalf.filled",
                accentColorHex: "#D97706",
                narrative: "Après avoir téléchargé un paquet suspect ou désinstallé d'anciennes applications, vous souhaitez vous assurer qu'aucun processus fantôme ou résidu persistant ne se lance au démarrage.",
                steps: [
                    DemoScenarioStep(
                        stepNumber: 1,
                        title: "Consultation des autorisations TCC",
                        detail: "Sur la page Permissions, vérifiez que l'application respecte les règles du bac à sable et n'a aucun accès non sollicité.",
                        pageTarget: "Permissions",
                        iconName: "lock.shield"
                    ),
                    DemoScenarioStep(
                        stepNumber: 2,
                        title: "Audit des LaunchAgents et LaunchDaemons",
                        detail: "Sur la page Persistence Audit, inspectez tous les services de démarrage et cochez 'Orphans Only'.",
                        pageTarget: "Persistence Audit",
                        iconName: "eye"
                    ),
                    DemoScenarioStep(
                        stepNumber: 3,
                        title: "Traitement éclairé",
                        detail: "Identifiez les fichiers plist orphelins pointant vers des binaires supprimés et copiez leurs chemins pour nettoyage.",
                        pageTarget: "Persistence Audit",
                        iconName: "doc.text.magnifyingglass"
                    )
                ],
                outcome: DemoScenarioOutcome(
                    storageReclaimed: "Services fantômes identifiés et neutralisés",
                    performanceGain: "Temps de démarrage de session macOS optimisé",
                    safetyAssurance: "Audit 100% passif sans privilège root ni risque d'endommager le système"
                )
            )
        ]
    }
    
    private static func buildSafetyPrinciples() -> [DemoSafetyPrinciple] {
        return [
            DemoSafetyPrinciple(
                id: "rule_1_trash_only",
                ruleNumber: 1,
                title: "Jamais de suppression destructrice (Corbeille uniquement)",
                shortSummary: "Interdiction formelle de 'rm', 'unlink' ou 'FileManager.removeItem'.",
                deepExplanation: "Chaque élément nettoyé par Morax Garage passe obligatoirement par 'FileManager.trashItem(at:resultingItemURL:)'. Il n'existe AUCUNE option de suppression définitive dans l'application. Si un fichier ne peut pas être mis à la corbeille, il est signalé comme ignoré.",
                iconName: "trash.circle.fill",
                forbiddenPractices: [
                    "Exécution de commandes shell 'rm -rf' en arrière-plan",
                    "Suppression définitive sans confirmation explicite",
                    "Nettoyage automatique 'en un clic' sans revue par l'utilisateur",
                    "Bouton 'Vider immédiatement la corbeille' intégré"
                ],
                moraxStrictPractice: "Tout fichier retiré se retrouve dans votre Corbeille macOS standard, permettant une restauration instantanée via 'Remettre' en cas d'erreur.",
                technicalJustification: "L'erreur humaine est inévitable lors du tri de gigaoctets de données. La Corbeille macOS offre un filet de sécurité inviolable qui annule tout risque de perte définitive."
            ),
            
            DemoSafetyPrinciple(
                id: "rule_2_no_root",
                ruleNumber: 2,
                title: "Zéro privilège root, zéro LaunchDaemon privilégié",
                shortSummary: "L'application s'exécute à 100% dans l'espace utilisateur sans élévation de droits.",
                deepExplanation: "Morax Garage ne possède aucun helper privilégié (Privileged Helper Tool) et ne demande JAMAIS votre mot de passe administrateur pour s'octroyer des privilèges root. Les dossiers système protégés (/System, /Library, /usr) ne sont jamais altérés.",
                iconName: "person.badge.shield.checkmark.fill",
                forbiddenPractices: [
                    "Demande de mot de passe administrateur (sudo) dans l'application",
                    "Installation d'un daemon d'arrière-plan permanent dans /Library/LaunchDaemons",
                    "Modification ou tentative de nettoyage sous /System ou /private/var",
                    "Usurpation ou contournement des protections SIP de macOS"
                ],
                moraxStrictPractice: "Toute opération nécessitant une élévation de privilèges est présentée sous forme de commande shell explicite à copier et exécuter par vous-même.",
                technicalJustification: "Les malwares comme AMOS cherchent souvent à exploiter les helpers privilégiés mal sécurisés. En refusant tout privilège root, Morax Garage garantit une surface d'attaque nulle."
            ),
            
            DemoSafetyPrinciple(
                id: "rule_3_no_bundled_binaries",
                ruleNumber: 3,
                title: "Aucun binaire tiers précompilé embarqué",
                shortSummary: "Détection et orchestration transparente des outils officiels installés par l'utilisateur.",
                deepExplanation: "Morax Garage n'embarque, ne télécharge et ne vend aucun outil tiers. Il détecte proprement les outils déjà installés via Homebrew (macmon, Mole, Pearcleaner, Stats) et respecte scrupuleusement leurs licences respectives (MIT, GPL-3.0, BSD, Apache 2.0).",
                iconName: "shippingbox.and.arrow.backward.fill",
                forbiddenPractices: [
                    "Embarquer des binaires compilés opaques dans le bundle .app",
                    "Télécharger automatiquement des exécutables depuis Internet sans passer par Homebrew",
                    "Re-packager ou violer les termes de la licence GPL-3.0 de Mole",
                    "Vendre ou commercialiser des fonctionnalités dérivées d'outils avec Commons Clause"
                ],
                moraxStrictPractice: "Détection passive sur le disque et intégration via des canaux propres (flux de données JSON macmon, terminal interactif SwiftTerm, URL Scheme).",
                technicalJustification: "Vous gardez le contrôle total sur les versions et la provenance de vos outils en passant exclusivement par vos taps Homebrew officiels et vérifiés."
            )
        ]
    }
    
    private static func buildFAQItems() -> [DemoFAQItem] {
        return [
            DemoFAQItem(
                category: "Prise en main",
                question: "Par où commencer en tant que nouvel utilisateur ?",
                answer: "Commencez par consulter le 'Dashboard' pour vérifier la santé de votre système et l'état du Swap. Ensuite, explorez 'Storage Map' pour visualiser vos plus gros dossiers, et lancez un scan sécurisé dans 'Cleanup & Cache'.",
                pageLink: "Dashboard"
            ),
            DemoFAQItem(
                category: "Sécurité",
                question: "Puis-je perdre des fichiers de projet importants lors d'un nettoyage ?",
                answer: "Non. Premièrement, les bases de données de projets (comme DaVinci Resolve .drp) sont strictement exclues par le SafetyGate. Deuxièmement, tous les scans sont désélectionnés par défaut : rien n'est supprimé sans votre choix explicite. Troisièmement, tout part dans la Corbeille de macOS, ce qui rend l'opération réversible.",
                pageLink: "Cleanup & Cache"
            ),
            DemoFAQItem(
                category: "Autorisations",
                question: "Pourquoi l'Accès Disque Complet (FDA) est-il recommandé ?",
                answer: "macOS verrouille l'accès aux dossiers de caches des applications (comme DaVinci Resolve ou vos navigateurs) sous ~/Library/Caches. L'Accès Disque Complet permet au scanner de mesurer la taille de ces caches et de vous proposer de les nettoyer.",
                pageLink: "Permissions"
            ),
            DemoFAQItem(
                category: "Outils Tiers",
                question: "Dois-je obligatoirement installer macmon et Mole pour utiliser l'application ?",
                answer: "Non, Morax Garage fonctionne très bien de manière autonome avec ses métriques et scanners natifs ! Installer macmon permet simplement d'ajouter la température GPU et les Watts en direct, tandis que Mole offre une console de nettoyage approfondie.",
                pageLink: "Environment"
            ),
            DemoFAQItem(
                category: "Maintenance",
                question: "À quelle fréquence est-il recommandé de faire un nettoyage ?",
                answer: "Pour un monteur vidéo ou un développeur, un contrôle hebdomadaire de la Storage Map et un nettoyage des caches de rendu terminés ou des vieux node_modules à la fin de chaque gros projet est la routine idéale.",
                pageLink: "Storage Map"
            )
        ]
    }
}
