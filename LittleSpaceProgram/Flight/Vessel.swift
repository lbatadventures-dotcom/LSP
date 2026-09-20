import Foundation

enum Situation: String {
    case prelaunch, landed, flying, suborbital, orbiting, escaping, destroyed

    var label: String {
        switch self {
        case .prelaunch: return "Pre-launch"
        case .landed: return "Landed"
        case .flying: return "Flying"
        case .suborbital: return "Sub-orbital"
        case .orbiting: return "Orbiting"
        case .escaping: return "Escape trajectory"
        case .destroyed: return "Destroyed"
        }
    }
}

/// Live state of a single part in flight.
struct PartRuntime {
    var ignited = false
    var flamedOut = false
    /// Propellant left in a solid booster's own grain, kg.
    var solidFuel = 0.0
    var parachuteDeployed = false
    /// 0 to 1 as the canopy opens.
    var parachuteOpen = 0.0
}

/// Propellant is pooled per fuel section rather than per tank: decouplers cut the
/// network, so each section drains as one pool. Tank fill levels are drawn from the
/// section fraction, which matches what a player expects to see.
struct FuelNetwork {
    var sectionOfPart: [UUID: Int] = [:]
    var capacity: [Double] = []
    var fuel: [Double] = []

    init(design: VesselDesign, active: Set<UUID>, preserving old: FuelNetwork? = nil) {
        let sections = design.fuelSections()
        for (i, section) in sections.enumerated() {
            var cap = 0.0
            var carried = 0.0
            var sawOld = false
            for id in section where active.contains(id) {
                sectionOfPart[id] = i
                guard let d = design.part(id)?.definition, !d.isSolidBooster else { continue }
                cap += d.fuelCapacity
                if let old, let oldIndex = old.sectionOfPart[id], !sawOld {
                    carried = old.fuel[oldIndex]
                    sawOld = true
                }
            }
            capacity.append(cap)
            fuel.append(sawOld ? min(carried, cap) : cap)
        }
    }

    func fraction(ofPart id: UUID) -> Double {
        guard let i = sectionOfPart[id], capacity[i] > 0 else { return 0 }
        return MathUtil.clamp(fuel[i] / capacity[i], 0, 1)
    }

    var totalFuel: Double { fuel.reduce(0, +) }
    var totalCapacity: Double { capacity.reduce(0, +) }
}

/// A rocket in flight. Position and velocity are held in the inertial frame of
/// `body`; switching sphere of influence rebases them.
final class Vessel {
    var name: String
    var design: VesselDesign
    var body: CelestialBody

    /// Position of the design-space origin, relative to `body`'s centre, metres.
    var position: Vec2
    var velocity: Vec2
    /// Direction the nose points, radians CCW from +x.
    var heading: Double
    var angularVelocity: Double = 0

    var throttle: Double = 0
    var currentStage: Int = 0
    var situation: Situation = .prelaunch
    /// Seconds since launch, for the mission clock.
    var missionTime: Double = 0
    /// Absolute universe time, kept in step by the simulator. Orbits are epoched on it.
    var universeTime: Double = 0
    /// Longitude in the body's rotating frame, held while landed so warp keeps the
    /// vessel pinned to the pad rather than letting the planet slide out from under it.
    var landedLongitude: Double = 0

    var activeParts: Set<UUID> {
        didSet { livePartsCacheValid = false }
    }
    var runtime: [UUID: PartRuntime] = [:]
    var fuelNetwork: FuelNetwork

    /// Set when the vessel breaks up, for the failure banner.
    var failureReason: String?

    init(design: VesselDesign, body: CelestialBody, position: Vec2, velocity: Vec2, heading: Double) {
        self.name = design.name
        self.design = design
        self.body = body
        self.position = position
        self.velocity = velocity
        self.heading = heading
        self.activeParts = Set(design.parts.map(\.id))
        self.fuelNetwork = FuelNetwork(design: design, active: activeParts)
        for p in design.parts {
            var r = PartRuntime()
            if let d = p.definition, d.isSolidBooster { r.solidFuel = d.fuelCapacity }
            runtime[p.id] = r
        }
    }

