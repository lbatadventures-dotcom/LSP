import Foundation
import SwiftUI

/// The stock system: a home world with an atmosphere, a close grey moon, and a small
/// high moon that is cheap to reach but awkward to land on.
///
/// Scales are deliberately compressed — the home world is 600 km across rather than
/// Earth-sized — so an orbit takes about half an hour of game time rather than 90
/// minutes, and a Mun-and-back mission fits in a single sitting on a phone.
final class SolarSystem {
    static let shared = SolarSystem()

    let home: CelestialBody
    let moon: CelestialBody
    let outerMoon: CelestialBody
    let bodies: [CelestialBody]

    private init() {
        let atmo = Atmosphere(
            height: 70_000,
            seaLevelDensity: 1.225,
            seaLevelPressure: 101_325,
            scaleHeight: 5_600
        )

        let home = CelestialBody(
            id: "terra",
            name: "Terra",
            radius: 600_000,
            mu: 3.5316e12,
            rotationPeriod: 21_600,
            soiRadius: .infinity,
            atmosphere: atmo,
            parent: nil,
            orbitRadius: 0,
            orbitPeriod: 0,
            orbitPhaseAtEpoch: 0,
            surfaceColor: Color(red: 0.36, green: 0.52, blue: 0.30),
            deepColor: Color(red: 0.10, green: 0.20, blue: 0.36),
            atmosphereColor: Color(red: 0.35, green: 0.62, blue: 0.95),
            terrainAmplitude: 3_500
        )

        let moon = CelestialBody(
            id: "selene",
            name: "Selene",
            radius: 200_000,
            mu: 6.5138e10,
            rotationPeriod: 138_984,
            soiRadius: 2_429_559,
            atmosphere: nil,
            parent: home,
            orbitRadius: 12_000_000,
            orbitPeriod: 138_984,
            orbitPhaseAtEpoch: 1.7,
            surfaceColor: Color(red: 0.62, green: 0.60, blue: 0.58),
            deepColor: Color(red: 0.28, green: 0.27, blue: 0.26),
            atmosphereColor: .clear,
            terrainAmplitude: 4_200
        )

        let outerMoon = CelestialBody(
            id: "vesper",
            name: "Vesper",
            radius: 60_000,
            mu: 1.7658e9,
            rotationPeriod: 40_400,
            soiRadius: 2_247_428,
            atmosphere: nil,
            parent: home,
            orbitRadius: 47_000_000,
            orbitPeriod: 1_077_311,
            orbitPhaseAtEpoch: 3.9,
            surfaceColor: Color(red: 0.72, green: 0.78, blue: 0.68),
            deepColor: Color(red: 0.32, green: 0.38, blue: 0.30),
            atmosphereColor: .clear,
            terrainAmplitude: 1_100
        )

        self.home = home
        self.moon = moon
        self.outerMoon = outerMoon
        self.bodies = [home, moon, outerMoon]
    }

    func body(id: String) -> CelestialBody {
        bodies.first { $0.id == id } ?? home
    }

    /// Bodies whose sphere of influence a vessel inside `parent`'s SOI could fall into.
    func childBodies(of parent: CelestialBody) -> [CelestialBody] {
        bodies.filter { $0.parent === parent }
    }

    /// The body whose SOI contains `position` (given relative to `frame`), preferring
    /// the deepest match. Returns `frame` when no child SOI contains the point.
    func dominantBody(position: Vec2, frame: CelestialBody, time: Double) -> CelestialBody {
        for child in childBodies(of: frame) {
            let rel = position - child.positionRelativeToParent(at: time)
            if rel.length < child.soiRadius {
                return child
            }
        }
        return frame
    }
}
