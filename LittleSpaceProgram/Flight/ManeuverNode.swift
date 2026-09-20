import Foundation

/// A planned burn. In a two-dimensional universe there are only two useful burn
/// directions, so a node is a prograde and a radial component.
struct ManeuverNode: Equatable {
    /// Universe time at which the burn is centred.
    var time: Double
    var prograde: Double = 0
    var radial: Double = 0

    var deltaV: Double { (prograde * prograde + radial * radial).squareRoot() }

    /// The burn vector in the inertial frame, given the orbit it is planned on.
    func worldDeltaV(on orbit: Orbit) -> Vec2 {
        let s = orbit.state(at: time)
        let pro = s.velocity.normalized
        let rad = s.position.normalized
        return pro * prograde + rad * radial
    }

    /// The orbit the vessel ends up on if the burn is executed exactly.
    func resultingOrbit(from orbit: Orbit) -> Orbit {
        let s = orbit.state(at: time)
        let dv = worldDeltaV(on: orbit)
        return Orbit(position: s.position, velocity: s.velocity + dv, mu: orbit.mu, epoch: time)
    }

    /// How long the burn takes at full throttle, from the rocket equation.
    func burnDuration(vessel: Vessel) -> Double {
        let thrust = vessel.maxThrust
        guard thrust > 0, deltaV > 0 else { return 0 }
        let pressure = vessel.atmosphericPressure
        var flow = 0.0
        for e in vessel.ignitedEngines {
            guard let d = e.definition else { continue }
            flow += d.thrust(atPressure: pressure) / (d.isp(atPressure: pressure) * Units.g0)
        }
        guard flow > 0 else { return 0 }
        let isp = thrust / (flow * Units.g0)
        let m0 = vessel.totalMass
        let mf = m0 / exp(deltaV / (isp * Units.g0))
        return (m0 - mf) / flow
    }

    /// Seconds until the burn should start so that it is centred on the node.
    func timeToIgnition(vessel: Vessel, now: Double) -> Double {
        time - now - burnDuration(vessel: vessel) / 2
    }
}

enum ManeuverPresets {
    /// Delta-v needed to circularise at the current altitude, evaluated at `time`.
    static func circularize(orbit: Orbit, at time: Double) -> Double {
        let s = orbit.state(at: time)
        let r = s.position.length
        let circular = (orbit.mu / r).squareRoot()
        // Only the tangential component matters for the magnitude estimate.
        let tangential = s.velocity.dot(s.position.perpendicular.normalized * (orbit.clockwise ? -1 : 1))
        return circular - tangential
    }

    /// Delta-v at periapsis to raise apoapsis to `targetRadius`.
    static func raiseApoapsis(orbit: Orbit, to targetRadius: Double, at time: Double) -> Double {
        let s = orbit.state(at: time)
        let r = s.position.length
        guard targetRadius > r else { return 0 }
        let a = (r + targetRadius) / 2
        let want = (orbit.mu * (2 / r - 1 / a)).squareRoot()
        return want - s.velocity.length
    }
}