    // MARK: - Aggregates

    private var livePartsCache: [PlacedPart] = []
    private var livePartsCacheValid = false

    /// The parts still attached. Cached because the physics step reads it several times
    /// per tick, and re-filtering the part list each time showed up as the single
    /// biggest source of churn on the integrator's hot path.
    var liveParts: [PlacedPart] {
        if livePartsCacheValid { return livePartsCache }
        livePartsCache = design.parts.filter { activeParts.contains($0.id) }
        livePartsCacheValid = true
        return livePartsCache
    }

    var totalMass: Double {
        var m = 0.0
        for p in liveParts {
            guard let d = p.definition else { continue }
            m += d.dryMass
            if d.isSolidBooster { m += runtime[p.id]?.solidFuel ?? 0 }
        }
        for (i, cap) in fuelNetwork.capacity.enumerated() where cap > 0 {
            m += fuelNetwork.fuel[i]
        }
        return max(m, 1)
    }

    /// Centre of mass in design space.
    var centerOfMass: Vec2 {
        var sum = Vec2.zero
        var total = 0.0
        for p in liveParts {
            guard let d = p.definition else { continue }
            var m = d.dryMass
            if d.isSolidBooster {
                m += runtime[p.id]?.solidFuel ?? 0
            } else if d.fuelCapacity > 0 {
                m += d.fuelCapacity * fuelNetwork.fraction(ofPart: p.id)
            }
            sum += p.position * m
            total += m
        }
        return total > 0 ? sum / total : .zero
    }

    /// Moment of inertia about the centre of mass, kg*m^2.
    var momentOfInertia: Double {
        let com = centerOfMass
        var total = 0.0
        for p in liveParts {
            guard let d = p.definition else { continue }
            var m = d.dryMass
            if d.isSolidBooster {
                m += runtime[p.id]?.solidFuel ?? 0
            } else if d.fuelCapacity > 0 {
                m += d.fuelCapacity * fuelNetwork.fraction(ofPart: p.id)
            }
            let r = (p.position - com).lengthSquared
            let own = (d.size.x * d.size.x + d.size.y * d.size.y) / 12
            total += m * (r + own)
        }
        return max(total, 1)
    }

    /// Altitude above the reference sphere — "above sea level".
    var altitude: Double { position.length - body.radius }

    /// Altitude above the ground directly below, which is what matters on approach.
    var altitudeAboveTerrain: Double {
        position.length - body.terrainRadius(atAngle: position.angle)
    }

    var atmosphericPressure: Double {
        body.atmosphere?.pressure(atAltitude: altitude) ?? 0
    }

    var atmosphericDensity: Double {
        body.atmosphere?.density(atAltitude: altitude) ?? 0
    }

    /// Velocity relative to the rotating surface — the number a pilot cares about low down.
    var surfaceVelocity: Vec2 {
        velocity - body.surfaceVelocity(at: position)
    }

    var verticalSpeed: Double {
        surfaceVelocity.dot(position.normalized)
    }

    var horizontalSpeed: Double {
        let up = position.normalized
        return (surfaceVelocity - up * surfaceVelocity.dot(up)).length
    }

    var noseDirection: Vec2 { Vec2.polar(angle: heading) }

    /// Local horizon "up", away from the body's centre.
    var upDirection: Vec2 { position.normalized }

    /// Pitch above the local horizon, degrees. 90 is straight up.
    var pitchAboveHorizon: Double {
        let up = upDirection
        let east = up.perpendicular
        return atan2(noseDirection.dot(up), noseDirection.dot(east)) * 180 / .pi
    }

    var orbit: Orbit {
        Orbit(position: position, velocity: velocity, mu: body.mu, epoch: universeTime)
    }

    var crewCount: Int {
        liveParts.reduce(0) { $0 + ($1.definition?.crewCapacity ?? 0) }
    }

    // MARK: - Engines and propellant

    var ignitedEngines: [PlacedPart] {
        liveParts.filter { p in
            guard let d = p.definition, d.isEngine else { return false }
            let r = runtime[p.id]
            return (r?.ignited ?? false) && !(r?.flamedOut ?? false)
        }
    }

