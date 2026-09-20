import Combine
import SwiftUI
import UIKit

/// Everything the HUD displays, gathered once per refresh so SwiftUI redraws a single
/// value rather than reading through to the simulation sixty times a second.
struct HUDSnapshot {
    var situation: Situation = .prelaunch
    var bodyName: String = ""
    var altitude: Double = 0
    var altitudeAboveTerrain: Double = 0
    var surfaceSpeed: Double = 0
    var orbitalSpeed: Double = 0
    var verticalSpeed: Double = 0
    var apoapsis: Double?
    var periapsis: Double = 0
    var timeToApoapsis: Double?
    var timeToPeriapsis: Double?
    var period: Double?
    var throttle: Double = 0
    var thrust: Double = 0
    var twr: Double = 0
    var mass: Double = 0
    var fuelFraction: Double = 0
    var stageDeltaV: Double = 0
    var missionTime: Double = 0
    var universeTime: Double = 0
    var heading: Double = 0
    var pitch: Double = 0
    var progradeAngle: Double = 0
    var retrogradeAngle: Double = 0
    var radialAngle: Double = 0
    var angleOfAttack: Double = 0
    var dynamicPressure: Double = 0
    var atmosphereFraction: Double = 0
    var stagesRemaining: Int = 0
    var currentStage: Int = 0
    var warpFactor: Double = 1
    var crew: Int = 0
    var isAtmospheric: Bool = false
}

/// Owns the simulation for one flight and republishes it at a rate a phone display
/// can actually use.
///
/// Deliberately not actor-isolated: every caller (the SpriteKit render loop and the
/// SwiftUI views) already runs on the main thread, and annotating it would only add
/// isolation noise at the SKScene override boundary.
final class FlightModel: ObservableObject {
    let simulator: FlightSimulator

    @Published private(set) var hud = HUDSnapshot()
    @Published private(set) var patches: [TrajectoryPatch] = []
    @Published var showMap = false
    @Published var banner: BannerMessage? = nil
    @Published var maneuver: ManeuverNode? = nil
    @Published private(set) var isPaused = false
    @Published private(set) var sasMode: SASMode = .off
    @Published private(set) var warpIndex: Int = 0
    /// Bumped whenever the staging list changes, to nudge SwiftUI into redrawing it.
    @Published private(set) var stagingRevision: Int = 0

    struct BannerMessage: Identifiable, Equatable {
        let id = UUID()
        let text: String
        var isFailure = false
    }

