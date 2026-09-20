import Foundation

enum SASMode: String, CaseIterable, Identifiable {
    case off, stability, prograde, retrograde, radialOut, radialIn, surfaceUp
    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "SAS"
        case .stability: return "HOLD"
        case .prograde: return "PRO"
        case .retrograde: return "RET"
        case .radialOut: return "R+"
        case .radialIn: return "R-"
        case .surfaceUp: return "UP"
        }
    }

    var symbol: String {
        switch self {
        case .off: return "power"
        case .stability: return "dot.circle"
        case .prograde: return "arrow.up.forward.circle"
        case .retrograde: return "arrow.down.backward.circle"
        case .radialOut: return "arrow.up.circle"
        case .radialIn: return "arrow.down.circle"
        case .surfaceUp: return "arrow.up.to.line"
        }
    }
}

/// Events the UI reacts to — banners, haptics and sounds.
enum FlightEvent {
    case staged(Int)
    case flameout
    case landed(Double)
    case destroyed(String)
    case soiChange(String)
    case parachuteDeployed
    case parachuteTorn
    case reachedOrbit
    case warpDropped(String)
}

/// Drives the rocket forward in time. Powered and atmospheric flight runs a fixed-step
/// integrator; coasting at high warp switches to analytic Kepler propagation, which is
/// what keeps 100000x warp from melting a phone battery.
final class FlightSimulator {
    private(set) var vessel: Vessel
    let system: SolarSystem
    private(set) var universeTime: Double

    /// Rotation command, -1 (nose left) to +1 (nose right).
    var rotationInput: Double = 0
    var sasMode: SASMode = .off
    var maneuverNode: ManeuverNode?

    /// Collected each step and drained by the UI layer.
    private(set) var events: [FlightEvent] = []

    static let warpFactors: [Double] = [1, 2, 3, 4, 5, 10, 50, 100, 1_000, 10_000, 100_000]
    /// Indices at or above this propagate on rails instead of integrating.
    static let railsWarpThreshold = 4

    var warpIndex: Int = 0
    var warpFactor: Double { FlightSimulator.warpFactors[MathUtil.clamp(warpIndex, 0, FlightSimulator.warpFactors.count - 1)] }
    var isOnRails: Bool { warpIndex >= FlightSimulator.railsWarpThreshold }

    private var railsOrbit: Orbit?
    private let fixedStep: Double = 0.02
    private var accumulator: Double = 0
    /// Cap on integrator steps per frame so a stutter cannot cascade.
    private let maxStepsPerFrame = 12

    init(vessel: Vessel, system: SolarSystem = .shared, universeTime: Double = 0) {
        self.vessel = vessel
        self.system = system
        self.universeTime = universeTime
        vessel.universeTime = universeTime
        vessel.landedLongitude = MathUtil.wrapAngle2Pi(vessel.position.angle - vessel.body.rotationAngle(at: universeTime))
    }

    func drainEvents() -> [FlightEvent] {
        let e = events
        events.removeAll(keepingCapacity: true)
        return e
    }

    // MARK: - Warp control

    func setWarp(index: Int) {
        let clamped = MathUtil.clamp(index, 0, FlightSimulator.warpFactors.count - 1)
        guard clamped != warpIndex else { return }
        if clamped >= FlightSimulator.railsWarpThreshold {
            guard let reason = railsBlockReason() else {
                warpIndex = clamped
                enterRails()
                return
            }
            events.append(.warpDropped(reason))
            warpIndex = min(clamped, FlightSimulator.railsWarpThreshold - 1)
            return
        }
        warpIndex = clamped
        railsOrbit = nil
    }

    /// Why the vessel cannot go on rails right now, or nil when it can.
    func railsBlockReason() -> String? {
        if vessel.situation == .destroyed { return "Vessel destroyed" }
        if vessel.throttle > 0 && vessel.currentThrust > 0 { return "Cannot warp under thrust" }
        if vessel.situation == .landed || vessel.situation == .prelaunch { return nil }
        if vessel.atmosphericDensity > 1e-6 { return "Cannot warp inside the atmosphere" }
        return nil
    }

