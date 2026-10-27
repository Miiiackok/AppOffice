import AppKit
import XCTest
@testable import OfficeCore

final class IconsTests: XCTestCase {
    func testRendersAnyImageTo128PixelPNGWithItsColor() throws {
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).setFill()
            rect.fill()
            return true
        }
        let icon = WorkspaceIcons.render(image)
        let data = try XCTUnwrap(Data(base64Encoded: icon.pngBase64))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
        XCTAssertEqual(rep.pixelsWide, 128)
        XCTAssertEqual(rep.pixelsHigh, 128)
        let r = try XCTUnwrap(Int(icon.color.dropFirst().prefix(2), radix: 16))
        let g = try XCTUnwrap(Int(icon.color.dropFirst(3).prefix(2), radix: 16))
        XCTAssertGreaterThan(r, 200, icon.color)
        XCTAssertLessThan(g, 90, icon.color)
    }

    func testFinderIconIsRenderedOnceAndCached() {
        let icons = WorkspaceIcons()
        let finder = RosterEntry(id: "com.apple.finder", name: "Finder", kind: .staff, seat: 0,
                                 bundleURL: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        let first = icons.icon(for: finder)
        XCTAssertFalse(first.pngBase64.isEmpty)
        XCTAssertEqual(icons.icon(for: finder), first)
    }

    func testUnknownAppGetsTheGenericIcon() {
        let ghost = RosterEntry(id: "com.example.does-not-exist", name: "Ghost", kind: .temp, seat: nil, bundleURL: nil)
        XCTAssertFalse(WorkspaceIcons().icon(for: ghost).pngBase64.isEmpty)
    }
}
