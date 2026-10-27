import CoreGraphics
import Foundation

public struct RGBColor: Equatable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    public var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
}

/// 图标主色：衬衫和地毯描边用
public enum DominantColor {
    public static let fallback = RGBColor(r: 0x9A, g: 0xA5, b: 0xB1)
    static let sampleSize = 32

    public static func of(_ image: CGImage) -> RGBColor {
        let n = sampleSize
        var px = [UInt8](repeating: 0, count: n * n * 4)
        let drawn = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8,
                                      bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        return drawn ? fromRGBA(px) : fallback
    }

    /// 输入是预乘 alpha 的 RGBA 逐像素排列的字节
    public static func fromRGBA(_ px: [UInt8]) -> RGBColor {
        var weight = [Double](repeating: 0, count: 12)
        var sums = [[Double]](repeating: [0, 0, 0], count: 12)
        var counts = [Double](repeating: 0, count: 12)
        for i in stride(from: 0, to: px.count - 3, by: 4) where px[i + 3] >= 128 {
            let a = Double(px[i + 3]) / 255
            // 还原预乘：半透明边缘像素不会被压暗
            let r = min(1, Double(px[i]) / 255 / a), g = min(1, Double(px[i + 1]) / 255 / a), b = min(1, Double(px[i + 2]) / 255 / a)
            let hi = max(r, g, b), lo = min(r, g, b), d = hi - lo
            let s = hi == 0 ? 0 : d / hi
            guard hi >= 0.15, s >= 0.15 else { continue }
            var h: Double
            if hi == r { h = (g - b) / d } else if hi == g { h = 2 + (b - r) / d } else { h = 4 + (r - g) / d }
            h = (h * 60).truncatingRemainder(dividingBy: 360)
            if h < 0 { h += 360 }
            let k = min(11, Int(h / 30))
            weight[k] += s
            sums[k][0] += r * 255; sums[k][1] += g * 255; sums[k][2] += b * 255
            counts[k] += 1
        }
        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 0 else { return fallback }
        func avg(_ c: Int) -> UInt8 { UInt8((sums[best][c] / counts[best]).rounded()) }
        return RGBColor(r: avg(0), g: avg(1), b: avg(2))
    }
}
