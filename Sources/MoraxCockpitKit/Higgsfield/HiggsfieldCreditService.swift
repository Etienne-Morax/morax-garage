import Foundation
import Observation

/// Protocole d'exécution de commande pour Higgsfield (mockable pour les tests).
public protocol HiggsfieldCommandExecuting: Sendable {
    func resolveExecutablePath() -> String?
    func execute(arguments: [String], timeout: TimeInterval) async throws -> ProcessResult
}

/// Implémentation de production utilisant `ToolRegistry` et `ProcessRunner`.
public final class DefaultHiggsfieldCommandExecutor: HiggsfieldCommandExecuting, @unchecked Sendable {
    public init() {}
    
    public func resolveExecutablePath() -> String? {
        ToolRegistry.shared.resolveBinaryPath(name: "higgsfield") ??
        ToolRegistry.shared.resolveBinaryPath(name: "hf")
    }
    
    public func execute(arguments: [String], timeout: TimeInterval) async throws -> ProcessResult {
        guard let path = resolveExecutablePath() else {
            throw ProcessRunnerError.processLaunchFailed("Binaire higgsfield / hf introuvable")
        }
        let executableURL = URL(fileURLWithPath: path)
        return try await ProcessRunner.shared.run(
            executableURL: executableURL,
            arguments: arguments,
            timeout: timeout
        )
    }
}

/// Service singleton responsable du suivi des crédits du compte Higgsfield.ai.
@MainActor
@Observable
public final class HiggsfieldCreditService: TelemetryFeedControlling {
    public static let shared = HiggsfieldCreditService()
    
    public static let pollingInterval: TimeInterval = 300.0 // 5 minutes
    public static let requestTimeout: TimeInterval = 8.0  // 8 seconds
    
    public var state: HiggsfieldCreditState = .loading
    public private(set) var cachedSnapshot: HiggsfieldCreditSnapshot?
    public private(set) var availableWorkspaces: [HiggsfieldWorkspaceItem] = []
    public private(set) var isRunning = false
    public private(set) var isRefreshing = false
    
    private let executor: HiggsfieldCommandExecuting
    private let clock: @Sendable () -> Date

    private var pollingTask: Task<Void, Never>?
    private var inFlightRefreshTask: Task<HiggsfieldCreditSnapshot?, Never>?
    private var pollInterval: TimeInterval = HiggsfieldCreditService.pollingInterval
    /// Local time of the last live snapshot (drives the restart freshness gate).
    private var lastSuccessAt: Date?