    private func enterRails() {
        guard vessel.situation != .landed, vessel.situation != .prelaunch else {
            railsOrbit = nil
            return
        }
        railsOrbit = vessel.orbit
    }

    private func dropWarp(_ reason: String) {
        guard warpIndex > 0 else { return }
        warpIndex = 0
        railsOrbit = nil
        events.append(.warpDropped(reason))
    }

    // MARK: - Main update

    /// `realDelta` is wall-clock seconds since the last frame.
    func update(realDelta: Double) {
        guard vessel.situation != .destroyed else { return }
        let clamped = min(realDelta, 0.1)

        if isOnRails {
            stepRails(dt: clamped * warpFactor)
            accumulator = 0
            return
        }

        accumulator += clamped * warpFactor
        var steps = 0
        while accumulator >= fixedStep && steps < maxStepsPerFrame {
            step(dt: fixedStep)
            accumulator -= fixedStep
            steps += 1
            if vessel.situation == .destroyed { break }
        }
        if steps == maxStepsPerFrame { accumulator = 0 }
    }

    // MARK: - On-rails propagation

    private func stepRails(dt: Double) {
        advanceClock(by: dt)

        if vessel.situation == .landed || vessel.situation == .prelaunch {
            // Stay bolted to the rotating surface.
            let angle = vessel.landedLongitude + vessel.body.rotationAngle(at: universeTime)
            let r = vessel.position.length
            vessel.position = Vec2.polar(angle: angle, length: r)
            vessel.velocity = vessel.body.surfaceVelocity(at: vessel.position)
            vessel.heading = angle
            return
        }

        let orbit = railsOrbit ?? vessel.orbit
        railsOrbit = orbit
        let s = orbit.state(at: universeTime)
        vessel.position = s.position
        vessel.velocity = s.velocity

        if updateSphereOfInfluence() {
            railsOrbit = vessel.orbit
        }

        // Drop out of warp before hitting anything.
        let clearance = vessel.groundClearance
        let atmoTop = vessel.body.atmosphere?.height ?? 0
        if clearance < max(atmoTop, 1_000) {
            dropWarp(atmoTop > 0 ? "Atmospheric interface" : "Terrain ahead")
        }
        updateSituation()
    }

    private func advanceClock(by dt: Double) {
        universeTime += dt
        vessel.universeTime = universeTime
        if vessel.situation != .prelaunch { vessel.missionTime += dt }
    }

    // MARK: - Integrated step

