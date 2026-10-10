import SwiftUI
import AppKit
import ImageIO

public struct MoraxMascotView: View {
    public let size: CGFloat
    public let showBorder: Bool
    
    public init(size: CGFloat = 36, showBorder: Bool = true) {
        self.size = size
        self.showBorder = showBorder
    }
    
    public var body: some View {
        if let image = MoraxMascotImage.shared {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(showBorder ? MoraxTheme.warmOffWhite.opacity(0.4) : Color.clear, lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 1)
        } else {
            ZStack {
                Circle()
                    .fill(MoraxTheme.surfaceSubtle)
                    .frame(width: size, height: size)
                Image(systemName: "wrench.adjustable.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(MoraxTheme.textSecondary)
            }
            .overlay(
                Circle()
                    .stroke(MoraxTheme.border, lineWidth: 1)
            )
        }
    }
}

/// The mascot artwork, read and decoded once per process.
///
/// The source PNG is 1024×1024 but the mascot is never drawn above 72 pt, so it is
/// downsampled on load instead of keeping a ~4 MB bitmap per view and re-reading
/// the file on every render.
@MainActor
enum MoraxMascotImage {
    /// Longest side of the decoded bitmap: covers the largest mascot (72 pt) at @2x with margin.
    nonisolated static let maxPixelSize = 256

    static let shared: NSImage? = {
        let url = MoraxResourceBundle.url(forResource: "MoraxMascot", withExtension: "png")
            ?? Bundle.main.url(forResource: "MoraxMascot", withExtension: "png")
        return url.flatMap { downsampledImage(at: $0, maxPixelSize: maxPixelSize) }
    }()

    nonisolated static func downsampledImage(at url: URL, maxPixelSize: Int) -> NSImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
