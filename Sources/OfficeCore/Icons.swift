import AppKit
import UniformTypeIdentifiers

public enum IconRenderer {
    /// 把 NSImage 画成 size × size 的 sRGB 位图
    public static func cgImage(_ image: NSImage, size: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    public static func png(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

/// 从系统拿 app 图标，按 bundle id 缓存；找不到 app 就用通用 app 图标（不记在这个 app 名下，下次再找）
/// 只在主线程用
public final class WorkspaceIcons: IconProviding {
    static let size = 128
    /// 通用 app 图标只画一次，找不到的 app 不用每拍重画；画不出来才给空图标
    static let generic = draw(NSWorkspace.shared.icon(for: .application))
        ?? AppIcon(pngBase64: "", color: DominantColor.fallback.hex)
    private var cache: [String: AppIcon] = [:]

    public init() {}

    public func icon(for entry: RosterEntry) -> AppIcon {
        if let hit = cache[entry.id] { return hit }
        guard let url = entry.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.id) else {
            return Self.generic
        }
        let icon = Self.render(NSWorkspace.shared.icon(forFile: url.path))
        cache[entry.id] = icon
        return icon
    }

    /// 画不出来就退回通用 app 图标
    static func render(_ image: NSImage) -> AppIcon {
        draw(image) ?? generic
    }

    private static func draw(_ image: NSImage) -> AppIcon? {
        guard let cg = IconRenderer.cgImage(image, size: size), let png = IconRenderer.png(cg) else { return nil }
        return AppIcon(pngBase64: png.base64EncodedString(), color: DominantColor.of(cg).hex)
    }
}