    private func step(dt: Double) {
        advanceClock(by: dt)
        let v = vessel
        let body = v.body

        let mass = v.totalMass
        let com = v.centerOfMass
        let inertia = v.momentOfInertia

        // --- Gravity ---
        let r = max(v.position.length, 1)
        var accel = v.position.normalized * (-body.mu / (r * r))

        // --- Thrust ---
        let pressure = v.atmosphericPressure
        var thrustTotal = 0.0
        var gimbalTorque = 0.0
        var flamedOutThisStep = false

        for e in v.ignitedEngines {
            guard let d = e.definition else { continue }
            if v.availableFuel(for: e) <= 0 {
                var rt = v.runtime[e.id] ?? PartRuntime()
                if !rt.flamedOut {
                    rt.flamedOut = true
                    v.runtime[e.id] = rt
                    flamedOutThisStep = true
                }
                continue
            }
            let level = d.throttleable ? v.throttle : 1
            guard level > 0.001 else { continue }
            let f = d.thrust(atPressure: pressure) * level
            thrustTotal += f
            let flow = f / (d.isp(atPressure: pressure) * Units.g0)
            v.consumeFuel(flow * dt, for: e)
            if d.gimbalRange > 0 {
                let lever = abs(e.position.y - com.y) + 0.5
                gimbalTorque += f * sin(d.gimbalRange) * lever
            }
        }
        if flamedOutThisStep {
            events.append(.flameout)
            if v.throttle > 0 { dropWarp("Flameout") }
        }
        if thrustTotal > 0 {
            accel += v.noseDirection * (thrustTotal / mass)
        }

        // --- Aerodynamics ---
        var aeroTorque = 0.0
        let rho = v.atmosphericDensity
        if rho > 1e-9 {
            let airVel = v.velocity - body.surfaceVelocity(at: v.position)
            let speed = airVel.length
            if speed > 0.5 {
                let q = 0.5 * rho * speed * speed
                let aoa = v.noseDirection.signedAngle(to: airVel)

                var dragArea = 0.0
                var weightedY = 0.0
                var liftArea = 0.0
                for p in v.liveParts {
                    guard let d = p.definition else { continue }
                    var a = d.dragCoefficient * d.frontalArea
                    if d.isParachute, let rt = v.runtime[p.id], rt.parachuteDeployed {
                        a += d.parachuteDrag * rt.parachuteOpen
                    }
                    dragArea += a
                    weightedY += a * p.position.y
                    liftArea += d.liftAuthority * d.size.x * d.size.y
                }
                dragArea = max(dragArea, 0.1)
                // Angle of attack turns the whole stack broadside on.
                let sinA = sin(aoa)
                let effectiveArea = dragArea * (1 + 2.5 * sinA * sinA)
                accel -= airVel.normalized * (q * effectiveArea / mass)

                // A centre of pressure behind the centre of mass weathervanes the rocket
                // toward the airflow; ahead of it, the rocket flips. Fins move it back.
                let centerOfPressureY = (dragArea + liftArea) > 0
                    ? (weightedY + liftArea * finCenterY(v)) / (dragArea + liftArea)
                    : com.y
                let lever = com.y - centerOfPressureY
                aeroTorque = q * (dragArea + liftArea * 2.5) * lever * sinA * 0.5
                // Aerodynamic damping, so fins settle the rocket instead of oscillating.
                aeroTorque -= v.angularVelocity * q * (dragArea + liftArea) * 0.35

                if q > 55_000 && v.situation != .prelaunch {
                    checkAerodynamicFailure(q: q)
                }
                updateParachutes(dt: dt, speed: speed, q: q)
            } else {
                updateParachutes(dt: dt, speed: speed, q: 0)
            }
        }

        // --- Attitude control ---
        let reaction = v.liveParts.reduce(0.0) { $0 + ($1.definition?.reactionTorque ?? 0) }
        let authority = reaction + gimbalTorque
        let command = MathUtil.clamp(effectiveRotationCommand(authority: authority, inertia: inertia), -1, 1)
        var torque = command * authority + aeroTorque

        // --- Ground ---
        let clearance = v.groundClearance
        var resting = false
        if clearance <= 0 || v.situation == .landed || v.situation == .prelaunch {
            switch handleGround(clearance: clearance, thrust: thrustTotal, mass: mass, dt: dt) {
            case .destroyed:
                return
            case .resting:
                resting = true
                // Settle upright while the rocket sits on its base.
                let err = MathUtil.wrapAngle(v.position.angle - v.heading)
                torque += err * inertia * 2.0 - v.angularVelocity * inertia * 2.5
            case .airborne:
                break
            }
        }

        // --- Integrate ---
        if !resting {
            let newVelocity = v.velocity + accel * dt
            v.position += (v.velocity + newVelocity) * 0.5 * dt
            v.velocity = newVelocity
        }

        let angularAccel = MathUtil.clamp(torque / inertia, -20, 20)
        v.angularVelocity = MathUtil.clamp(v.angularVelocity + angularAccel * dt, -6, 6)
        v.heading = MathUtil.wrapAngle2Pi(v.heading + v.angularVelocity * dt)

        _ = updateSphereOfInfluence()
        updateSituation()
    }

    /// Average vertical position of the fins, used to place the centre of pressure.
    private func finCenterY(_ v: Vessel) -> Double {
        var sum = 0.0, total = 0.0
        for p in v.liveParts {
            guard let d = p.definition, d.liftAuthority > 0 else { continue }
            let w = d.liftAuthority
            sum += p.position.y * w
            total += w
        }
        return total > 0 ? sum / total : v.centerOfMass.y
    }

    // MARK: - Attitude

