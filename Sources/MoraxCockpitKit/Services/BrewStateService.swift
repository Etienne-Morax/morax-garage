import Foundation
import Observation

@Observable
@MainActor
public final class BrewStateService {
    public static let shared = BrewStateService()
    
    public private(set) var report: BrewOutdatedReport? = nil
    public private(set) var isLoading: Bool = false
    public private(set) var isScanning: Bool = false
    public private(set) var lastScanDate: Date? = nil
    public private(set) var errorMessage: String? = nil
    
    private let brewService = BrewService.shared
    private var scanTask: Task<Void, Never>? = nil
    
    public init() {}
    
    public var hasLoadedOnce: Bool {
        lastScanDate != nil || report != nil
    }
    
    public func loadOutdated(force: Bool = false) async {
        if !force && hasLoadedOnce {
            return
        }
        
        if report == nil && errorMessage == nil {
            isLoading = true
        }
        isScanning = true
        errorMessage = nil
        
        scanTask?.cancel()
        scanTask = Task.detached(priority: .userInitiated) { [brewService] in
            do {
                let fetchedReport = try await brewService.fetchOutdated()
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.report = fetchedReport
                    self.errorMessage = nil
                    self.lastScanDate = Date()
                    self.isLoading = false
                    self.isScanning = false
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                    self.isScanning = false
                }
            }
        }
        
        await scanTask?.value
    }
}
