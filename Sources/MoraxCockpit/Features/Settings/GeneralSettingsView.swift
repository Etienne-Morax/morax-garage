import SwiftUI
import MoraxCockpitKit

public struct GeneralSettingsView: View {
    @Bindable private var appSettings = AppSettings.shared
    private var updateService = UpdateService.shared
    @AppStorage("morax_appearance_mode") private var appearanceMode: AppAppearanceMode = .system
    @AppStorage(MetaMuseManualQuota.percentKey) private var manualPercent: Double = MetaMuseManualQuota.unset
    @AppStorage(MetaMuseManualQuota.updatedAtKey) private var manualUpdatedAt: Double = 0
    @State private var moleInstalled: Bool = false
    @State private var brewInstalled: Bool = false
    @State private var brewPath: String = "Recherche..."
    @State private var higgsfieldInstalled: Bool = false
    @State private var higgsfieldPath: String = "Recherche..."
    @State private var usageKey: String = UsageQuotaCredentials.read() ?? ""
    @State private var usageConnectionStatus: String?
    @State private var openAIAdminKey: String = OpenAIAdminCredentials.read() ?? ""
    @AppStorage(OpenAICostsService.projectIDDefaultsKey) private var openAIProjectID: String = ""
    private var openAICostsService = OpenAICostsService.shared
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Banner
                headerBanner
                
                // Screenshot feature 1: Stats & System Core Settings Card
                statsCoreSettingsSection
                
                // Screenshot feature 2: Menu Bar Display Items Selector ("Cocher ce qu'on veut voir en haut")
                menuBarDisplaySection
                
                // Mini Cockpit HUD Flottant Always-On Section
                miniCockpitSection
                
                // 3. Theme & Appearance
                appearanceSection
                
                // 4. Real-Time Telemetry & Monitoring Services
                telemetrySection

                usageQuotaSection
                
                // 5. System Integrations & Health
                systemHealthSection
                
                // 6. Privacy & Safety Guarantees
                privacySafetySection
                
