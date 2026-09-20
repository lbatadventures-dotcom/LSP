import SpriteKit
import SwiftUI
import UIKit

/// Scatterer, in the small.
///
/// The real mod integrates Rayleigh and Mie scattering along a view ray. That is a
/// shader's job and there is no view ray to integrate in a flat game, so this
/// approximates the two effects a player actually reads: short wavelengths survive a
/// short path through air (blue overhead, deepening to black with altitude), and long
/// wavelengths survive a long one (red at the horizon when the sun is low).
enum Scattering {

    /// Everything the sky needs for one frame.
    struct Sample {
        /// Colour filling the upper part of the screen.
        var zenith: SKColor
        /// Colour at the horizon line, which is where sunsets live.
        var horizon: SKColor
        /// Warm band hugging the horizon; alpha rides the sun's angle.
        var horizonGlow: SKColor
        /// How much of the starfield shows through.
        var starVisibility: Double
        /// Tint applied additively to the vessel, standing in for bounced light.
        var ambientTint: SKColor
        var ambientStrength: Double
    }

    /// Daylight sky at sea level, before the sun angle is applied.
    private static let daylight = (0.33, 0.58, 0.92)
    /// Sunset band.
    private static let dusk = (0.98, 0.46, 0.20)
    /// Deep twilight, just after the sun goes down.
    private static let twilight = (0.12, 0.13, 0.30)
    private static let space = (0.02, 0.03, 0.07)

    /// - Parameters:
    ///   - altitude: metres above sea level
    ///   - sunElevation: cosine of the sun's angle above the local horizon
    static func sample(body: CelestialBody, altitude: Double, sunElevation: Double) -> Sample {
        guard let atmo = body.atmosphere else {
            return Sample(zenith: color(space), horizon: color(space),
                          horizonGlow: SKColor.clear, starVisibility: 1,
                          ambientTint: SKColor.clear, ambientStrength: 0)
        }

        // 0 at sea level, 1 at the top of the atmosphere.
        let height = atmo.spaceFraction(atAltitude: altitude)
        // Thinning air scatters less; the sky darkens faster than it thins.
        let airDepth = pow(1 - height, 1.35)

        // Day factor: 1 in full daylight, 0 below the horizon.
        let day = MathUtil.clamp(MathUtil.remap(sunElevation, -0.18, 0.22, 0, 1), 0, 1)
        // Golden hour: peaks as the sun crosses the horizon.
        let goldenHour = pow(max(0, 1 - abs(sunElevation) / 0.34), 1.6)

        // Blue overhead in daylight, sinking through twilight to night.
        var zenithRGB = mix(twilight, daylight, day)
        zenithRGB = mix(mix(space, zenithRGB, airDepth), zenithRGB, airDepth * day)

        // The horizon keeps more colour than the zenith, and turns red at low sun.
        var horizonRGB = mix(twilight, mix(daylight, (0.66, 0.78, 0.95), 0.35), day)
        horizonRGB = mix(horizonRGB, dusk, goldenHour * 0.85 * airDepth)
        horizonRGB = mix(mix(space, horizonRGB, airDepth), horizonRGB, airDepth)

        let glowAlpha = goldenHour * airDepth * 0.9
        let glowRGB = mix(dusk, (1.0, 0.72, 0.36), 0.35)

        // Stars wash out in a bright sky and come back as it thins or darkens.
        let skyBrightness = (zenithRGB.0 + zenithRGB.1 + zenithRGB.2) / 3
        let starVisibility = MathUtil.clamp(1 - skyBrightness * 2.6, 0, 1)

        // PlanetShine-ish: the lit ground throws some of its own colour back up.
        let bounce = day * airDepth * 0.55
        let surface = rgb(body.surfaceColor)

        return Sample(
            zenith: color(zenithRGB),
            horizon: color(horizonRGB),
            horizonGlow: color(glowRGB, alpha: glowAlpha),
            starVisibility: starVisibility,
            ambientTint: color(mix(surface, (1.0, 0.86, 0.66), goldenHour * 0.6)),
            ambientStrength: bounce
        )
    }

    /// Colour of the glow ringing a body seen from space, and how far it extends.
    static func limbGlow(for body: CelestialBody) -> SKColor? {
        guard body.hasAtmosphere else { return nil }
        let c = rgb(body.atmosphereColor)
        return color(mix(c, (1, 1, 1), 0.22), alpha: 0.55)
    }

    // MARK: - Small colour helpers

    private static func mix(_ a: (Double, Double, Double), _ b: (Double, Double, Double),
                            _ t: Double) -> (Double, Double, Double) {
        let k = MathUtil.clamp(t, 0, 1)
        return (a.0 + (b.0 - a.0) * k, a.1 + (b.1 - a.1) * k, a.2 + (b.2 - a.2) * k)
    }

    private static func color(_ c: (Double, Double, Double), alpha: Double = 1) -> SKColor {
        SKColor(red: CGFloat(MathUtil.clamp(c.0, 0, 1)),
                green: CGFloat(MathUtil.clamp(c.1, 0, 1)),
                blue: CGFloat(MathUtil.clamp(c.2, 0, 1)),
                alpha: CGFloat(MathUtil.clamp(alpha, 0, 1)))
    }

    private static func rgb(_ color: Color) -> (Double, Double, Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }
}

/// A vertical two-stop gradient sprite, regenerated only when the colours actually
/// change. Rebuilding the texture every frame would be far too expensive; in practice
/// the sky shifts slowly enough that a 24-step quantisation is invisible.
final class SkyGradientNode: SKSpriteNode {
    private var lastKey: Int = .min

    // No initialisers are declared, so SKSpriteNode's designated initialisers — including
    // the required init(coder:) — are inherited. `SkyGradientNode()` is enough.

    func update(top: SKColor, bottom: SKColor, size: CGSize) {
        self.size = size
        let key = SkyGradientNode.key(top) &* 31 &+ SkyGradientNode.key(bottom)
        guard key != lastKey else { return }
        lastKey = key

        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        _ = top.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        _ = bottom.getRed(&br, green: &bg, blue: &bb, alpha: &ba)

        // 1 x N strip, stretched across the screen by the sprite.
        let steps = 64
        var bytes = [UInt8](repeating: 0, count: steps * 4)
        for i in 0..<steps {
            // Row 0 is the top of the image.
            let t = Double(i) / Double(steps - 1)
            let eased = pow(t, 1.5)
            bytes[i * 4] = UInt8(MathUtil.clamp(Double(tr) + (Double(br) - Double(tr)) * eased, 0, 1) * 255)
            bytes[i * 4 + 1] = UInt8(MathUtil.clamp(Double(tg) + (Double(bg) - Double(tg)) * eased, 0, 1) * 255)
            bytes[i * 4 + 2] = UInt8(MathUtil.clamp(Double(tb) + (Double(bb) - Double(tb)) * eased, 0, 1) * 255)
            bytes[i * 4 + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let cg = CGImage(width: 1, height: steps, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil,
                               shouldInterpolate: true, intent: .defaultIntent)
        else { return }
        texture = SKTexture(cgImage: cg)
        colorBlendFactor = 0
    }

    private static func key(_ c: SKColor) -> Int {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = c.getRed(&r, green: &g, blue: &b, alpha: &a)
        // Quantise so tiny changes do not trigger a rebuild.
        return ((Int(r * 24) * 25 + Int(g * 24)) * 25 + Int(b * 24)) * 25 + Int(a * 24)
    }
}
