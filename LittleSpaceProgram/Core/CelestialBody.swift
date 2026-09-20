import Foundation
import SwiftUI

/// An exponential atmosphere model: density falls off with a fixed scale height.
struct Atmosphere {
    let height: Double            // m above sea level where the atmosphere ends
    let seaLevelDensity: Double   // kg/m^3
    let seaLevelPressure: Double  // Pa
    let scaleHeight: Double       // m

    func density(atAltitude alt: Double) -> Double {
        guard alt < height else { return 0 }
        return seaLevelDensity * exp(-max(alt, 0) / scaleHeight)
    }

    func pressure(atAltitude alt: Double) -> Double {
        guard alt < height else { return 0 }
        return seaLevelPressure * exp(-max(alt, 0) / scaleHeight)
    }

    /// 0 at sea level, 1 at the edge of space — drives the sky gradient.
    func spaceFraction(atAltitude alt: Double) -> Double {
        MathUtil.clamp(alt / height, 0, 1)
    }
}

/// A planet or moon. Bodies orbit their parent on a fixed circular orbit, which keeps
/// the n-body bookkeeping analytic and cheap enough to run on a phone at high time warp.
final class CelestialBody: Identifiable {
    let id: String
    let name: String
    let radius: Double            // m
    let mu: Double                // m^3/s^2
    let rotationPeriod: Double    // s, sidereal
    /// Radius of the sphere of influence. `.infinity` for the root body.
    let soiRadius: Double
    let atmosphere: Atmosphere?

    let parent: CelestialBody?
    let orbitRadius: Double       // m, circular orbit about `parent`
    let orbitPeriod: Double       // s
    let orbitPhaseAtEpoch: Double // rad

    let surfaceColor: Color
    let deepColor: Color
    let atmosphereColor: Color
    /// Peak height of terrain above the reference radius, used by the surface renderer.
    let terrainAmplitude: Double
    /// Stable per-body phase for the terrain function. Derived from the id's bytes
    /// rather than `hashValue`, which Swift reseeds on every launch.
    private let terrainSeed: Double

    init(id: String, name: String, radius: Double, mu: Double, rotationPeriod: Double,
         soiRadius: Double, atmosphere: Atmosphere?, parent: CelestialBody?,
         orbitRadius: Double, orbitPeriod: Double, orbitPhaseAtEpoch: Double,
         surfaceColor: Color, deepColor: Color, atmosphereColor: Color,
         terrainAmplitude: Double) {
        self.id = id
        self.name = name
        self.radius = radius
        self.mu = mu
        self.rotationPeriod = rotationPeriod
        self.soiRadius = soiRadius
        self.atmosphere = atmosphere
        self.parent = parent
        self.orbitRadius = orbitRadius
        self.orbitPeriod = orbitPeriod
        self.orbitPhaseAtEpoch = orbitPhaseAtEpoch
        self.surfaceColor = surfaceColor
        self.deepColor = deepColor
        self.atmosphereColor = atmosphereColor
        self.terrainAmplitude = terrainAmplitude
        var acc: UInt64 = 1469598103934665603
        for byte in id.utf8 {
            acc = (acc ^ UInt64(byte)) &* 1099511628211
        }
        self.terrainSeed = Double(acc % 6283) / 1000.0
    }

    var surfaceGravity: Double { mu / (radius * radius) }

    /// Deterministic terrain height, so hills look the same every visit without
    /// storing a heightmap. Always at or above the reference radius, which keeps
    /// "altitude above sea level" meaningful.
    func terrainRadius(atAngle theta: Double) -> Double {
        guard terrainAmplitude > 0 else { return radius }
        let seed = terrainSeed
        let n = sin(theta * 9 + seed) * 0.55
              + sin(theta * 23 + seed * 2.1) * 0.28
              + sin(theta * 57 + seed * 3.7) * 0.17
        return radius + terrainAmplitude * 0.5 * (n + 1)
    }

    /// Height of the terrain above sea level at a given angle.
    func terrainHeight(atAngle theta: Double) -> Double {
        terrainRadius(atAngle: theta) - radius
    }

    var hasAtmosphere: Bool { atmosphere != nil }

    /// Altitude at which a circular orbit clears the atmosphere (or 10 km for airless bodies).
    var minimumSafeOrbitAltitude: Double { (atmosphere?.height ?? 10_000) + 2_000 }

    var escapeSpeedAtSurface: Double { (2 * mu / radius).squareRoot() }

    /// Speed of a circular orbit at the given altitude.
    func circularOrbitSpeed(atAltitude alt: Double) -> Double {
        (mu / (radius + alt)).squareRoot()
    }

    /// Angle the body has rotated through at time `t`.
    func rotationAngle(at t: Double) -> Double {
        guard rotationPeriod != 0 else { return 0 }
        return MathUtil.wrapAngle2Pi(2 * .pi * t / rotationPeriod)
    }

    /// Velocity of the surface at a point, due to the body's rotation (inertial frame).
    func surfaceVelocity(at position: Vec2) -> Vec2 {
        guard rotationPeriod != 0 else { return .zero }
        let omega = 2 * .pi / rotationPeriod
        return position.perpendicular * omega
    }

    /// Position relative to the parent body at time `t`.
    func positionRelativeToParent(at t: Double) -> Vec2 {
        guard parent != nil, orbitPeriod != 0 else { return .zero }
        let angle = orbitPhaseAtEpoch + 2 * .pi * t / orbitPeriod
        return Vec2.polar(angle: angle, length: orbitRadius)
    }

    func velocityRelativeToParent(at t: Double) -> Vec2 {
        guard parent != nil, orbitPeriod != 0 else { return .zero }
        let angle = orbitPhaseAtEpoch + 2 * .pi * t / orbitPeriod
        let speed = 2 * .pi * orbitRadius / orbitPeriod
        return Vec2.polar(angle: angle + .pi / 2, length: speed)
    }

    /// Position in the frame of `frame`, walking up the parent chain.
    func position(at t: Double, relativeTo frame: CelestialBody) -> Vec2 {
        if frame === self { return .zero }
        var result = Vec2.zero
        var node: CelestialBody? = self
        while let n = node, n !== frame {
            result += n.positionRelativeToParent(at: t)
            node = n.parent
        }
        if node == nil {
            // `frame` is not an ancestor; express both against the root and subtract.
            return absolutePosition(at: t) - frame.absolutePosition(at: t)
        }
        return result
    }

    func velocity(at t: Double, relativeTo frame: CelestialBody) -> Vec2 {
        if frame === self { return .zero }
        var result = Vec2.zero
        var node: CelestialBody? = self
        while let n = node, n !== frame {
            result += n.velocityRelativeToParent(at: t)
            node = n.parent
        }
        if node == nil {
            return absoluteVelocity(at: t) - frame.absoluteVelocity(at: t)
        }
        return result
    }

    func absolutePosition(at t: Double) -> Vec2 {
        var result = Vec2.zero
        var node: CelestialBody? = self
        while let n = node {
            result += n.positionRelativeToParent(at: t)
            node = n.parent
        }
        return result
    }

    func absoluteVelocity(at t: Double) -> Vec2 {
        var result = Vec2.zero
        var node: CelestialBody? = self
        while let n = node {
            result += n.velocityRelativeToParent(at: t)
            node = n.parent
        }
        return result
    }

    /// Direct children of this body in the given system.
    func moons(in system: SolarSystem) -> [CelestialBody] {
        system.bodies.filter { $0.parent === self }
    }
}

extension CelestialBody: Equatable, Hashable {
    static func == (a: CelestialBody, b: CelestialBody) -> Bool { a === b }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