                // 7. About Cockpit
                aboutSection
            }
            .padding(24)
        }
        .background(CleanMyMacBackground())
        .onAppear {
            checkInstalledTools()
            appSettings.syncLaunchAtLoginStatus()
        }
        .onChange(of: appSettings.miniCockpitEnabled) { _, enabled in
            if enabled {
                MiniCockpitWindowController.shared.showMiniCockpit(onOpenMainWindow: {
                    MainWindowOpener.shared.open()
                })
            } else {
                MiniCockpitWindowController.shared.hideMiniCockpit()
            }
        }
        .onChange(of: appSettings.miniCockpitAlwaysOnTop) { _, enabled in
            MiniCockpitWindowController.shared.applyAlwaysOnTop(enabled)
        }
        .onChange(of: appSettings.miniCockpitAllSpaces) { _, enabled in
            MiniCockpitWindowController.shared.applyAllSpaces(enabled)
        }
    }

    private var usageQuotaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compteurs IA").font(.headline).foregroundStyle(MoraxTheme.textPrimary)
            Text("Lecture authentifiée des forfaits Claude, ChatGPT / Codex, Gemini / Antigravity et des dépenses DeepSeek / OpenAI API.")
                .font(.caption).foregroundStyle(MoraxTheme.textSecondary)
            TextField("URL du cockpit", text: $appSettings.usageCockpitBaseURL)
                .textFieldStyle(.roundedBorder)
            SecureField("Clé interne", text: $usageKey)
                .textFieldStyle(.roundedBorder)
                .onSubmit { _ = UsageQuotaCredentials.write(usageKey) }
            HStack {
                Toggle("Afficher la carte sur le Dashboard", isOn: $appSettings.usageQuotasEnabled)
                Spacer()
                Button("Tester la connexion") { testUsageConnection() }
                    .disabled(appSettings.usageCockpitURL == nil || usageKey.isEmpty)
            }
            if let usageConnectionStatus {
                Text(usageConnectionStatus).font(.caption).foregroundStyle(MoraxTheme.textSecondary)
            }
            
            Divider().overlay(MoraxTheme.border.opacity(0.8))

            openAICostsSettings

            Divider().overlay(MoraxTheme.border.opacity(0.8))
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Higgsfield.ai").font(.subheadline.weight(.semibold)).foregroundStyle(MoraxTheme.textPrimary)
                Text("Suivi du solde de crédits et de l'abonnement via le CLI officiel (`higgsfield account status --json`).")
                    .font(.caption).foregroundStyle(MoraxTheme.textSecondary)
                Toggle("Activer le suivi des crédits Higgsfield", isOn: $appSettings.higgsfieldMonitoringEnabled)
            }

            Divider().overlay(MoraxTheme.border.opacity(0.8))

            VStack(alignment: .leading, spacing: 6) {
                Text("Muse Code (Meta)").font(.subheadline.weight(.semibold)).foregroundStyle(MoraxTheme.textPrimary)
                Text("La jauge affiche le % relevé à la main depuis la page Usage officielle (aucun endpoint auto).")
                    .font(.caption).foregroundStyle(MoraxTheme.textSecondary)
                Toggle("Activer le compteur Muse Code", isOn: $appSettings.metamuseMonitoringEnabled)
                HStack(spacing: 8) {
                    Text("Utilisé :")
                        .font(.caption).foregroundStyle(MoraxTheme.textSecondary)
                    Slider(value: Binding(
                        get: { max(0, manualPercent) },
                        set: { newValue in
                            manualPercent = newValue
                            manualUpdatedAt = Date().timeIntervalSince1970
                        }
                    ), in: 0...100, step: 1)
                    Text(manualPercent >= 0 ? MetaMuseManualQuota.formatted(manualPercent) : "—")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MoraxTheme.textPrimary)
                        .frame(minWidth: 44, alignment: .trailing)
                }
                HStack(spacing: 8) {
                    TextField("Project ID", text: $appSettings.metamuseProjectID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                    TextField("Team ID", text: $appSettings.metamuseTeamID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                }
                Text("IDs visibles dans l'URL de la page Usage : `dev.meta.ai/usage/?project_id=…&team_id=…`.")
                    .font(.caption).foregroundStyle(MoraxTheme.textMuted)
            }
        }
        .padding(16)
        .background(MoraxTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(MoraxTheme.border, lineWidth: 1))
    }

    private var openAICostsSettings: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OpenAI API").font(.subheadline.weight(.semibold)).foregroundStyle(MoraxTheme.textPrimary)
            Text("Montant facturé depuis le 1er du mois, relevé chez OpenAI (`/v1/organization/costs`). Une clé admin d'organisation est requise : les clés de projet `sk-proj-…` sont refusées.")
                .font(.caption).foregroundStyle(MoraxTheme.textSecondary)
            SecureField("Clé admin OpenAI (sk-admin-…)", text: $openAIAdminKey)
                .textFieldStyle(.roundedBorder)
                .onSubmit { saveOpenAIAdminKey() }
            HStack(spacing: 8) {
                TextField("Project ID (optionnel, sinon toute l'organisation)", text: $openAIProjectID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                Button("Enregistrer et relever") { saveOpenAIAdminKey() }
            }
            if let error = openAICostsService.lastError {
                Text(error).font(.caption).foregroundStyle(MoraxTheme.oxbloodRed)
            } else if let spend = openAICostsService.spend {
                Text("Relevé OK : \((spend.balanceSpendUsd ?? spend.costUsd).formatted(.currency(code: "USD"))) ce mois-ci")
                    .font(.caption).foregroundStyle(MoraxTheme.textSecondary)
            }
        }
    }

    private func saveOpenAIAdminKey() {
        _ = OpenAIAdminCredentials.write(openAIAdminKey)
        Task {
            await openAICostsService.refresh()
            if openAICostsService.isConfigured { openAICostsService.startMonitoring() }
            else { openAICostsService.stopMonitoring() }
        }
    }

    private func testUsageConnection() {
        guard let baseURL = appSettings.usageCockpitURL else { return }
        _ = UsageQuotaCredentials.write(usageKey)
        guard UsageQuotaService.isAllowedEndpoint(baseURL) else {
            usageConnectionStatus = UsageQuotaService.insecureEndpointMessage
            return
        }
        var request = URLRequest(url: baseURL.appending(path: "api/usage/quotas"), timeoutInterval: 8)
        request.setValue(usageKey, forHTTPHeaderField: "X-Internal-Key")
        usageConnectionStatus = "Test en cours…"
        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                await MainActor.run { usageConnectionStatus = status == 200 ? "Connexion OK (200)" : "Réponse du cockpit : HTTP \(status)" }
            } catch {
                await MainActor.run { usageConnectionStatus = "Cockpit injoignable : \(error.localizedDescription)" }
            }
        }
    }
    
    // MARK: - Header Banner
    private var headerBanner: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(MoraxTheme.surfaceSubtle)
                    .frame(width: 52, height: 52)
                
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(MoraxTheme.infoBlue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Général & Préférences")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    
                    Text("COCKPIT CORE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(MoraxTheme.infoBlue.opacity(0.18))
                        .foregroundStyle(MoraxTheme.infoBlue)
                        .clipShape(.rect(cornerRadius: 4))
                }
                
                Text("Configurez la visibilité du Dock, l'affichage dans la barre des menus, les sondes et les préférences système.")
                    .font(.subheadline)
                    .foregroundStyle(MoraxTheme.textSecondary)
            }
            
            Spacer()
        }
        .padding(18)
        .background(MoraxTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
    }
    
    // MARK: - Stats & System Core Settings Section (Faithful to Screenshot)
    private var statsCoreSettingsSection: some View {
        VStack(spacing: 16) {
            // Centered App Header (Stats-style)
            VStack(spacing: 6) {
                MoraxMascotView(size: 44)
                
                Text("Stats & Cockpit")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(MoraxTheme.textPrimary)
                
                let versionText = updateService.lastCheckInfo != nil 
                    ? "Version \(updateService.lastCheckInfo!.currentVersion) (Build \(updateService.lastCheckInfo!.currentBuild))"
                    : "Version 1.0.0 (Build 3011)"
                
                Text(versionText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(MoraxTheme.textSecondary)
                
                // Update button
                Button(action: checkForUpdates) {
                    HStack(spacing: 6) {
                        if updateService.isChecking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(updateService.isChecking ? "Recherche en cours..." : "Vérifier les mises à jour")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(MoraxTheme.surfaceSubtle)
                    .foregroundStyle(MoraxTheme.textPrimary)
                    .clipShape(.rect(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(MoraxTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(updateService.isChecking)
                .padding(.top, 4)
                
                if let info = updateService.lastCheckInfo {
                    VStack(spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(MoraxTheme.successGreen)
                            Text(info.message)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(MoraxTheme.successGreen)
                        }
                        
                        Text("Dernière vérification : \(UpdateService.formatDate(info.lastCheckedDate))")
                            .font(.system(size: 10))
                            .foregroundStyle(MoraxTheme.textSecondary)
                    }
                    .padding(.top, 4)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            
            // Grouped Options List (Screenshot layout)
            VStack(spacing: 0) {
                // 1. Vérifier les mises à jour (Dropdown)
                HStack {
                    Text("Vérifier les mises à jour")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    
                    Spacer()
                    
                    Picker("", selection: $appSettings.updateCheckFrequency) {
                        ForEach(UpdateCheckFrequency.allCases) { freq in
                            Text(freq.rawValue).tag(freq)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 140)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                
                Divider().overlay(MoraxTheme.border.opacity(0.8))
                
                // 2. Température (Dropdown)
                HStack {
                    Text("Température")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    
                    Spacer()
                    
                    Picker("", selection: $appSettings.temperatureUnit) {
                        ForEach(TemperatureUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 140)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                
                Divider().overlay(MoraxTheme.border.opacity(0.8))
                
                // 3. Afficher l'icône dans le Dock (Toggle)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Afficher l'icône dans le Dock")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MoraxTheme.textPrimary)
                        Text("Désactivez pour masquer l'application du Dock et l'exécuter discrètement en barre des menus")
                            .font(.system(size: 10))
                            .foregroundStyle(MoraxTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $appSettings.showDockIcon)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                
                Divider().overlay(MoraxTheme.border.opacity(0.8))
                
                // 4. Démarrer à l'ouverture de la session (Toggle)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Démarrer à l'ouverture de la session")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MoraxTheme.textPrimary)
                        Text("Lance automatiquement Morax Garage au démarrage de votre Mac")
                            .font(.system(size: 10))
                            .foregroundStyle(MoraxTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $appSettings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                
                Divider().overlay(MoraxTheme.border.opacity(0.8))
                
                // 5. Keep the menubar items position (Toggle)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep the menubar items position")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MoraxTheme.textPrimary)
                        Text("Préserve l'ordre et la position d'ancrage des modules dans la barre des menus")
                            .font(.system(size: 10))
                            .foregroundStyle(MoraxTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $appSettings.keepMenuBarPosition)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                
                Divider().overlay(MoraxTheme.border.opacity(0.8))
                
                // 6. macOS widgets (Toggle)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("macOS widgets")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MoraxTheme.textPrimary)
                        Text("Active les extensions et widgets interactifs de bureau macOS")
                            .font(.system(size: 10))
                            .foregroundStyle(MoraxTheme.textSecondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $appSettings.macosWidgetsEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
            }
            .background(MoraxTheme.surface)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(MoraxTheme.border, lineWidth: 1)
            )
        }
        .padding(18)
        .background(MoraxTheme.surface.opacity(0.5))
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
    }
    
    // MARK: - Menu Bar Display Items Configuration ("Cocher ce qu'on veut voir en haut")
    private var menuBarDisplaySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MoraxTheme.infoBlue)
                
                Text("Affichage dans la barre des menus (En haut)")
                    .font(.headline)
                    .foregroundStyle(MoraxTheme.textPrimary)
                
                Spacer()
                
                Text("LIVE SYNC")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(MoraxTheme.infoBlue.opacity(0.18))
                    .foregroundStyle(MoraxTheme.infoBlue)
                    .clipShape(.rect(cornerRadius: 4))
            }
            
            Text("Cochez les métriques et indicateurs que vous souhaitez afficher en haut dans la barre des menus macOS :")
                .font(.subheadline)
                .foregroundStyle(MoraxTheme.textSecondary)
            
            // Live Simulation Preview Bar
            VStack(alignment: .leading, spacing: 6) {
                Text("APERÇU EN DIRECT DANS LA BARRE DES MENUS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(MoraxTheme.textSecondary)
                
                HStack(spacing: 12) {
                    Spacer()
                    
                    // The live preview of the menubar label
                    MoraxMenuBarLabel(
                        settings: appSettings,
                        metrics: SystemMetricsService.shared,
                        networkMetrics: NetworkMetricsService.shared
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 5))
                    
                    Text("13:42")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.75))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
            }
            .padding(.bottom, 6)
            
            // Checkboxes / Toggles List
            VStack(spacing: 0) {
                menuBarItemRow(
                    icon: "menubar.rectangle",
                    title: "Élément dans la barre des menus",
                    subtitle: "Affiche Morax Garage près de l'heure, en haut de l'écran",
                    isOn: $appSettings.menuBarEnabled
                )

                Divider().overlay(MoraxTheme.border.opacity(0.8))

                menuBarItemRow(
                    icon: "wrench.adjustable.fill",
                    title: "Icône de l'application",
                    subtitle: "Affiche la clé à molette Morax Garage dans la barre",
                    isOn: $appSettings.menuBarShowIcon
                )
                
                Divider().overlay(MoraxTheme.border.opacity(0.8))
                
                menuBarItemRow(
                    icon: "cpu",
                    title: "Utilisation Processeur (CPU)",
                    subtitle: "Pourcentage de charge processeur en temps réel (ex: CPU 14%)",
                    isOn: $appSettings.menuBarShowCpu
                )
                
                Divider().overlay(MoraxTheme.border.opacity(0.8))
                
                menuBarItemRow(
                    icon: "memorychip",
                    title: "Mémoire Vive (RAM)",
                    subtitle: "Consommation mémoire active (ex: 8,4 Go)",
                    isOn: $appSettings.menuBarShowRam
                )
                
                Divider().overlay(MoraxTheme.border.opacity(0.8))
                
                menuBarItemRow(
                    icon: "network",
                    title: "Débit Réseau (Bandwidth)",
                    subtitle: "Vitesses instantanées de téléchargement et d'envoi (↓/↑)",
                    isOn: $appSettings.menuBarShowNetwork
                )
                
                Divider().overlay(MoraxTheme.border.opacity(0.8))
                
                menuBarItemRow(
                    icon: "thermometer.medium",
                    title: "Température Système",
                    subtitle: "Température matérielle formatée selon l'unité choisie (°C / °F)",
                    isOn: $appSettings.menuBarShowTemperature
                )
                
                Divider().overlay(MoraxTheme.border.opacity(0.8))
                
                menuBarItemRow(
                    icon: "externaldrive",
                    title: "Espace Disque (SSD)",
                    subtitle: "Volume d'espace libre restant sur le disque principal",
                    isOn: $appSettings.menuBarShowDisk
                )
                
                Divider().overlay(MoraxTheme.border.opacity(0.8))
                
                menuBarItemRow(
                    icon: "exclamationmark.triangle.fill",
                    title: "Alerte SWAP critique",
                    subtitle: "Badge rouge clignotant lorsque le swap dépasse 2 Go (DaVinci / Montage)",
                    isOn: $appSettings.menuBarShowSwapAlert
                )
            }
            .background(MoraxTheme.surface)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(MoraxTheme.border, lineWidth: 1)
            )
        }
        .padding(18)
        .background(MoraxTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
    }
    
    private func menuBarItemRow(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(isOn.wrappedValue ? MoraxTheme.infoBlue : MoraxTheme.textSecondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MoraxTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(MoraxTheme.textSecondary)
            }
            
            Spacer()
            
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    // MARK: - Mini Cockpit HUD Section
    private var miniCockpitSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MoraxTheme.electricCyan)
                
                Text("Mini Cockpit (HUD Flottant Always-On)")
                    .font(.headline)
                    .foregroundStyle(MoraxTheme.textPrimary)
                
                Spacer()
                
                Text("ALWAYS-ON")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(MoraxTheme.electricCyan.opacity(0.18))
                    .foregroundStyle(MoraxTheme.electricCyan)
                    .clipShape(.rect(cornerRadius: 4))
            }
            
            Text("Affichez un moniteur compact et ultra-léger dans un coin de votre écran pour suivre l'état de votre Mac à tout instant :")
                .font(.subheadline)
                .foregroundStyle(MoraxTheme.textSecondary)
            
            VStack(spacing: 0) {
                menuBarItemRow(
                    icon: "macwindow.on.rectangle",
                    title: "Activer le Mini Cockpit HUD",
                    subtitle: "Fait apparaître la fenêtre miniature Always-On",
                    isOn: $appSettings.miniCockpitEnabled
                )
                
                Divider().overlay(MoraxTheme.border.opacity(0.8))
                
                menuBarItemRow(
                    icon: "arrow.up.and.line.horizontal.and.arrow.down",
                    title: "Toujours au premier plan",
                    subtitle: "Maintient le Mini Cockpit au-dessus des autres fenêtres applicatives",
                    isOn: $appSettings.miniCockpitAlwaysOnTop
                )
                
                Divider().overlay(MoraxTheme.border.opacity(0.8))
                
                menuBarItemRow(
                    icon: "square.grid.2x2",
                    title: "Afficher sur tous les Spaces",
                    subtitle: "Rend le HUD visible sur tous les bureaux virtuels et en plein écran",
                    isOn: $appSettings.miniCockpitAllSpaces
                )
                
                Divider().overlay(MoraxTheme.border.opacity(0.8))
                
                HStack {
                    HStack(spacing: 12) {
                        Image(systemName: appSettings.miniCockpitAppearance.iconName)
                            .font(.system(size: 14))
                            .foregroundStyle(MoraxTheme.electricCyan)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Thème d'apparence")
                                .font(.body.weight(.medium))
                                .foregroundStyle(MoraxTheme.textPrimary)
                            
                            Text("Affichage en mode Clair, Sombre ou Automatique (suit macOS)")
                                .font(.caption)
                                .foregroundStyle(MoraxTheme.textSecondary)
                        }
                    }
                    
                    Spacer()
                    
                    Picker("", selection: $appSettings.miniCockpitAppearance) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 230)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(MoraxTheme.surface)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(MoraxTheme.border, lineWidth: 1)
            )
        }
        .padding(18)
        .background(MoraxTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
    }
    
    // MARK: - Update Check Logic
    private func checkForUpdates() {
        Task {
            await updateService.checkForUpdates(manual: true)
        }
    }
    
    // MARK: - Appearance Section
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "circle.lefthalf.filled")
                    .foregroundStyle(MoraxTheme.infoBlue)
                Text("Apparence & Thème")
                    .font(.headline)
                    .foregroundStyle(MoraxTheme.textPrimary)
            }
            
            HStack(spacing: 14) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appearanceMode = mode
                        }
                    }) {
                        VStack(spacing: 10) {
                            HStack {
                                Image(systemName: mode.iconName)
                                    .font(.system(size: 16, weight: .bold))
                                Spacer()
                                if appearanceMode == mode {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(MoraxTheme.infoBlue)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.rawValue)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(MoraxTheme.textPrimary)
                                
                                Text(description(for: mode))
                                    .font(.system(size: 11))
                                    .foregroundStyle(MoraxTheme.textSecondary)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(14)
                        .background(appearanceMode == mode ? MoraxTheme.infoBlue.opacity(0.12) : MoraxTheme.surface)
                        .clipShape(.rect(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(appearanceMode == mode ? MoraxTheme.infoBlue : MoraxTheme.border, lineWidth: appearanceMode == mode ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background(MoraxTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
    }
    
    private func description(for mode: AppAppearanceMode) -> String {
        switch mode {
        case .system: return "Suit automatiquement le mode sombre/clair de macOS."
        case .light: return "Thème clair contrasté optimisé pour la journée."
        case .dark: return "Thème sombre Morax Garage haute visibilité."
        }
    }
    
    // MARK: - Telemetry Section
    private var telemetrySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(MoraxTheme.successGreen)
                Text("Télémétrie & Sondes Système")
                    .font(.headline)
                    .foregroundStyle(MoraxTheme.textPrimary)
                
                Spacer()
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(MoraxTheme.successGreen)
                        .frame(width: 8, height: 8)
                    Text("Actif en temps réel")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MoraxTheme.successGreen)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(MoraxTheme.successGreen.opacity(0.12))
                .clipShape(.capsule)
            }
            
            VStack(spacing: 10) {
                telemetryRow(
                    name: "Sonde Métriques Système (CPU & RAM)",
                    interval: "Échantillonnage : 1.0 s",
                    status: "En direct",
                    icon: "cpu"
                )
                
                Divider().overlay(MoraxTheme.border)
                
                telemetryRow(
                    name: "Sonde Télémétrie Cache & Espace Disque",
                    interval: "Échantillonnage : 5.0 s",
                    status: "En direct",
                    icon: "externaldrive"
                )
                
                Divider().overlay(MoraxTheme.border)
                
                telemetryRow(
                    name: "Sonde Débit Réseau (Live Network Bandwidth)",
                    interval: "Échantillonnage : 1.0 s",
                    status: "En direct",
                    icon: "network"
                )
            }
        }
        .padding(18)
        .background(MoraxTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
    }
    
    private func telemetryRow(name: String, interval: String, status: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(MoraxTheme.textSecondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MoraxTheme.textPrimary)
                Text(interval)
                    .font(.system(size: 11))
                    .foregroundStyle(MoraxTheme.textSecondary)
            }
            
            Spacer()
            
            Text(status)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MoraxTheme.successGreen)
                .padding(.horizontal, 8)
                .padding(.vertical, 2.5)
                .background(MoraxTheme.successGreen.opacity(0.12))
                .clipShape(.rect(cornerRadius: 4))
        }
    }
    
    // MARK: - System Integrations Section
    private var systemHealthSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "puzzlepiece.extension")
                    .foregroundStyle(MoraxTheme.warningAmber)
                Text("État des Outils & Autorisations")
                    .font(.headline)
                    .foregroundStyle(MoraxTheme.textPrimary)
            }
            
            VStack(spacing: 10) {
                FullDiskAccessObserver { hasFullDiskAccess, permissionsService in
                    toolHealthRow(
                        name: "Accès Disque Complet (Full Disk Access)",
                        detail: hasFullDiskAccess ? "Autorisation accordée (analyse complète des caches)" : "Accès restreint aux dossiers système",
                        isGood: hasFullDiskAccess,
                        actionTitle: hasFullDiskAccess ? nil : "Régler",
                        onAction: {
                            permissionsService.openSystemSettings(for: .fullDiskAccess)
                        }
                    )
                }
                
                Divider().overlay(MoraxTheme.border)
                
                toolHealthRow(
                    name: "Homebrew CLI",
                    detail: brewInstalled ? "Détecté : \(brewPath)" : "Non installé sur le chemin par défaut",
                    isGood: brewInstalled,
                    actionTitle: nil,
                    onAction: nil
                )
                
                Divider().overlay(MoraxTheme.border)
                
                toolHealthRow(
                    name: "Mole CLI (`mo`)",
                    detail: moleInstalled ? "Disponible pour les commandes rapides" : "Optionnel : `brew install tw93/tap/mole`",
                    isGood: moleInstalled,
                    actionTitle: nil,
                    onAction: nil
                )
                
                Divider().overlay(MoraxTheme.border)
                
                toolHealthRow(
                    name: "Higgsfield CLI (`higgsfield` / `hf`)",
                    detail: higgsfieldInstalled ? "Détecté : \(higgsfieldPath)" : "Optionnel : `brew install higgsfield-ai/tap/higgsfield`",
                    isGood: higgsfieldInstalled,
                    actionTitle: higgsfieldInstalled ? nil : "Installer",
                    onAction: {
                        if let url = URL(string: "https://github.com/higgsfield-ai/cli") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
            }
        }
        .padding(18)
        .background(MoraxTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
    }
    
    private func toolHealthRow(
        name: String,
        detail: String,
        isGood: Bool,
        actionTitle: String?,
        onAction: (() -> Void)?
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isGood ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isGood ? MoraxTheme.successGreen : MoraxTheme.warningAmber)
                .font(.system(size: 16))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MoraxTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(MoraxTheme.textSecondary)
            }
            
            Spacer()
            
            if let title = actionTitle, let action = onAction {
                Button(action: action) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
    
    // MARK: - Privacy & Safety Section
    private var privacySafetySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(MoraxTheme.successGreen)
                Text("Engagements de Sécurité & Confidentialité")
                    .font(.headline)
                    .foregroundStyle(MoraxTheme.textPrimary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                safetyBullet(
                    icon: "network.slash",
                    title: "100% Local & Hors-Ligne",
                    detail: "Aucune donnée personnelle, liste de fichiers ou métrique de télémétrie n'est envoyée vers un serveur."
                )
                
                safetyBullet(
                    icon: "trash",
                    title: "Nettoyage Sécurisé & Réversible",
                    detail: "Les nettoyages applicatifs déplacent les fichiers vers la Corbeille macOS (`~/.Trash`) pour permettre une récupération facile."
                )
                
                safetyBullet(
                    icon: "shield.lefthalf.filled",
                    title: "Préservation des Fichiers Système",
                    detail: "Les dossiers protégés de macOS (SIP, System, Library/Preferences critiques) sont exclus par défaut des opérations destructives."
                )
            }
        }
        .padding(18)
        .background(MoraxTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
    }
    
    private func safetyBullet(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(MoraxTheme.infoBlue)
                .frame(width: 18, height: 18)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MoraxTheme.textPrimary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(MoraxTheme.textSecondary)
            }
        }
    }
    
    // MARK: - About Section
    private var aboutSection: some View {
        HStack(spacing: 16) {
            MoraxMascotView(size: 38)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("MORAX GARAGE")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(MoraxTheme.textPrimary)
                Text("Mac Maintenance Garage — Version 1.0.0 (Native Swift & SwiftUI)")
                    .font(.system(size: 11))
                    .foregroundStyle(MoraxTheme.textSecondary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(MoraxTheme.surfaceSubtle)
        .clipShape(.rect(cornerRadius: 8))
    }
    
    private func checkInstalledTools() {
        let fileManager = FileManager.default
        let homebrewArm = "/opt/homebrew/bin/brew"
        let homebrewIntel = "/usr/local/bin/brew"
        
        if fileManager.fileExists(atPath: homebrewArm) {
            brewInstalled = true
            brewPath = homebrewArm
        } else if fileManager.fileExists(atPath: homebrewIntel) {
            brewInstalled = true
            brewPath = homebrewIntel
        } else {
            brewInstalled = false
            brewPath = "Non détecté"
        }
        
        let moleArm = "/opt/homebrew/bin/mo"
        let moleIntel = "/usr/local/bin/mo"
        let moleUser = ("~/.local/bin/mo" as NSString).expandingTildeInPath
        
        moleInstalled = fileManager.fileExists(atPath: moleArm) ||
                         fileManager.fileExists(atPath: moleIntel) ||
                         fileManager.fileExists(atPath: moleUser)
        
        if let hfPath = ToolRegistry.shared.resolveBinaryPath(name: "higgsfield") ?? ToolRegistry.shared.resolveBinaryPath(name: "hf") {
            higgsfieldInstalled = true
            higgsfieldPath = hfPath
        } else {
            higgsfieldInstalled = false
            higgsfieldPath = "Non détecté"
        }
    }
}
