import AppKit
import Quartz

/// Shows a file in the Quick Look panel without ever opening or launching it.
///
/// `NSWorkspace.open` would run a `.command`, `.app` or `.pkg` with its default handler;
/// Quick Look only renders a preview. When the panel is unavailable the file is revealed
/// in Finder instead, which is equally inert.
@MainActor
public final class QuickLookPreviewer: NSObject {
    public static let shared = QuickLookPreviewer()

    /// Presents the panel for the previewer's current item; returns `false` if it could not.
    public typealias PanelPresenter = @MainActor (QuickLookPreviewer) -> Bool
    public typealias FinderRevealer = @MainActor (URL) -> Void

    public private(set) var previewURL: URL? = nil
    private let presentPanel: PanelPresenter
    private let revealInFinder: FinderRevealer

    public init(presentPanel: PanelPresenter? = nil, revealInFinder: FinderRevealer? = nil) {
        self.presentPanel = presentPanel ?? Self.presentSharedPanel
        self.revealInFinder = revealInFinder ?? { url in
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        super.init()
    }

    public func preview(_ url: URL) {
        previewURL = url
        if !presentPanel(self) {
            revealInFinder(url)
        }
    }

    private static func presentSharedPanel(_ previewer: QuickLookPreviewer) -> Bool {
        guard let panel = QLPreviewPanel.shared() else { return false }
        panel.dataSource = previewer
        panel.currentPreviewItemIndex = 0
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
        return true
    }
}

extension QuickLookPreviewer: @preconcurrency QLPreviewPanelDataSource {
    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewURL.map { $0 as NSURL }
    }
}
