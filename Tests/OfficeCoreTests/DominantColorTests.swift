import XCTest
import CoreGraphics
@testable import OfficeCore

final class DominantColorTests: XCTestCase {
    private func pixels(_ list: [(UInt8, UInt8, UInt8, UInt8)]) -> [UInt8] {
        list.flatMap { [$0.0, $0.1, $0.2, $0.3] }
    }

    func testSolidColor() {
        let px = pixels(Array(repeating: (0x3D, 0x7B, 0xFD, 255), count: 16))
        XCTAssertEqual(DominantColor.fromRGBA(px).hex, "#3D7BFD")
    }

    func testTransparentFallsBack() {
        let px = pixels(Array(repeating: (255, 0, 0, 0), count: 16))
        XCTAssertEqual(DominantColor.fromRGBA(px), DominantColor.fallback)
        XCTAssertEqual(DominantColor.fallback.hex, "#9AA5B1")
    }

    func testBlackWhiteGrayFallsBack() {
        let px = pixels([(0, 0, 0, 255), (255, 255, 255, 255), (128, 128, 128, 255), (10, 12, 11, 255)])
        XCTAssertEqual(DominantColor.fromRGBA(px), DominantColor.fallback)
    }

    func testMajorityHueWins() {
        let blue = Array(repeating: (UInt8(20), UInt8(60), UInt8(220), UInt8(255)), count: 10)
        let red = Array(repeating: (UInt8(220), UInt8(30), UInt8(30), UInt8(255)), count: 3)
        let white = Array(repeating: (UInt8(255), UInt8(255), UInt8(255), UInt8(255)), count: 30)
        XCTAssertEqual(DominantColor.fromRGBA(pixels(blue + red + white)).hex, "#143CDC")
    }

    func testNegativeHueFolds() {
        let px = pixels(Array(repeating: (220, 30, 60, 255), count: 10))
        XCTAssertEqual(DominantColor.fromRGBA(px).hex, "#DC1E3C")
    }

    func testUnpremultipliesEdgePixels() {
        // 110/128*255 = 219.1 -> 219 (DB)，15/128*255 = 29.9 -> 30 (1E)，不能是变暗的 #6E0F0F
        let px = pixels(Array(repeating: (110, 15, 15, 128), count: 10))
        XCTAssertEqual(DominantColor.fromRGBA(px).hex, "#DB1E1E")
    }

    func testFromCGImage() {
        let size = 64
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 0, green: 0.8, blue: 0.2, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let color = DominantColor.of(ctx.makeImage()!)
        XCTAssertEqual(color.r, 0)
        XCTAssertEqual(Int(color.g), 204, accuracy: 2)
        XCTAssertEqual(Int(color.b), 51, accuracy: 2)
    }
}
