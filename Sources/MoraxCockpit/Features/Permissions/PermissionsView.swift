import SwiftUI
import MoraxCockpitKit

public struct PermissionsView: View {
    private var service = PermissionsService.shared
    @State private var showingInstructions = false
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .font(.title)
                            .foregroundStyle(service.hasFullDiskAccess ? MoraxTheme.successGreen : MoraxTheme.warningAmber)
                        
                        Text("System Permissions & Security")
                            .font(.title2)
                            .bold()
                            .foregroundStyle(MoraxTheme.textPrimary)
                        
                        Spacer()
                        
                        Button("Re-check Permissions", systemImage: "arrow.clockwise") {
                            service.checkAllPermissions()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Text("Morax Garage requires specific macOS system authorizations to safely scan and clean DaVinci Resolve caches, developer build artifacts, and installer files.")
                        .font(.subheadline)
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
                
                // Full Disk Access Hero Banner
                fullDiskAccessHeroCard
                
                // Permissions List
                VStack(alignment: .leading, spacing: 14) {
                    Text("Authorization Checklist")
                        .font(.headline)
                        .foregroundStyle(MoraxTheme.textPrimary)
                    
                    LazyVStack(spacing: 12) {
                        ForEach(service.permissions) { record in
                            PermissionCardRow(record: record) {
                                service.openSystemSettings(for: record.type)
                            } onTrigger: {
                                service.triggerFolderAccessPrompt(for: record.type)
                            }
                        }
                    }
                }
                
                // Setup Guide Footer
                setupGuideCard
            }
            .padding(24)
        }
        .background(CleanMyMacBackground())
        .onAppear {
            service.checkAllPermissions()
        }
    }
    
    private var fullDiskAccessHeroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: service.hasFullDiskAccess ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(service.hasFullDiskAccess ? MoraxTheme.successGreen : MoraxTheme.oxbloodRed)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Full Disk Access (FDA)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(MoraxTheme.textPrimary)
                        
                        Text(service.hasFullDiskAccess ? "ENABLED" : "RECOMMENDED")
                            .font(.system(size: 10, weight: .black))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(service.hasFullDiskAccess ? MoraxTheme.successGreen.opacity(0.15) : MoraxTheme.oxbloodRed.opacity(0.15))
                            .foregroundStyle(service.hasFullDiskAccess ? MoraxTheme.successGreen : MoraxTheme.oxbloodRed)
                            .clipShape(.rect(cornerRadius: 4))
                    }
                    
                    Text(service.hasFullDiskAccess
                         ? "Full Disk Access is active. The cockpit can scan DaVinci Resolve render caches, Lightroom previews, and audit system LaunchAgents without permission bottlenecks."
                         : "Without Full Disk Access, macOS TCC may block or silently skip DaVinci Resolve application support caches (~/Library), photo app previews, and LaunchAgent audits.")
                        .font(.callout)
                        .foregroundStyle(MoraxTheme.textSecondary)
                }
                
                Spacer()
            }
            
            Divider().overlay(MoraxTheme.border)
            
            HStack {
                if !service.hasFullDiskAccess {
                    Button("Open Full Disk Access Settings...", systemImage: "gearshape.fill") {
                        service.openAllFilesSettings()
                    }
                    .fontWeight(.semibold)
                    .buttonStyle(.borderedProminent)
                    .tint(MoraxTheme.infoBlue)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.open.fill")
                            .foregroundStyle(MoraxTheme.successGreen)
                        Text("Optimal working conditions active")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(MoraxTheme.successGreen)
                    }
                }
                
                Spacer()
                
                Button(showingInstructions ? "Hide Guide" : "How to enable", systemImage: "info.circle") {
                    showingInstructions.toggle()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(MoraxTheme.infoBlue)
            }
            
            if showingInstructions {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to grant Full Disk Access on macOS:")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Click **Open Full Disk Access Settings...** above.")
                        Text("2. Locate **Morax Garage** in the list and toggle the switch to ON.")
                        Text("3. If it is not listed, click the **+** button and select **Morax Garage.app** from `/Applications`.")
                        Text("4. Switch back here; permissions will refresh automatically.")
                    }
                    .font(.caption)
                    .foregroundStyle(MoraxTheme.textSecondary)
                }
                .padding(12)
                .background(MoraxTheme.surfaceSubtle)
                .clipShape(.rect(cornerRadius: 6))
            }
        }
        .padding(20)
        .background(MoraxTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(service.hasFullDiskAccess ? MoraxTheme.successGreen.opacity(0.3) : MoraxTheme.oxbloodRed.opacity(0.4), lineWidth: 1.5)
        )
        .clipShape(.rect(cornerRadius: 10))
    }
    
    private var setupGuideCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(MoraxTheme.infoBlue)
                Text("Zero Elevation & Privacy Commitment")
                    .font(.headline)
                    .foregroundStyle(MoraxTheme.textPrimary)
            }
            
            Text("Morax Garage adheres to a strict non-elevated safety model: no root privileges, no background daemon, no analytics, and all file deletions use macOS Trash recovery.")
                .font(.caption)
                .foregroundStyle(MoraxTheme.textSecondary)
        }
        .padding(16)
        .background(MoraxTheme.surfaceSubtle)
        .clipShape(.rect(cornerRadius: 8))
    }
}

private struct PermissionCardRow: View {
    let record: PermissionRecord
    let onOpenSettings: () -> Void
    let onTrigger: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: record.type.iconName)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(record.type.rawValue)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(MoraxTheme.textPrimary)
                    
                    if record.type.isCritical {
                        Text("ESSENTIAL")
                            .font(.system(size: 9, weight: .black))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(MoraxTheme.surfaceSubtle)
                            .foregroundStyle(MoraxTheme.textSecondary)
                            .clipShape(.rect(cornerRadius: 4))
                    }
                }
                
                Text(record.type.roleDescription)
                    .font(.caption)
                    .foregroundStyle(MoraxTheme.textSecondary)
                
                Text(record.details)
                    .font(.caption2)
                    .foregroundStyle(record.status == .granted ? MoraxTheme.successGreen : MoraxTheme.textMuted)
                    .padding(.top, 2)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 8) {
                // Status badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(record.status.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.12))
                .clipShape(.rect(cornerRadius: 6))
                
                if record.status != .granted {
                    Button("Configure", systemImage: "arrow.up.forward.app", action: onOpenSettings)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(16)
        .background(isHovered ? MoraxTheme.surfaceSubtle : MoraxTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(MoraxTheme.border, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 8))
        .onHover { isHovered = $0 }
    }
    
    private var statusColor: Color {
        switch record.status {
        case .granted:
            return MoraxTheme.successGreen
        case .notDetermined, .denied:
            return record.type.isCritical ? MoraxTheme.oxbloodRed : MoraxTheme.warningAmber
        case .notRequired:
            return MoraxTheme.textSecondary
        }
    }
}