    private func effectiveRotationCommand(authority: Double, inertia: Double) -> Double {
        if abs(rotationInput) > 0.02 { return rotationInput }
        guard sasMode != .off, let target = sasTargetHeading() else { return 0 }
        let maxAccel = max(authority / inertia, 1e-6)
        let err = MathUtil.wrapAngle(target - vessel.heading)
        let desired = 3.0 * err - 3.5 * vessel.angularVelocity
        return MathUtil.clamp(desired / maxAccel, -1, 1)
    }

    private func sasTargetHeading() -> Double? {
        let v = vessel
        switch sasMode {
        case .off:
            return nil
        case .stability:
            return v.heading + (-v.angularVelocity * 0.35)
        case .prograde:
            let ref = v.altitude < (v.body.atmosphere?.height ?? 0) ? v.surfaceVelocity : v.velocity
            return ref.length > 1 ? ref.angle : nil
        case .retrograde:
            let ref = v.altitude < (v.body.atmosphere?.height ?? 0) ? v.surfaceVelocity : v.velocity
            return ref.length > 1 ? (ref.angle + .pi) : nil
        case .radialOut:
            return v.position.angle
        case .radialIn:
            return v.position.angle + .pi
        case .surfaceUp:
            return v.position.angle
        }
    }

    // MARK: - Ground handling

    private enum GroundResult { case destroyed, resting, airborne }

    /// Resolves contact with the surface: crash, touchdown, or resting on the pad.
    private func handleGround(clearance: Double, thrust: Double, mass: Double, dt: Double) -> GroundResult {
        let v = vessel
        let weight = mass * v.body.mu / max(v.position.lengthSquared, 1)

        if clearance > 0.25 {
            if v.situation == .landed || v.situation == .prelaunch { v.situation = .flying }
            return .airborne
        }

        let impactSpeed = v.surfaceVelocity.length
        switch v.situation {
        case .flying, .suborbital, .orbiting, .escaping:
            if impactSpeed > v.impactTolerance {
                destroy(reason: String(format: "Impact at %.0f m/s — tolerance was %.0f m/s",
                                       impactSpeed, v.impactTolerance))
                return .destroyed
            }
            events.append(.landed(impactSpeed))
            v.situation = .landed
        default:
            break
        }

        // Cancel any penetration and pin the vessel to the rotating surface.
        if clearance < 0 {
            v.position = v.position.normalized * (v.position.length - clearance)
        }
        v.landedLongitude = MathUtil.wrapAngle2Pi(v.position.angle - v.body.rotationAngle(at: universeTime))

        if thrust > weight * 1.001 {
            v.situation = .flying
            return .airborne
        }

        v.velocity = v.body.surfaceVelocity(at: v.position)
        v.angularVelocity *= max(0, 1 - 6 * dt)
        return .resting
    }

    private func destroy(reason: String) {
        vessel.situation = .destroyed
        vessel.failureReason = reason
        vessel.throttle = 0
        warpIndex = 0
        railsOrbit = nil
        events.append(.destroyed(reason))
    }

    private func checkAerodynamicFailure(q: Double) {
        // Above roughly 55 kPa of dynamic pressure, an unprotected stack starts to shed
        // parts. Parachutes go first.
        for p in vessel.liveParts {
            guard let d = p.definition, d.isParachute,
                  let rt = vessel.runtime[p.id], rt.parachuteDeployed, rt.parachuteOpen > 0
            else { continue }
            if q > 70_000 {
                vessel.runtime[p.id]?.parachuteDeployed = false
                vessel.runtime[p.id]?.parachuteOpen = 0
                vessel.activeParts.remove(p.id)
                events.append(.parachuteTorn)
            }
        }
    }

    // MARK: - Parachutes

    private func updateParachutes(dt: Double, speed: Double, q: Double) {
        for p in vessel.liveParts {
            guard let d = p.definition, d.isParachute,
                  var rt = vessel.runtime[p.id], rt.parachuteDeployed else { continue }
            if q > 45_000 && rt.parachuteOpen < 0.05 {
                // Held in the semi-deployed state until the air is thin enough.
                continue
            }
            rt.parachuteOpen = min(1, rt.parachuteOpen + dt / 2.5)
            vessel.runtime[p.id] = rt
        }
    }

    // MARK: - Sphere of influence

