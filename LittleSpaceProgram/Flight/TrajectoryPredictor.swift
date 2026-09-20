import Foundation

/// Why a predicted patch ends.
enum PatchEnd: Equatable {
    case closedOrbit
    case escape(String)      // left the current sphere of influence
    case encounter(String)   // entered a moon's sphere of influence
    case impact
    case atmosphericEntry
    case horizon             // ran past the prediction window

    var label: String {
        switch self {
        case .closedOrbit: return "Orbit"
        case .escape(let n): return "Escapes to \(n)"
        case .encounter(let n): return "Encounter: \(n)"
        case .impact: return "Impact"
        case .atmosphericEntry: return "Atmospheric entry"
        case .horizon: return "…"
        }
    }
}

/// One conic arc of a predicted trajectory.
struct TrajectoryPatch: Identifiable {
    let id = UUID()
    let body: CelestialBody
    let orbit: Orbit
    let startTime: Double
    let endTime: Double
    let end: PatchEnd

    /// Samples the arc, returned in `frame`'s coordinates. Each patch is anchored to
    /// where its body was when the patch began, which is how a patched-conic map reads.
    func points(in frame: CelestialBody, count: Int = 128) -> [Vec2] {
        guard count > 1, endTime > startTime else { return [] }
        let offset = body === frame ? Vec2.zero : body.position(at: startTime, relativeTo: frame)
        var out: [Vec2] = []
        out.reserveCapacity(count)
        let span = endTime - startTime
        for i in 0..<count {
            let t = startTime + span * Double(i) / Double(count - 1)
            out.append(orbit.state(at: t).position + offset)
        }
        return out
    }

    func position(at t: Double, in frame: CelestialBody) -> Vec2 {
        let offset = body === frame ? Vec2.zero : body.position(at: startTime, relativeTo: frame)
        return orbit.state(at: t).position + offset
    }
}

/// Walks a state vector forward through spheres of influence, producing the patched
/// conic chain the map view draws.
enum TrajectoryPredictor {
    /// Sample count used when scanning for a moon encounter.
    private static let scanSamples = 360

    static func predict(body: CelestialBody,
                        position: Vec2,
                        velocity: Vec2,
                        time: Double,
                        system: SolarSystem = .shared,
                        maxPatches: Int = 4,
                        horizon: Double = 6 * 3600 * 40) -> [TrajectoryPatch] {
        var patches: [TrajectoryPatch] = []
        var currentBody = body
        var pos = position
        var vel = velocity
        var t = time
        let deadline = time + horizon

        for _ in 0..<maxPatches {
            guard t < deadline else { break }
            let orbit = Orbit(position: pos, velocity: vel, mu: currentBody.mu, epoch: t)

            // Candidate end conditions, earliest wins.
            var endTime = min(deadline, t + (orbit.period ?? horizon))
            var end: PatchEnd = orbit.isClosed ? .closedOrbit : .horizon

            // Hitting the ground or the top of the atmosphere.
            let atmoTop = currentBody.atmosphere?.height ?? 0
            // For airless bodies aim at the highest terrain, so the warning comes early
            // enough to do something about it.
            let surfaceTarget = currentBody.radius
                + (atmoTop > 0 ? atmoTop : currentBody.terrainAmplitude)
            if orbit.periapsis <= surfaceTarget,
               let hit = orbit.time(atRadius: surfaceTarget, after: t + 1),
               hit < endTime {
                endTime = hit
                end = atmoTop > 0 ? .atmosphericEntry : .impact
            }

            // Leaving this sphere of influence.
            if currentBody.parent != nil, currentBody.soiRadius.isFinite {
                let reachesEdge = !orbit.isClosed || (orbit.apoapsis ?? 0) > currentBody.soiRadius
                if reachesEdge,
                   let exit = orbit.time(atRadius: currentBody.soiRadius, after: t + 1),
                   exit < endTime {
                    endTime = exit
                    end = .escape(currentBody.parent?.name ?? "space")
                }
            }

            // Falling into a moon's sphere of influence.
            if let (encounterTime, moon) = scanForEncounter(
                orbit: orbit, host: currentBody, from: t, to: endTime, system: system
            ) {
                endTime = encounterTime
                end = .encounter(moon.name)
            }

            patches.append(TrajectoryPatch(body: currentBody, orbit: orbit,
                                           startTime: t, endTime: endTime, end: end))

            // Continue into the next patch where there is one.
            switch end {
            case .closedOrbit, .impact, .atmosphericEntry, .horizon:
                return patches
            case .escape:
                guard let parent = currentBody.parent else { return patches }
                let s = orbit.state(at: endTime)
                pos = s.position + currentBody.positionRelativeToParent(at: endTime)
                vel = s.velocity + currentBody.velocityRelativeToParent(at: endTime)
                currentBody = parent
                t = endTime
            case .encounter(let name):
                guard let moon = system.bodies.first(where: { $0.name == name }) else { return patches }
                let s = orbit.state(at: endTime)
                pos = s.position - moon.positionRelativeToParent(at: endTime)
                vel = s.velocity - moon.velocityRelativeToParent(at: endTime)
                currentBody = moon
                t = endTime
            }
        }
        return patches
    }

    static func predict(vessel: Vessel, system: SolarSystem = .shared, maxPatches: Int = 4) -> [TrajectoryPatch] {
        predict(body: vessel.body, position: vessel.position, velocity: vessel.velocity,
                time: vessel.universeTime, system: system, maxPatches: maxPatches)
    }

    /// Time-samples the arc looking for the first entry into a child body's SOI, then
    /// bisects to pin it down. Solving the intercept analytically is not worth it here —
    /// the sampling pass costs a few hundred Kepler solves and runs a few times a second.
    private static func scanForEncounter(orbit: Orbit,
                                         host: CelestialBody,
                                         from t0: Double,
                                         to t1: Double,
                                         system: SolarSystem) -> (Double, CelestialBody)? {
        let moons = system.childBodies(of: host)
        guard !moons.isEmpty, t1 > t0 else { return nil }

        let span = t1 - t0
        let steps = scanSamples
        var best: (Double, CelestialBody)?

        for moon in moons {
            // Cheap rejection: the arc must be able to reach the moon's orbit at all.
            let reach = orbit.apoapsis ?? .infinity
            if reach < moon.orbitRadius - moon.soiRadius { continue }
            if orbit.periapsis > moon.orbitRadius + moon.soiRadius { continue }

            var previous = t0
            var previousInside = false
            for i in 0...steps {
                let t = t0 + span * Double(i) / Double(steps)
                let vesselPos = orbit.state(at: t).position
                let moonPos = moon.positionRelativeToParent(at: t)
                let inside = (vesselPos - moonPos).length < moon.soiRadius
                if inside && i == 0 { break } // already inside; not a new encounter
                if inside && !previousInside {
                    let crossing = bisectEntry(orbit: orbit, moon: moon, lo: previous, hi: t)
                    if best == nil || crossing < best!.0 { best = (crossing, moon) }
                    break
                }
                previous = t
                previousInside = inside
            }
        }
        return best
    }

    private static func bisectEntry(orbit: Orbit, moon: CelestialBody, lo: Double, hi: Double) -> Double {
        var a = lo, b = hi
        for _ in 0..<40 {
            let m = (a + b) / 2
            let d = (orbit.state(at: m).position - moon.positionRelativeToParent(at: m)).length
            if d < moon.soiRadius { b = m } else { a = m }
        }
        return b
    }
}
