import SpriteKit
import SwiftUI
import UIKit

/// The world view during flight, with the visual mod stack layered on top.
///
/// Everything is drawn with the vessel pinned at the centre of the screen — a floating
/// origin. Planets are hundreds of kilometres across, and feeding coordinates that large
/// to the GPU (which works in single precision) makes geometry shimmer, so the scene
/// never holds an absolute position larger than a screen's worth of metres.
final class FlightScene: SKScene {

    weak var model: FlightModel? = nil

    /// Which visual mods are switched on. Changing it rebuilds what needs rebuilding.
    var visuals: VisualSettings = .default {
        didSet {
            guard visuals != oldValue else { return }
            if visuals.starCount != oldValue.starCount { buildStars() }
            rebuildPlumes = true
        }
    }

    /// Zoom, in screen points per metre.
    private(set) var pointsPerMeter: Double = 6
    private let minZoom: Double = 0.00004
    private let maxZoom: Double = 60

    // Layers, back to front.
    private let sky = SkyGradientNode()
    private let starLayer = SKNode()
    private let distantObjects = DistantObjectsNode()
    private let horizonGlow = SKSpriteNode()
    private let planetNode = PlanetNode()
    private let terrainNode = SKShapeNode()
    private let cloudBand = CloudBandNode()
    private let reentry = ReentryNode()
    private let vesselNode = SKNode()

    private var partNodes: [UUID: SKNode] = [:]
    private var plumes: [UUID: PlumeNode] = [:]
    private var builtPartSignature: Int = -1
    private var rebuildPlumes = false
    private var lastUpdate: TimeInterval = 0
    /// Slow drift of the cloud sheet relative to the ground.
    private var cloudPhase: Double = 0

