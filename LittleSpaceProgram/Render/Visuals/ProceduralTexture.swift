import CoreGraphics
import SpriteKit
import SwiftUI
import UIKit

/// Deterministic value noise with optional horizontal tiling, so a cloud sheet can be
/// wrapped around a planet without a visible seam.
struct ValueNoise {
    let seed: UInt64

    init(seed: UInt64) { self.seed = seed &* 0x9E3779B97F4A7C15 &+ 0x165667B19E3779F9 }

    /// Stable hash of a lattice point, in [0, 1).
    private func hash(_ xi: Int, _ yi: Int) -> Double {
        var h = UInt64(truncatingIfNeeded: xi) &* 0x9E3779B97F4A7C15
        h ^= UInt64(truncatingIfNeeded: yi) &* 0xC2B2AE3D27D4EB4F
        h ^= seed
        h ^= h >> 29
        h = h &* 0xBF58476D1CE4E5B9
        h ^= h >> 32
        return Double(h >> 11) / Double(1 << 53)
    }

    private static func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }

    private static func wrap(_ v: Int, _ period: Int) -> Int {
        guard period > 0 else { return v }
        let m = v % period
        return m < 0 ? m + period : m
    }

    /// Bilinear value noise. `periodX` > 0 makes the result tile horizontally.
    func value(_ x: Double, _ y: Double, periodX: Int = 0) -> Double {
        let x0 = Int(floor(x)), y0 = Int(floor(y))
        let fx = ValueNoise.smooth(x - Double(x0))
        let fy = ValueNoise.smooth(y - Double(y0))
        let xa = ValueNoise.wrap(x0, periodX)
        let xb = ValueNoise.wrap(x0 + 1, periodX)
        let v00 = hash(xa, y0), v10 = hash(xb, y0)
        let v01 = hash(xa, y0 + 1), v11 = hash(xb, y0 + 1)
        let a = v00 + (v10 - v00) * fx
        let b = v01 + (v11 - v01) * fx
        return a + (b - a) * fy
    }

    /// Fractal sum. `periodX` is the tiling period at the base frequency.
    func fbm(_ x: Double, _ y: Double, octaves: Int = 5, periodX: Int = 0) -> Double {
        var total = 0.0, amplitude = 1.0, frequency = 1.0, norm = 0.0
        for _ in 0..<octaves {
            total += value(x * frequency, y * frequency,
                           periodX: periodX > 0 ? periodX * Int(frequency) : 0) * amplitude
            norm += amplitude
            amplitude *= 0.5
            frequency *= 2
        }
        return norm > 0 ? total / norm : 0
    }

    /// Ridged variant, which reads as wispy cloud banding rather than blobs.
    func billow(_ x: Double, _ y: Double, octaves: Int = 5, periodX: Int = 0) -> Double {
        var total = 0.0, amplitude = 1.0, frequency = 1.0, norm = 0.0
        for _ in 0..<octaves {
            let v = abs(value(x * frequency, y * frequency,
                              periodX: periodX > 0 ? periodX * Int(frequency) : 0) * 2 - 1)
            total += v * amplitude
            norm += amplitude
            amplitude *= 0.5
            frequency *= 2
        }
        return norm > 0 ? total / norm : 0
    }
}

/// Builds the textures the visual mods need. Everything here is generated once and
/// cached — a 256×256 texture costs a few milliseconds to fill, which is fine at scene
/// setup and would be ruinous per frame.
enum ProceduralTexture {

    private static var cache: [String: SKTexture] = [:]

    static func cached(_ key: String, _ make: () -> SKTexture) -> SKTexture {
        if let hit = cache[key] { return hit }
        let texture = make()
        cache[key] = texture
        return texture
    }

    static func clearCache() { cache.removeAll() }

    // MARK: - Raw image construction