    /// Returns true when the reference body changed.
    @discardableResult
    private func updateSphereOfInfluence() -> Bool {
        let v = vessel
        let body = v.body

        if let parent = body.parent, v.position.length > body.soiRadius {
            v.position = v.position + body.positionRelativeToParent(at: universeTime)
            v.velocity = v.velocity + body.velocityRelativeToParent(at: universeTime)
            v.body = parent
            events.append(.soiChange(parent.name))
            return true
        }

        for child in system.childBodies(of: body) {
            let rel = v.position - child.positionRelativeToParent(at: universeTime)
            if rel.length < child.soiRadius {
                v.position = rel
                v.velocity = v.velocity - child.velocityRelativeToParent(at: universeTime)
                v.body = child
                events.append(.soiChange(child.name))
                return true
            }
        }
        return false
    }

    private func updateSituation() {
        let v = vessel
        guard v.situation != .destroyed else { return }
        if v.situation == .landed || v.situation == .prelaunch { return }

        let o = v.orbit
        let atmoTop = v.body.atmosphere?.height ?? 0
        let wasOrbiting = v.situation == .orbiting
        if !o.isClosed {
            v.situation = .escaping
        } else if o.periapsis > v.body.radius + atmoTop {
            v.situation = .orbiting
            if !wasOrbiting { events.append(.reachedOrbit) }
        } else if v.altitude > atmoTop {
            v.situation = .suborbital
        } else {
            v.situation = .flying
        }
    }

    // MARK: - Staging

    var canStage: Bool {
        vessel.situation != .destroyed && vessel.currentStage < vessel.design.stageCount
    }

    func activateNextStage() {
        guard canStage else { return }
        let v = vessel
        let stage = v.currentStage
        let staged = v.design.activatedParts(inStage: stage)
        let rootID = v.design.root?.id

        // 1. Jettison decouplers and any radial booster that has already burned.
        var jettison = Set<UUID>()
        for p in staged {
            guard let d = p.definition, v.activeParts.contains(p.id) else { continue }
            if d.isDecoupler {
                jettison.formUnion(v.design.subtree(of: p.id))
            } else if d.isSolidBooster, p.attachKind == .radial,
                      v.runtime[p.id]?.ignited == true {
                jettison.formUnion(v.design.subtree(of: p.id))
            }
        }
        if let rootID, jettison.contains(rootID) {
            // Never throw away the part we are flying from.
            jettison.subtract(v.design.subtree(of: rootID))
        }
        v.activeParts.subtract(jettison)

        // 2. Light the engines and pop the chutes.
        for p in staged where v.activeParts.contains(p.id) {
            guard let d = p.definition else { continue }
            if d.isEngine {
                v.runtime[p.id]?.ignited = true
            } else if d.isParachute {
                deployParachute(p)
            }
        }

        v.fuelNetwork = FuelNetwork(design: v.design, active: v.activeParts, preserving: v.fuelNetwork)
        v.currentStage += 1
        if v.situation == .prelaunch && v.throttle == 0 { v.throttle = 1 }
        events.append(.staged(stage))
        if warpIndex > 0 { dropWarp("Staging") }
    }

    func deployAllParachutes() {
        for p in vessel.liveParts where p.definition?.isParachute == true {
            deployParachute(p)
        }
    }

    private func deployParachute(_ p: PlacedPart) {
        guard var rt = vessel.runtime[p.id], !rt.parachuteDeployed else { return }
        let speed = vessel.surfaceVelocity.length
        let rho = vessel.atmosphericDensity
        let q = 0.5 * rho * speed * speed
        if q > 70_000 {
            vessel.activeParts.remove(p.id)
            events.append(.parachuteTorn)
            return
        }
        rt.parachuteDeployed = true
        vessel.runtime[p.id] = rt
        events.append(.parachuteDeployed)
        if warpIndex > 0 { dropWarp("Parachute deployed") }
    }

    // MARK: - Throttle

    func setThrottle(_ value: Double) {
        vessel.throttle = MathUtil.clamp(value, 0, 1)
        if vessel.throttle > 0 && isOnRails {
            dropWarp("Throttle up")
        }
    }
}