    // MARK: - Setup

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.02, green: 0.03, blue: 0.07, alpha: 1)
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)

        sky.zPosition = -100
        addChild(sky)

        starLayer.zPosition = -95
        addChild(starLayer)
        buildStars()

        distantObjects.zPosition = -90
        addChild(distantObjects)

        horizonGlow.texture = ProceduralTexture.glow
        horizonGlow.blendMode = .add
        horizonGlow.zPosition = -80
        horizonGlow.isHidden = true
        addChild(horizonGlow)

        planetNode.zPosition = -60
        addChild(planetNode)

        terrainNode.zPosition = -50
        terrainNode.lineWidth = 0
        addChild(terrainNode)

        cloudBand.zPosition = -25
        addChild(cloudBand)

        reentry.zPosition = 8
        addChild(reentry)

        vesselNode.zPosition = 10
        addChild(vesselNode)

        if let model { fitZoom(to: model) }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        buildStars()
    }

    /// Picks an initial zoom that puts the whole rocket comfortably on screen.
    func fitZoom(to model: FlightModel) {
        let h = max(model.simulator.vessel.design.height, 2)
        pointsPerMeter = MathUtil.clamp(Double(size.height) * 0.30 / h, 1.5, 30)
    }

    func zoom(by factor: Double) {
        pointsPerMeter = MathUtil.clamp(pointsPerMeter * factor, minZoom, maxZoom)
    }

    // MARK: - Stars

    private func buildStars() {
        starLayer.removeAllChildren()
        guard size.width > 0 else { return }
        // A fixed pseudo-random field; the seed is constant so the sky does not
        // reshuffle when the view resizes.
        var seed: UInt64 = 0x5DEECE66D
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) % 100_000) / 100_000
        }
        for _ in 0..<visuals.starCount {
            let star = SKSpriteNode(texture: ProceduralTexture.particle)
            star.size = CGSize(width: 3, height: 3)
            star.position = CGPoint(x: (random() - 0.5) * size.width * 1.6,
                                    y: (random() - 0.5) * size.height * 1.6)
            let brightness = random()
            star.alpha = CGFloat(0.25 + brightness * 0.75)
            star.setScale(CGFloat(0.5 + brightness * 1.2))
            // A few warm and cool stars stop the field reading as grey noise.
            let hue = random()
            if hue > 0.86 {
                star.color = SKColor(red: 1.0, green: 0.82, blue: 0.68, alpha: 1)
                star.colorBlendFactor = 0.7
            } else if hue < 0.14 {
                star.color = SKColor(red: 0.74, green: 0.84, blue: 1.0, alpha: 1)
                star.colorBlendFactor = 0.7
            }
            starLayer.addChild(star)
        }
    }

    // MARK: - Frame

    override func update(_ currentTime: TimeInterval) {
        guard let model else { return }
        let delta = lastUpdate == 0 ? 1.0 / 60.0 : min(currentTime - lastUpdate, 0.1)
        lastUpdate = currentTime

        model.advance(realDelta: delta)

        let vessel = model.simulator.vessel
        // The cloud sheet drifts slowly against the ground, scaled by time warp so it
        // still moves visibly when the mission is running fast.
        cloudPhase += delta * 1.4e-5 * max(1, model.simulator.warpFactor)

        rebuildVesselIfNeeded(vessel)
        updateSky(vessel)
        updateWorld(vessel)
        updateVessel(vessel)
        updatePlumes(vessel)
        updateReentry(vessel)
    }

    // MARK: - Sky and scattering

    private func updateSky(_ vessel: Vessel) {
        let system = SolarSystem.shared
        let sunElevation = system.sunElevation(at: vessel.position)
        let sample = Scattering.sample(body: vessel.body,
                                       altitude: vessel.altitude,
                                       sunElevation: sunElevation)

        if visuals.cloudsAndScattering {
            sky.update(top: sample.zenith, bottom: sample.horizon, size: size)
        } else {
            // Without Scatterer, fall back to the flat two-colour sky.
            let f = vessel.body.atmosphere?.spaceFraction(atAltitude: vessel.altitude) ?? 1
            let flat = FlightScene.blend(SKColor(red: 0.33, green: 0.58, blue: 0.92, alpha: 1),
                                         SKColor(red: 0.02, green: 0.03, blue: 0.07, alpha: 1),
                                         CGFloat(pow(f, 0.6)))
            sky.update(top: flat, bottom: flat, size: size)
        }

        distantObjects.update(system: system, vessel: vessel,
                              time: vessel.universeTime,
                              pointsPerMeter: pointsPerMeter,
                              viewSize: size, settings: visuals)

        starLayer.alpha = CGFloat(MathUtil.clamp(
            sample.starVisibility * (1 - distantObjects.skyDimming), 0, 1))

        // Scatterer's sunset band, sitting on the horizon and leaning toward the sun.
        let glowAlpha = visuals.cloudsAndScattering
            ? CGFloat(sample.horizonGlow.cgColor.alpha) : 0
        horizonGlow.isHidden = glowAlpha < 0.01
        if !horizonGlow.isHidden {
            let up = vessel.position.normalized
            let east = up.perpendicular
            let sunEast = system.sunDirection.dot(east)
            // The horizon sits one altitude below the vessel on screen.
            let horizonY = -vessel.altitude * pointsPerMeter
            horizonGlow.position = CGPoint(
                x: CGFloat(sunEast) * size.width * 0.34,
                y: CGFloat(MathUtil.clamp(horizonY, Double(-size.height), Double(size.height) * 0.1))
            )
            horizonGlow.size = CGSize(width: size.width * 2.2, height: size.height * 0.85)
            horizonGlow.color = sample.horizonGlow
            horizonGlow.colorBlendFactor = 1
            horizonGlow.alpha = glowAlpha
        }
    }

    private static func blend(_ a: SKColor, _ b: SKColor, _ t: CGFloat) -> SKColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        _ = a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        _ = b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let k = max(0, min(1, t))
        return SKColor(red: ar + (br - ar) * k, green: ag + (bg - ag) * k,
                       blue: ab + (bb - ab) * k, alpha: aa + (ba - aa) * k)
    }

    // MARK: - World

    private func updateWorld(_ vessel: Vessel) {
        let body = vessel.body
        let system = SolarSystem.shared
        let scale = pointsPerMeter
        let altitude = vessel.altitude

        // Close to the surface, draw only the visible slice of ground as a polygon.
        // Far away, the whole body fits on screen as a textured disc.
        let halfWidthMeters = Double(size.width) / 2 / scale
        let useSurfaceView = altitude < body.radius * 0.6 && halfWidthMeters < body.radius * 0.5

        terrainNode.isHidden = !useSurfaceView
        planetNode.isHidden = useSurfaceView

        if useSurfaceView {
            let path = CGMutablePath()
            let centerAngle = vessel.position.angle
            let span = (halfWidthMeters * 1.6) / body.radius + 1e-5
            let steps = 96
            let depth = Double(size.height) / scale + halfWidthMeters
            var first = true
            for i in 0...steps {
                let a = centerAngle - span + 2 * span * Double(i) / Double(steps)
                let groundR = body.terrainRadius(atAngle: a)
                let world = Vec2.polar(angle: a, length: groundR)
                let p = toScene(world - vessel.position, scale: scale)
                if first { path.move(to: p); first = false } else { path.addLine(to: p) }
            }
            // Close the polygon well below the visible area.
            let right = Vec2.polar(angle: centerAngle + span, length: body.radius - depth)
            let left = Vec2.polar(angle: centerAngle - span, length: body.radius - depth)
            path.addLine(to: toScene(right - vessel.position, scale: scale))
            path.addLine(to: toScene(left - vessel.position, scale: scale))
            path.closeSubpath()
            terrainNode.path = path

            // Ground lighting: full colour at noon, deep blue at night, warm at dusk.
            let sunElevation = system.sunElevation(at: vessel.position)
            terrainNode.fillColor = groundColor(for: body, sunElevation: sunElevation)
            terrainNode.strokeColor = SKColor(body.deepColor)
            terrainNode.lineWidth = 2
        } else {
            planetNode.position = toScene(-vessel.position, scale: scale)
            planetNode.update(body: body,
                              radiusPoints: body.radius * scale,
                              bodyRotation: body.rotationAngle(at: vessel.universeTime),
                              sunDirection: system.sunDirection,
                              cloudPhase: cloudPhase,
                              settings: visuals)
        }

        cloudBand.isHidden = !useSurfaceView
        if useSurfaceView {
            cloudBand.update(body: body,
                             vesselPosition: vessel.position,
                             pointsPerMeter: scale,
                             viewSize: size,
                             bodyRotation: body.rotationAngle(at: vessel.universeTime),
                             sunElevation: system.sunElevation(at: vessel.position),
                             settings: visuals)
        }
    }

    private func groundColor(for body: CelestialBody, sunElevation: Double) -> SKColor {
        let base = SKColor(body.surfaceColor)
        guard visuals.cloudsAndScattering else { return base }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = base.getRed(&r, green: &g, blue: &b, alpha: &a)

        let day = CGFloat(MathUtil.clamp(MathUtil.remap(sunElevation, -0.22, 0.20, 0, 1), 0, 1))
        let golden = CGFloat(pow(max(0, 1 - abs(sunElevation) / 0.34), 1.6))
        // Night: dark and blue. Dusk: warm. Day: as authored.
        let night = SKColor(red: r * 0.16, green: g * 0.18, blue: b * 0.30 + 0.03, alpha: 1)
        let lit = FlightScene.blend(SKColor(red: r, green: g, blue: b, alpha: 1),
                                    SKColor(red: min(1, r * 1.25 + 0.18),
                                            green: g * 0.92, blue: b * 0.68, alpha: 1),
                                    golden * 0.7)
        return FlightScene.blend(night, lit, day)
    }

    private func toScene(_ offsetMeters: Vec2, scale: Double) -> CGPoint {
        CGPoint(x: offsetMeters.x * scale, y: offsetMeters.y * scale)
    }

    // MARK: - Vessel

    /// Cheap signature that changes when parts are added, dropped or a chute opens.
    private func partSignature(_ vessel: Vessel) -> Int {
        var hasher = Hasher()
        for id in vessel.activeParts.sorted(by: { $0.uuidString < $1.uuidString }) {
            hasher.combine(id)
            hasher.combine(vessel.runtime[id]?.parachuteDeployed ?? false)
        }
        return hasher.finalize()
    }

    private func rebuildVesselIfNeeded(_ vessel: Vessel) {
        let signature = partSignature(vessel)
        guard signature != builtPartSignature || rebuildPlumes else { return }
        builtPartSignature = signature
        rebuildPlumes = false

        vesselNode.removeAllChildren()
        partNodes.removeAll()
        plumes.removeAll()

        for part in vessel.liveParts {
            guard let def = part.definition else { continue }
            let node = SKNode()
            node.position = CGPoint(x: part.position.x, y: part.position.y)
            if part.side < 0 { node.xScale = -1 }

            for layer in PartGeometry.layers(for: def,
                                             fuelFraction: 1,
                                             chuteOpen: vessel.runtime[part.id]?.parachuteOpen ?? 0) {
                let shape = SKShapeNode(path: layer.path)
                shape.name = layer.role
                shape.fillColor = layer.fill.map { SKColor($0) } ?? .clear
                shape.strokeColor = layer.stroke.map { SKColor($0) } ?? .clear
                shape.lineWidth = CGFloat(layer.lineWidth)
                shape.isAntialiased = true
                node.addChild(shape)
            }
            vesselNode.addChild(node)
            partNodes[part.id] = node

            if def.isEngine {
                let plume = PlumeNode()
                plume.configure(definition: def)
                plume.position = CGPoint(x: part.position.x,
                                         y: part.position.y - def.size.y / 2)
                if part.side < 0 { plume.xScale = -1 }
                plume.zPosition = -1
                vesselNode.addChild(plume)
                plumes[part.id] = plume
            }
        }
    }

    private func updateVessel(_ vessel: Vessel) {
        vesselNode.setScale(CGFloat(pointsPerMeter))
        vesselNode.position = .zero
        vesselNode.zRotation = CGFloat(vessel.heading - .pi / 2)
        vesselNode.alpha = vessel.situation == .destroyed ? 0.35 : 1

        // Keep propellant levels in sync without rebuilding nodes.
        for part in vessel.liveParts {
            guard let def = part.definition, let node = partNodes[part.id] else { continue }
            if def.isTank || def.isSolidBooster {
                let fraction = def.isSolidBooster
                    ? (vessel.runtime[part.id]?.solidFuel ?? 0) / max(def.fuelCapacity, 1)
                    : vessel.fuelNetwork.fraction(ofPart: part.id)
                if let bar = node.childNode(withName: "fuel") as? SKShapeNode {
                    bar.yScale = CGFloat(max(0.001, fraction))
                    bar.position = CGPoint(x: 0, y: -def.size.y * 0.46 * (1 - fraction))
                }
            }
        }
    }

    private func updatePlumes(_ vessel: Vessel) {
        let pressure = vessel.atmosphericPressure
        for part in vessel.liveParts {
            guard let def = part.definition, def.isEngine,
                  let plume = plumes[part.id] else { continue }
            let runtime = vessel.runtime[part.id]
            let lit = (runtime?.ignited ?? false)
                && !(runtime?.flamedOut ?? false)
                && vessel.availableFuel(for: part) > 0
            let level = def.throttleable ? vessel.throttle : 1
            plume.update(intensity: lit ? level : 0, pressure: pressure, settings: visuals)
        }
    }

    private func updateReentry(_ vessel: Vessel) {
        let airVelocity = vessel.surfaceVelocity
        let sizePoints = max(vessel.design.height, 1) * pointsPerMeter * 0.5
        reentry.update(density: vessel.atmosphericDensity,
                       airspeed: airVelocity.length,
                       travelAngle: airVelocity.length > 1 ? airVelocity.angle : vessel.heading,
                       vesselSizePoints: sizePoints,
                       settings: visuals)
    }
}