    /// Fills an RGBA image pixel by pixel. The closure returns straight (un-premultiplied)
    /// components in 0...1; premultiplication happens here.
    static func image(size: Int, _ shade: (Double, Double) -> (Double, Double, Double, Double)) -> CGImage? {
        guard size > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for py in 0..<size {
            let v = (Double(py) + 0.5) / Double(size)
            for px in 0..<size {
                let u = (Double(px) + 0.5) / Double(size)
                let (r, g, b, a) = shade(u, v)
                let alpha = MathUtil.clamp(a, 0, 1)
                let i = (py * size + px) * 4
                bytes[i] = UInt8(MathUtil.clamp(r, 0, 1) * alpha * 255)
                bytes[i + 1] = UInt8(MathUtil.clamp(g, 0, 1) * alpha * 255)
                bytes[i + 2] = UInt8(MathUtil.clamp(b, 0, 1) * alpha * 255)
                bytes[i + 3] = UInt8(alpha * 255)
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: size, height: size,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)
    }

    static func texture(size: Int, _ shade: (Double, Double) -> (Double, Double, Double, Double)) -> SKTexture {
        guard let cg = image(size: size, shade) else { return SKTexture() }
        return SKTexture(cgImage: cg)
    }

    // MARK: - Shared sprites

    /// Soft round particle, used by every emitter.
    static var particle: SKTexture {
        cached("particle") {
            texture(size: 64) { u, v in
                let d = ((u - 0.5) * (u - 0.5) + (v - 0.5) * (v - 0.5)).squareRoot() * 2
                let a = max(0, 1 - d)
                return (1, 1, 1, a * a)
            }
        }
    }

    /// Additive radial glow with a long tail, for limb glow and flares.
    static var glow: SKTexture {
        cached("glow") {
            texture(size: 128) { u, v in
                let d = ((u - 0.5) * (u - 0.5) + (v - 0.5) * (v - 0.5)).squareRoot() * 2
                let a = max(0, 1 - d)
                return (1, 1, 1, pow(a, 2.6))
            }
        }
    }

    /// Four-point star flare for Distant Object Enhancement.
    static var flare: SKTexture {
        cached("flare") {
            texture(size: 128) { u, v in
                let dx = abs(u - 0.5) * 2, dy = abs(v - 0.5) * 2
                let d = (dx * dx + dy * dy).squareRoot()
                let core = pow(max(0, 1 - d), 3.5)
                // Thin cross spikes.
                let spikeH = max(0, 1 - dx) * pow(max(0, 1 - dy * 14), 2)
                let spikeV = max(0, 1 - dy) * pow(max(0, 1 - dx * 14), 2)
                return (1, 1, 1, MathUtil.clamp(core + (spikeH + spikeV) * 0.55, 0, 1))
            }
        }
    }

    /// Soft cloud puff for the surface-level cloud band.
    static func cloudPuff(seed: UInt64, size: Int) -> SKTexture {
        cached("cloudPuff-\(seed)-\(size)") {
            let noise = ValueNoise(seed: seed)
            return texture(size: size) { u, v in
                let dx = (u - 0.5) * 2, dy = (v - 0.5) * 2.4
                let radial = max(0, 1 - (dx * dx + dy * dy).squareRoot())
                let n = noise.fbm(u * 5, v * 5, octaves: 4)
                let a = MathUtil.clamp(pow(radial, 1.5) * (0.55 + n * 0.9) * 1.5, 0, 1)
                let shade = 0.80 + 0.20 * n
                return (shade, shade, min(1, shade * 1.03), a)
            }
        }
    }

    // MARK: - Planet textures

    /// The lit face of a body: terrain, seas where it has an atmosphere, and polar caps.
    static func surface(for body: CelestialBody, size: Int) -> SKTexture {
        cached("surface-\(body.id)-\(size)") {
            let noise = ValueNoise(seed: UInt64(abs(body.id.utf8.reduce(7) { $0 &* 31 &+ Int($1) })))
            let land = components(body.surfaceColor)
            let deep = components(body.deepColor)
            let hasSea = body.hasAtmosphere

            return texture(size: size) { u, v in
                // Map the square onto the disc; outside it is transparent.
                let dx = (u - 0.5) * 2, dy = (v - 0.5) * 2
                let d = (dx * dx + dy * dy).squareRoot()
                if d > 1 { return (0, 0, 0, 0) }

                // Spherical projection, so features compress toward the limb.
                let lat = asin(MathUtil.clamp(dy, -1, 1))
                let cosLat = max(cos(lat), 0.08)
                let lon = asin(MathUtil.clamp(dx / cosLat, -1, 1))

                let h = noise.fbm(lon * 2.2 + 8, lat * 2.2 + 3, octaves: 6)
                var r: Double, g: Double, b: Double
                if hasSea && h < 0.46 {
                    let t = MathUtil.remap(h, 0.2, 0.46, 0, 1)
                    r = MathUtil.lerp(deep.0 * 0.8, deep.0 * 1.25, t)
                    g = MathUtil.lerp(deep.1 * 0.8, deep.1 * 1.25, t)
                    b = MathUtil.lerp(deep.2 * 0.85, deep.2 * 1.3, t)
                } else {
                    let t = MathUtil.remap(h, 0.4, 0.95, 0, 1)
                    r = MathUtil.lerp(land.0 * 0.72, land.0 * 1.22, t)
                    g = MathUtil.lerp(land.1 * 0.72, land.1 * 1.22, t)
                    b = MathUtil.lerp(land.2 * 0.72, land.2 * 1.18, t)
                    // Craters read better than hills on an airless body.
                    if !hasSea {
                        let c = noise.billow(lon * 7 + 2, lat * 7, octaves: 3)
                        let k = 0.78 + 0.34 * c
                        r *= k; g *= k; b *= k
                    }
                }
                // Polar caps.
                let polar = MathUtil.remap(abs(dy), 0.78, 0.99, 0, 1)
                if polar > 0 && hasSea {
                    r = MathUtil.lerp(r, 0.92, polar); g = MathUtil.lerp(g, 0.95, polar)
                    b = MathUtil.lerp(b, 0.98, polar)
                }
                // Soften the very edge so the disc does not alias.
                let edge = MathUtil.remap(d, 0.985, 1.0, 1, 0)
                return (r, g, b, edge)
            }
        }
    }

    /// EVE's contribution: a cloud sheet over the disc, transparent between the clouds.
    static func clouds(for body: CelestialBody, size: Int) -> SKTexture {
        cached("clouds-\(body.id)-\(size)") {
            let noise = ValueNoise(seed: UInt64(abs(body.id.utf8.reduce(19) { $0 &* 37 &+ Int($1) })) &+ 977)
            return texture(size: size) { u, v in
                let dx = (u - 0.5) * 2, dy = (v - 0.5) * 2
                let d = (dx * dx + dy * dy).squareRoot()
                if d > 1 { return (0, 0, 0, 0) }
                let lat = asin(MathUtil.clamp(dy, -1, 1))
                let cosLat = max(cos(lat), 0.08)
                let lon = asin(MathUtil.clamp(dx / cosLat, -1, 1))

                // Stretched horizontally into bands, the way weather actually organises.
                let n = noise.fbm(lon * 3.1, lat * 6.4, octaves: 6)
                let wisp = noise.billow(lon * 6.0 + 4, lat * 11.0, octaves: 4)
                var a = MathUtil.remap(n * 0.72 + wisp * 0.28, 0.46, 0.78, 0, 1)
                a = pow(a, 1.35) * 0.95
                // Fade out at the limb so clouds do not spill past the horizon.
                a *= MathUtil.remap(d, 0.88, 1.0, 1, 0)
                return (1, 1, 1, a)
            }
        }
    }

    /// Night side, as a disc that is opaque on one edge and clear on the other.
    /// Rotating this sprite to face away from the sun gives the terminator.
    ///
    /// `softness` widens the dusk band: air scatters light well around the limb, so a
    /// world with an atmosphere has a broad twilight zone while an airless one cuts
    /// almost straight from day to night.
    static func terminator(softness: Double) -> SKTexture {
        let q = (MathUtil.clamp(softness, 0, 1) * 10).rounded() / 10
        return cached("terminator-\(q)") {
            let halfBand = 0.10 + 0.42 * q
            return texture(size: 256) { u, v in
                let dx = (u - 0.5) * 2, dy = (v - 0.5) * 2
                let d = (dx * dx + dy * dy).squareRoot()
                if d > 1 { return (0, 0, 0, 0) }
                // +x is the night pole; the band across the middle is dusk.
                let night = MathUtil.remap(dx, -halfBand, halfBand, 0, 1)
                let edge = MathUtil.remap(d, 0.985, 1.0, 1, 0)
                // Dusk carries a little warmth before it goes to night blue.
                let dusk = pow(1 - abs(MathUtil.remap(dx, -halfBand, halfBand, -1, 1)), 2.0)
                let r = MathUtil.lerp(0.012, 0.16, dusk * q)
                let g = MathUtil.lerp(0.020, 0.07, dusk * q)
                let b = MathUtil.lerp(0.050, 0.06, dusk * q)
                return (r, g, b, pow(night, 0.85) * 0.94 * edge)
            }
        }
    }

    private static func components(_ color: Color) -> (Double, Double, Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }
}

extension ProceduralTexture {