    /// Propellant available to a given engine, kg.
    func availableFuel(for part: PlacedPart) -> Double {
        guard let d = part.definition else { return 0 }
        if d.isSolidBooster { return runtime[part.id]?.solidFuel ?? 0 }
        guard let s = fuelNetwork.sectionOfPart[part.id] else { return 0 }
        return fuelNetwork.fuel[s]
    }

    func consumeFuel(_ amount: Double, for part: PlacedPart) {
        guard let d = part.definition, amount > 0 else { return }
        if d.isSolidBooster {
            var r = runtime[part.id] ?? PartRuntime()
            r.solidFuel = max(0, r.solidFuel - amount)
            if r.solidFuel <= 0 { r.flamedOut = true }
            runtime[part.id] = r
        } else if let s = fuelNetwork.sectionOfPart[part.id] {
            fuelNetwork.fuel[s] = max(0, fuelNetwork.fuel[s] - amount)
        }
    }

    /// Thrust the currently lit engines would produce at the present throttle.
    var currentThrust: Double {
        let p = atmosphericPressure
        var total = 0.0
        for e in ignitedEngines {
            guard let d = e.definition, availableFuel(for: e) > 0 else { continue }
            total += d.thrust(atPressure: p) * (d.throttleable ? throttle : 1)
        }
        return total
    }

    var maxThrust: Double {
        let p = atmosphericPressure
        return ignitedEngines.reduce(0) { $0 + ($1.definition?.thrust(atPressure: p) ?? 0) }
    }

    var thrustToWeight: Double {
        let w = totalMass * body.mu / max(position.lengthSquared, 1)
        return w > 0 ? currentThrust / w : 0
    }

    /// Delta-v left to the current stack, ignoring what is still behind a decoupler.
    var remainingDeltaV: Double {
        let p = atmosphericPressure
        var thrust = 0.0, flow = 0.0, fuel = 0.0
        var counted = Set<Int>()
        for e in ignitedEngines {
            guard let d = e.definition else { continue }
            let t = d.thrust(atPressure: p)
            thrust += t
            flow += t / (d.isp(atPressure: p) * Units.g0)
            if d.isSolidBooster {
                fuel += runtime[e.id]?.solidFuel ?? 0
            } else if let s = fuelNetwork.sectionOfPart[e.id], !counted.contains(s) {
                counted.insert(s)
                fuel += fuelNetwork.fuel[s]
            }
        }
        guard flow > 0, fuel > 0 else { return 0 }
        let isp = thrust / (flow * Units.g0)
        let m0 = totalMass
        let mf = max(m0 - fuel, 1)
        return isp * Units.g0 * log(m0 / mf)
    }

    // MARK: - Geometry

    /// Height of the lowest corner of the rocket above the ground below it.
    ///
    /// Walks the corners without building an array — this runs on every physics
    /// substep, and at high warp that is a dozen times a frame.
    var groundClearance: Double {
        let up = position.normalized
        let rot = heading - .pi / 2
        let c = cos(rot), s = sin(rot)
        var lowest = Double.greatestFiniteMagnitude
        var sawAny = false

        for p in liveParts {
            guard let d = p.definition else { continue }
            sawAny = true
            let hx = d.size.x / 2, hy = d.size.y / 2
            for (dx, dy) in [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)] {
                let lx = p.position.x + dx
                let ly = p.position.y + dy
                // Rotate into world, then project onto the local vertical.
                let wx = position.x + lx * c - ly * s
                let wy = position.y + lx * s + ly * c
                let projected = wx * up.x + wy * up.y
                if projected < lowest { lowest = projected }
            }
        }
        guard sawAny else { return altitudeAboveTerrain }
        return lowest - body.terrainRadius(atAngle: position.angle)
    }

    /// Weakest part in the stack decides what the rocket survives.
    var impactTolerance: Double {
        let base = liveParts.compactMap { $0.definition?.impactTolerance }.min() ?? 6
        let hasLegs = liveParts.contains { $0.definition?.style == .landingLegs }
        return hasLegs ? base * 2 : base
    }
}
