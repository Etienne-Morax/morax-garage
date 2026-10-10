import SwiftUI
import MoraxCockpitKit

/// Reads the Full Disk Access state without pulling its observation into the
/// enclosing view.
///
/// `PermissionsService` is a singleton that several screens depend on. Observing it
/// at the top of a screen meant a permission re-check invalidated that entire screen,
/// so the dependency is narrowed to the small piece of interface that reacts to it.
struct FullDiskAccessObserver<Content: View>: View {
    private var permissionsService = PermissionsService.shared

    private let content: (Bool, PermissionsService) -> Content

    init(@ViewBuilder content: @escaping (Bool, PermissionsService) -> Content) {
        self.content = content
    }

    var body: some View {
        content(permissionsService.hasFullDiskAccess, permissionsService)
    }
}