    private var hudAccumulator: Double = 0
    private var trajectoryAccumulator: Double = 0
    private var autosaveAccumulator: Double = 0
    private let hudInterval: Double = 1.0 / 15.0
    private let trajectoryInterval: Double = 0.25
    private let autosaveInterval: Double = 20

    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)
    var hapticsEnabled = true

    init(simulator: FlightSimulator) {
        self.simulator = simulator
        refreshHUD()
        refreshTrajectory()
    }

    convenience init(design: VesselDesign, system: SolarSystem = .shared) {
        let body = system.home
        // Launch from the equator, sitting on the terrain, nose up and co-rotating.
        let launchAngle = 0.0
        var design = design
        design.normalizeStages()
        let surface = body.terrainRadius(atAngle: launchAngle)
        let position = Vec2.polar(angle: launchAngle, length: surface)
        let vessel = Vessel(design: design, body: body, position: position,
                            velocity: body.surfaceVelocity(at: position),
                            heading: launchAngle)
        // Seat the rocket on the pad: lift it by however far its base hangs below.
        let clearance = vessel.groundClearance
        vessel.position = position.normalized * (position.length - clearance)
        vessel.velocity = body.surfaceVelocity(at: vessel.position)
        vessel.situation = .prelaunch
        self.init(simulator: FlightSimulator(vessel: vessel, system: system))
    }

    // MARK: - Frame

    /// Called from the SpriteKit render loop.
    func advance(realDelta: Double) {
        guard !isPaused else { return }
        simulator.update(realDelta: realDelta)
        handle(events: simulator.drainEvents())

        hudAccumulator += realDelta
        if hudAccumulator >= hudInterval {
            hudAccumulator = 0
            refreshHUD()
        }
        trajectoryAccumulator += realDelta
        if trajectoryAccumulator >= trajectoryInterval {
            trajectoryAccumulator = 0
            refreshTrajectory()
        }
        autosaveAccumulator += realDelta
        if autosaveAccumulator >= autosaveInterval {
            autosaveAccumulator = 0
            if simulator.vessel.situation != .destroyed {
                SaveStore.shared.saveFlight(simulator)
            }
        }
    }

    func refreshHUD() {
        let v = simulator.vessel
        let o = v.orbit
        var s = HUDSnapshot()
        s.situation = v.situation
        s.bodyName = v.body.name
        s.altitude = v.altitude
        s.altitudeAboveTerrain = v.altitudeAboveTerrain
        s.surfaceSpeed = v.surfaceVelocity.length
        s.orbitalSpeed = v.velocity.length
        s.verticalSpeed = v.verticalSpeed
        s.apoapsis = o.apoapsis.map { $0 - v.body.radius }
        s.periapsis = o.periapsis - v.body.radius
        s.timeToApoapsis = o.timeOfApoapsis(after: v.universeTime).map { $0 - v.universeTime }
        s.timeToPeriapsis = o.timeOfPeriapsis(after: v.universeTime).map { $0 - v.universeTime }
        s.period = o.period
        s.throttle = v.throttle
        s.thrust = v.currentThrust
        s.twr = v.thrustToWeight
        s.mass = v.totalMass
        s.fuelFraction = v.fuelNetwork.totalCapacity > 0
            ? v.fuelNetwork.totalFuel / v.fuelNetwork.totalCapacity : 0
        s.stageDeltaV = v.remainingDeltaV
        s.missionTime = v.missionTime
        s.universeTime = v.universeTime
        s.heading = v.heading
        s.pitch = v.pitchAboveHorizon
        let reference = v.altitude < (v.body.atmosphere?.height ?? 0) ? v.surfaceVelocity : v.velocity
        s.progradeAngle = reference.length > 0.5 ? reference.angle : v.heading
        s.retrogradeAngle = s.progradeAngle + .pi
        s.radialAngle = v.position.angle
        s.angleOfAttack = reference.length > 0.5
            ? v.noseDirection.signedAngle(to: reference) * 180 / .pi : 0
        let rho = v.atmosphericDensity
        s.dynamicPressure = 0.5 * rho * v.surfaceVelocity.lengthSquared
        s.atmosphereFraction = v.body.atmosphere.map {
            $0.spaceFraction(atAltitude: v.altitude)
        } ?? 1
        s.isAtmospheric = v.atmosphericDensity > 1e-6
        s.stagesRemaining = max(0, v.design.stageCount - v.currentStage)
        s.currentStage = v.currentStage
        s.warpFactor = simulator.warpFactor
        s.crew = v.crewCount
        hud = s
        sasMode = simulator.sasMode
        warpIndex = simulator.warpIndex
    }

    func refreshTrajectory() {
        var list = TrajectoryPredictor.predict(vessel: simulator.vessel)
        // Draw the planned burn's result as an extra patch.
        if let node = maneuver, node.deltaV > 0, let first = list.first {
            let after = node.resultingOrbit(from: first.orbit)
            list.append(TrajectoryPatch(body: simulator.vessel.body, orbit: after,
                                        startTime: node.time,
                                        endTime: node.time + (after.period ?? 3600 * 6),
                                        end: after.isClosed ? .closedOrbit : .horizon))
        }
        patches = list
    }

    // MARK: - Events

    private func handle(events: [FlightEvent]) {
        for event in events {
            switch event {
            case .staged(let index):
                tap(.light)
                stagingRevision &+= 1
                banner = BannerMessage(text: "Stage \(index + 1) activated")
            case .flameout:
                banner = BannerMessage(text: "Flameout")
            case .landed(let speed):
                tap(.heavy)
                banner = BannerMessage(text: String(format: "Touchdown at %.1f m/s", speed))
            case .destroyed(let reason):
                tap(.heavy)
                banner = BannerMessage(text: reason, isFailure: true)
            case .soiChange(let name):
                banner = BannerMessage(text: "Now orbiting \(name)")
                refreshTrajectory()
            case .parachuteDeployed:
                tap(.light)
                banner = BannerMessage(text: "Parachute deployed")
            case .parachuteTorn:
                tap(.heavy)
                banner = BannerMessage(text: "Parachute torn off — too fast, too low", isFailure: true)
            case .reachedOrbit:
                tap(.light)
                banner = BannerMessage(text: "Orbit achieved")
            case .warpDropped(let reason):
                banner = BannerMessage(text: reason)
            }
        }
    }

    private func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard hapticsEnabled else { return }
        switch style {
        case .heavy: heavyHaptic.impactOccurred()
        default: lightHaptic.impactOccurred()
        }
    }

    // MARK: - Controls

    func setThrottle(_ value: Double) {
        simulator.setThrottle(value)
        hud.throttle = simulator.vessel.throttle
    }

    func setRotation(_ value: Double) {
        simulator.rotationInput = MathUtil.clamp(value, -1, 1)
        if abs(value) > 0.02 && simulator.sasMode != .off && simulator.sasMode != .stability {
            // Manual input overrides a hold, the way it does in the cockpit.
            simulator.sasMode = .stability
            sasMode = .stability
        }
    }

    func cycleSAS(to mode: SASMode) {
        simulator.sasMode = simulator.sasMode == mode ? .off : mode
        sasMode = simulator.sasMode
        tap(.light)
    }

    func stage() {
        simulator.activateNextStage()
        refreshHUD()
        refreshTrajectory()
    }

    func deployChutes() {
        simulator.deployAllParachutes()
        refreshHUD()
    }

    func changeWarp(by delta: Int) {
        simulator.setWarp(index: simulator.warpIndex + delta)
        warpIndex = simulator.warpIndex
        handle(events: simulator.drainEvents())
        refreshHUD()
    }

    func togglePause() {
        isPaused.toggle()
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        if paused, simulator.vessel.situation != .destroyed {
            SaveStore.shared.saveFlight(simulator)
        }
    }

    // MARK: - Maneuver planning

    func createManeuver() {
        let v = simulator.vessel
        let lead = max(60, (v.orbit.period ?? 600) * 0.25)
        maneuver = ManeuverNode(time: v.universeTime + lead)
        refreshTrajectory()
    }

    func adjustManeuver(prograde: Double = 0, radial: Double = 0, time: Double = 0) {
        guard var node = maneuver else { return }
        node.prograde += prograde
        node.radial += radial
        node.time = max(simulator.vessel.universeTime + 5, node.time + time)
        maneuver = node
        refreshTrajectory()
    }

    func clearManeuver() {
        maneuver = nil
        refreshTrajectory()
    }

    var maneuverCountdown: Double? {
        guard let node = maneuver else { return nil }
        return node.timeToIgnition(vessel: simulator.vessel, now: simulator.vessel.universeTime)
    }

    var maneuverBurnDuration: Double? {
        maneuver.map { $0.burnDuration(vessel: simulator.vessel) }
    }
}