    /// Ring of atmospheric glow around a planet seen from space. `inner` is the planet's
    /// radius as a fraction of the sprite's own radius.
    static func limb(inner: Double) -> SKTexture {
        let q = (inner * 40).rounded() / 40
        return cached("limb-\(q)") {
            texture(size: 256) { u, v in
                let dx = (u - 0.5) * 2, dy = (v - 0.5) * 2
                let d = (dx * dx + dy * dy).squareRoot()
                if d > 1 || d < q * 0.94 { return (0, 0, 0, 0) }
                // Bright right at the surface, falling away into space.
                let radial: Double
                if d < q {
                    radial = MathUtil.remap(d, q * 0.94, q, 0, 1) * 0.85
                } else {
                    radial = pow(MathUtil.remap(d, q, 1.0, 1, 0), 2.1)
                }
                // Air only glows where the sun is shining through it, so the ring is a
                // bright crescent on the day side and barely there on the night side.
                // +x is sunward; PlanetNode rotates the sprite to match.
                let facing = d > 1e-6 ? dx / d : 0
                let day = pow(MathUtil.remap(facing, -0.35, 0.55, 0, 1), 1.25)
                return (1, 1, 1, radial * (0.10 + 0.90 * day))
            }
        }
    }

    /// Waterfall's plume: nozzle at the top of the texture, tip at the bottom.
    /// The sprite is stretched in x and y to shape it for pressure and throttle.
    static func plume(hot: Bool) -> SKTexture {
        cached("plume-\(hot)") {
            texture(size: 128) { u, v in
                // Roughly constant near the nozzle, tapering to a point.
                let halfWidth = 0.44 * pow(max(0.0001, 1 - v), 0.55)
                let t = abs(u - 0.5) / halfWidth
                if t >= 1 { return (0, 0, 0, 0) }
                let radial = 1 - t * t
                let lengthFade = pow(1 - v, 0.45)
                let a = radial * lengthFade

                // White-hot core bleeding into the flame colour at the edges.
                let core = pow(radial, 3.2)
                let r: Double, g: Double, b: Double
                if hot {
                    r = MathUtil.lerp(1.0, 1.0, core)
                    g = MathUtil.lerp(0.55, 0.92, core)
                    b = MathUtil.lerp(0.22, 0.72, core)
                } else {
                    r = MathUtil.lerp(0.48, 0.90, core)
                    g = MathUtil.lerp(0.66, 0.95, core)
                    b = MathUtil.lerp(1.0, 1.0, core)
                }
                return (r, g, b, a)
            }
        }
    }

