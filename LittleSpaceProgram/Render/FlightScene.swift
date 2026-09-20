import SpriteKit
import SwiftUI
import UIKit

/// The world view during flight.
///
/// Everything is drawn with the vessel pinned at the centre of the screen — a floating
/// origin. Planets are hundreds of kilometres across, and feeding coordinates that large
/// to the GPU (which works in single precision) makes geometry shimmer, so the scene
/// never holds an absolute position larger than a screen's worth of metres.
final class FlightScene: SKScene {

    weak var model: FlightModel? = nil

    /// Zoom, in screen points per metre.
    private(set) var pointsPerMeter: Double = 6
    private let minZoom: Double = 0.00004
    private let maxZoom: Double = 60

    private let skyNode = SKSpriteNode()
    private let starLayer = SKNode()
    private let terrainNode = SKShapeNode()
    private let planetNode = SKShapeNode()
    private let atmosphereNode = SKShapeNode()
    private let vesselNode = SKNode()
    private let effectsNode = SKNode()

    private var partNodes: [UUID: SKNode] = [:]
    private var exhaustNodes: [UUID: SKEmitterNode] = [:]
    private var builtPartSignature: Int = -1
    private var lastUpdate: TimeInterval = 0
    private var particleTexture: SKTexture? = nil

    // MARK: - Setup

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.02, green: 0.03, blue: 0.07, alpha: 1)
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)

        skyNode.zPosition = -100
        skyNode.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        addChild(skyNode)

        starLayer.zPosition = -90
        addChild(starLayer)
        buildStars()

        atmosphereNode.zPosition = -50
        atmosphereNode.lineWidth = 0
        addChild(atmosphereNode)

        planetNode.zPosition = -40
        planetNode.lineWidth = 0
        addChild(planetNode)

        terrainNode.zPosition = -30
        terrainNode.lineWidth = 0
        addChild(terrainNode)

        effectsNode.zPosition = 5
        addChild(effectsNode)

        vesselNode.zPosition = 10
        addChild(vesselNode)

        particleTexture = FlightScene.makeParticleTexture()
        if let model { fitZoom(to: model) }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        skyNode.size = size
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
        let count = 220
        for _ in 0..<count {
            let star = SKSpriteNode(color: .white, size: CGSize(width: 2, height: 2))
            star.position = CGPoint(x: (random() - 0.5) * size.width * 1.6,
                                    y: (random() - 0.5) * size.height * 1.6)
            let brightness = 0.25 + random() * 0.75
            star.alpha = brightness
            star.setScale(0.6 + random() * 1.1)
            starLayer.addChild(star)
        }
    }

    private static func makeParticleTexture() -> SKTexture {
        let side = 32
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { ctx in
            let colors = [UIColor.white.cgColor,
                          UIColor.white.withAlphaComponent(0.0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors, locations: [0, 1]) else { return }
            let center = CGPoint(x: side / 2, y: side / 2)
            ctx.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                             endCenter: center, endRadius: CGFloat(side) / 2,
                                             options: [])
        }
        return SKTexture(image: image)
    }

    // MARK: - Frame

    override func update(_ currentTime: TimeInterval) {
        guard let model else { return }
        let delta = lastUpdate == 0 ? 1.0 / 60.0 : min(currentTime - lastUpdate, 0.1)
        lastUpdate = currentTime

        model.advance(realDelta: delta)

        let vessel = model.simulator.vessel
        rebuildVesselIfNeeded(vessel)
        updateSky(vessel)
        updateWorld(vessel)
        updateVessel(vessel)
        updateExhaust(vessel)
    }

    // MARK: - Sky

    private func updateSky(_ vessel: Vessel) {
        skyNode.size = size
        let body = vessel.body
        guard let atmo = body.atmosphere else {
            skyNode.color = SKColor(red: 0.02, green: 0.025, blue: 0.055, alpha: 1)
            starLayer.alpha = 1
            return
        }
        // Blue near the ground, fading to black at the top of the atmosphere.
        let f = atmo.spaceFraction(atAltitude: vessel.altitude)
        let eased = pow(f, 0.6)
        let day = SKColor(red: 0.33, green: 0.58, blue: 0.92, alpha: 1)
        let space = SKColor(red: 0.02, green: 0.03, blue: 0.07, alpha: 1)
        skyNode.color = FlightScene.blend(day, space, CGFloat(eased))
        starLayer.alpha = CGFloat(MathUtil.remap(f, 0.25, 0.75, 0, 1))
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
        let scale = pointsPerMeter
        let altitude = vessel.altitude

        // Close to the surface, draw only the visible slice of ground as a polygon.
        // Far away, the whole body fits on screen as a circle.
        let halfWidthMeters = Double(size.width) / 2 / scale
        let useSurfaceView = altitude < body.radius * 0.6 && halfWidthMeters < body.radius * 0.5

        terrainNode.isHidden = !useSurfaceView
        planetNode.isHidden = useSurfaceView
        atmosphereNode.isHidden = useSurfaceView || body.atmosphere == nil

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
            terrainNode.fillColor = SKColor(body.surfaceColor)
            terrainNode.strokeColor = SKColor(body.deepColor)
            terrainNode.lineWidth = 2
        } else {
            let radiusPoints = CGFloat(body.radius * scale)
            let center = toScene(-vessel.position, scale: scale)
            planetNode.path = CGPath(ellipseIn: CGRect(x: -radiusPoints, y: -radiusPoints,
                                                       width: radiusPoints * 2,
                                                       height: radiusPoints * 2), transform: nil)
            planetNode.position = center
            planetNode.fillColor = SKColor(body.surfaceColor)

            if let atmo = body.atmosphere {
                let outer = CGFloat((body.radius + atmo.height) * scale)
                atmosphereNode.path = CGPath(ellipseIn: CGRect(x: -outer, y: -outer,
                                                               width: outer * 2, height: outer * 2),
                                             transform: nil)
                atmosphereNode.position = center
                atmosphereNode.fillColor = SKColor(body.atmosphereColor).withAlphaComponent(0.22)
            }
        }
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
        guard signature != builtPartSignature else { return }
        builtPartSignature = signature

        vesselNode.removeAllChildren()
        partNodes.removeAll()
        exhaustNodes.removeAll()

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

            if def.isEngine, let texture = particleTexture {
                let emitter = FlightScene.makeExhaust(texture: texture, def: def)
                emitter.position = CGPoint(x: part.position.x,
                                           y: part.position.y - def.size.y / 2)
                emitter.particleBirthRate = 0
                vesselNode.addChild(emitter)
                exhaustNodes[part.id] = emitter
            }
        }
    }

    private func updateVessel(_ vessel: Vessel) {
        vesselNode.setScale(CGFloat(pointsPerMeter))
        vesselNode.position = .zero
        vesselNode.zRotation = CGFloat(vessel.heading - .pi / 2)
        vesselNode.alpha = vessel.situation == .destroyed ? 0.35 : 1

        // Keep propellant levels and open canopies in sync without rebuilding nodes.
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

    private func updateExhaust(_ vessel: Vessel) {
        let pressure = vessel.atmosphericPressure
        for part in vessel.liveParts {
            guard let def = part.definition, def.isEngine,
                  let emitter = exhaustNodes[part.id] else { continue }
            let runtime = vessel.runtime[part.id]
            let lit = (runtime?.ignited ?? false)
                && !(runtime?.flamedOut ?? false)
                && vessel.availableFuel(for: part) > 0
            let level = def.throttleable ? vessel.throttle : 1
            let intensity = lit ? level : 0
            emitter.particleBirthRate = CGFloat(420 * intensity)
            // A vacuum plume spreads; at sea level it stays tight.
            let spread = MathUtil.remap(pressure, 0, 101_325, 0.55, 0.12)
            emitter.emissionAngleRange = CGFloat(spread)
            emitter.particleSpeed = CGFloat(def.size.y * 9 * (0.6 + intensity))
            emitter.particleLifetime = CGFloat(0.22 + 0.25 * (1 - pressure / 101_325))
        }
    }

    private static func makeExhaust(texture: SKTexture, def: PartDefinition) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = texture
        e.particleBirthRate = 0
        e.particleLifetime = 0.3
        e.particleLifetimeRange = 0.12
        e.emissionAngle = -.pi / 2
        e.emissionAngleRange = 0.2
        e.particleSpeed = CGFloat(def.size.y * 10)
        e.particleSpeedRange = CGFloat(def.size.y * 3)
        e.particleAlpha = 0.85
        e.particleAlphaSpeed = -2.4
        e.particleScale = CGFloat(def.size.x * 0.5)
        e.particleScaleRange = CGFloat(def.size.x * 0.2)
        e.particleScaleSpeed = CGFloat(def.size.x * 0.6)
        e.particleColor = def.isSolidBooster
            ? SKColor(red: 1.0, green: 0.78, blue: 0.45, alpha: 1)
            : SKColor(red: 0.72, green: 0.85, blue: 1.0, alpha: 1)
        e.particleColorBlendFactor = 1
        e.particleBlendMode = .add
        e.zPosition = -1
        return e
    }
}