    public init(
        executor: HiggsfieldCommandExecuting = DefaultHiggsfieldCommandExecutor(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.executor = executor
        self.clock = now
    }

    public var currentDate: Date {
        clock()
    }

    // MARK: - TelemetryFeedControlling

    public func startMonitoring() {
        guard !isRunning else { return }
        isRunning = true
        restartPollingLoop()
    }

    public func stopMonitoring() {
        isRunning = false
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Changes the poll interval. A running loop keeps polling at the new rate.
    public func updateInterval(_ interval: TimeInterval) {
        guard interval > 0 else { return }
        pollInterval = interval
        guard isRunning else { return }
        restartPollingLoop()
    }

    /// (Re)starts the polling loop. A snapshot younger than the interval is served
    /// as is: the first CLI call waits for the remaining time instead of running now.
    private func restartPollingLoop() {
        pollingTask?.cancel()
        let interval = pollInterval
        let firstDelay = FeedFreshness.initialDelay(lastSuccessAt: lastSuccessAt, now: clock(), interval: interval)
        pollingTask = Task { [weak self] in
            if firstDelay > 0 { try? await Task.sleep(for: .seconds(firstDelay)) }
            while !Task.isCancelled {
                guard let self, self.isRunning else { return }
                await self.refresh()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Executes a refresh of Higgsfield credits with deduplication.
    @discardableResult
    public func refresh() async -> HiggsfieldCreditSnapshot? {
        if let existing = inFlightRefreshTask {
            return await existing.value
        }

        isRefreshing = true
        let task = Task<HiggsfieldCreditSnapshot?, Never> { [weak self] () -> HiggsfieldCreditSnapshot? in
            guard let self = self else { return nil }
            return await self.performRefresh()
        }
        inFlightRefreshTask = task
        let snapshot = await task.value
        inFlightRefreshTask = nil
        isRefreshing = false
        return snapshot
    }

    private func performRefresh() async -> HiggsfieldCreditSnapshot? {
        guard let _ = executor.resolveExecutablePath() else {
            let reason = "CLI Higgsfield non détecté (installez le CLI avec `brew install higgsfield` ou npm)"
            return applyFailure(reason: reason, fallback: .cliUnavailable(reason))
        }

        do {
            let result = try await executor.execute(
                arguments: ["account", "status", "--json"],
                timeout: Self.requestTimeout
            )

            // No workspace selected: read the credits from the workspace list instead,
            // without changing the user's CLI selection.
            if !result.isSuccess {
                let combinedErr = "\(result.standardError) \(result.standardOutput)".lowercased()
                if combinedErr.contains("workspace") || combinedErr.contains("no workspace") {
                    if let fromList = await creditsFromWorkspaceList() {
                        return fromList
                    }
                }
                return handleCliError(combinedErr: combinedErr, exitCode: result.exitCode)
            }

            let output = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !output.isEmpty else {
                return handleMalformed(reason: "Sortie JSON vide")
            }

            // Extract JSON object if output contains any surrounding text
            let jsonString: String
            if let firstBrace = output.firstIndex(of: "{"), let lastBrace = output.lastIndex(of: "}") {
                jsonString = String(output[firstBrace...lastBrace])
            } else {
                jsonString = output
            }

            guard let data = jsonString.data(using: .utf8) else {
                return handleMalformed(reason: "Impossible d'encoder la chaîne en UTF-8")
            }

            let decoder = JSONDecoder()
            let accountStatus: HiggsfieldAccountStatus
            do {
                accountStatus = try decoder.decode(HiggsfieldAccountStatus.self, from: data)
            } catch {
                return handleMalformed(reason: "Format JSON non conforme : \(error.localizedDescription)")
            }

            guard let credits = accountStatus.credits else {
                return handleMalformed(reason: "Champ 'credits' manquant dans le statut du compte")
            }

            return publishLive(credits: credits, plan: accountStatus.subscriptionPlanType)

        } catch let error as ProcessRunnerError {
            switch error {
            case .timedOut:
                return applyFailure(reason: "Délai de connexion dépassé (timeout 8s)", fallback: .timeout)

            case .cancelled:
                return cachedSnapshot

            case .processLaunchFailed(let msg):
                let reason = "Échec du lancement : \(msg)"
                return applyFailure(reason: reason, fallback: .error(reason))
            }
        } catch {
            let reason = error.localizedDescription
            return applyFailure(reason: reason, fallback: .error(reason))
        }
    }

    /// Reads the credits of the best workspace from `workspace list --json`.
    /// Read-only: the poll never runs `workspace set`, which would change the
    /// workspace billed by the user's own terminal sessions.
    private func creditsFromWorkspaceList() async -> HiggsfieldCreditSnapshot? {
        do {
            let wsResult = try await executor.execute(
                arguments: ["workspace", "list", "--json"],
                timeout: Self.requestTimeout
            )
            guard wsResult.isSuccess else { return nil }

            let wsOutput = wsResult.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !wsOutput.isEmpty,
                  let startBracket = wsOutput.firstIndex(of: "["),
                  let endBracket = wsOutput.lastIndex(of: "]") else {
                return nil
            }

            let jsonArrayString = String(wsOutput[startBracket...endBracket])
            guard let data = jsonArrayString.data(using: .utf8),
                  let workspaces = try? JSONDecoder().decode([HiggsfieldWorkspaceItem].self, from: data),
                  !workspaces.isEmpty else {
                return nil
            }

            self.availableWorkspaces = workspaces

            // Prefer the selected workspace, then any workspace reporting credits.
            let withCredits = workspaces.filter { $0.credits != nil }
            guard let best = withCredits.first(where: { $0.isSelected == true }) ?? withCredits.first,
                  let credits = best.credits else {
                return nil
            }
            return publishLive(credits: credits, plan: best.planType)
        } catch {
            return nil
        }
    }

    private func publishLive(credits: Double, plan: String?) -> HiggsfieldCreditSnapshot {
        let now = clock()
        let snapshot = HiggsfieldCreditSnapshot(credits: credits, plan: plan, capturedAt: now, isStale: false)
        cachedSnapshot = snapshot
        state = .live(snapshot)
        lastSuccessAt = now
        return snapshot
    }

    /// Marks the last good snapshot stale, or shows `fallback` when there is none.
    private func applyFailure(reason: String, fallback: HiggsfieldCreditState) -> HiggsfieldCreditSnapshot? {
        let newState: HiggsfieldCreditState
        if let old = cachedSnapshot {
            let stale = old.isStale
                ? old
                : HiggsfieldCreditSnapshot(credits: old.credits, plan: old.plan, capturedAt: old.capturedAt, isStale: true)
            if cachedSnapshot != stale { cachedSnapshot = stale }
            newState = .stale(stale, reason: reason)
        } else {
            newState = fallback
        }
        // Assigning an equal value still notifies observers before macOS 26, so a poll
        // that keeps failing the same way would re-render the gauge on every tick.
        if state != newState { state = newState }
        return nil
    }

    private func handleCliError(combinedErr: String, exitCode: Int32) -> HiggsfieldCreditSnapshot? {
        if combinedErr.contains("auth") || combinedErr.contains("login") ||
            combinedErr.contains("not logged in") || combinedErr.contains("unauthorized") ||
            combinedErr.contains("api key") || combinedErr.contains("token") ||
            combinedErr.contains("credentials") {
            let reason = "Session non connectée. Exécutez : higgsfield auth login ou cliquez sur 'Me connecter au compte'"
            return applyFailure(reason: reason, fallback: .unauthenticated(reason))
        }

        if combinedErr.contains("workspace") || combinedErr.contains("no workspace") {
            let reason = "Workspace requis. Sélectionnez un workspace ci-dessous."
            return applyFailure(reason: reason, fallback: .workspaceRequired(reason))
        }

        let reason = "Erreur du CLI Higgsfield (code \(exitCode))"
        return applyFailure(reason: reason, fallback: .error(reason))
    }

    private func handleMalformed(reason: String) -> HiggsfieldCreditSnapshot? {
        applyFailure(reason: reason, fallback: .malformedResponse(reason))
    }

    // MARK: - Workspace & Authentication Helpers
    
    /// Définit le workspace actif via `higgsfield workspace set <id>`.
    @discardableResult
    public func setWorkspace(id: String) async -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            let result = try await executor.execute(
                arguments: ["workspace", "set", trimmed],
                timeout: Self.requestTimeout
            )
            if result.isSuccess {
                await refresh()
                return true
            }
            return false
        } catch {
            return false
        }
    }
    
    /// Réinitialise le workspace vers le compte personnel via `higgsfield workspace unset`.
    @discardableResult
    public func unsetWorkspace() async -> Bool {
        do {
            let result = try await executor.execute(
                arguments: ["workspace", "unset"],
                timeout: Self.requestTimeout
            )
            if result.isSuccess {
                await refresh()
                return true
            }
            return false
        } catch {
            return false
        }
    }
    
    /// Tente de lister les workspaces disponibles via `higgsfield workspace list --json`.
    public func listWorkspaces() async -> [String] {
        do {
            let result = try await executor.execute(
                arguments: ["workspace", "list", "--json"],
                timeout: Self.requestTimeout
            )
            guard result.isSuccess else { return [] }
            if let data = result.standardOutput.data(using: .utf8),
               let list = try? JSONDecoder().decode([HiggsfieldWorkspaceItem].self, from: data) {
                self.availableWorkspaces = list
                return list.map { item in
                    let name = item.name ?? "Privé"
                    return "\(name) (\(item.id))"
                }
            }
            return result.standardOutput
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } catch {
            return []
        }
    }
}