    /// Bright disc for a shock diamond.
    static var shockDiamond: SKTexture {
        cached("shockDiamond") {
            texture(size: 64) { u, v in
                // A lens shape: wide across, pinched top and bottom.
                let dx = (u - 0.5) * 2
                let dy = (v - 0.5) * 2.6
                let d = (dx * dx + dy * dy).squareRoot()
                let a = pow(max(0, 1 - d), 1.8)
                return (1, 0.95, 0.82, a)
            }
        }
    }

    /// Elongated glow used for the reentry plasma sheath.
    static var sheath: SKTexture {
        cached("sheath") {
            texture(size: 128) { u, v in
                // Teardrop bow shock: broad and bright at the leading edge, tapering
                // back along the flanks. v = 0 is the vessel end, v = 1 is ahead of it.
                let across = abs(u - 0.5) * 2
                let along = MathUtil.clamp(v, 0, 1)
                let width = 0.20 + 0.70 * pow(along, 0.7)
                let t = across / width
                if t >= 1 { return (0, 0, 0, 0) }
                // Soften the very front so the sprite's edge does not read as a cut.
                let nose = MathUtil.remap(along, 0.86, 1.0, 1, 0.25)
                let a = pow(1 - t * t, 1.5) * along * nose
                return (1, 0.72, 0.40, a)
            }
        }
    }
}
