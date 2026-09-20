import SpriteKit

/// EVE's cloud layer as seen from inside it: a band of puffs sitting at a fixed altitude
/// that you climb up through on the way out and drop back through on the way home.
///
/// Puffs live at fixed longitudes around the body, so they stay put as the rocket flies
/// past and rotate with the planet. Only the ones on screen are drawn, from a reused
/// pool — allocating sprites per frame would stutter during ascent, which is exactly
/// when they are on screen.
final class CloudBandNode: SKNode {

    private var pool: [SKSpriteNode] = []

    /// Metres between puff anchors along the surface.
    private let spacingMeters: Double = 1_600
    /// Nominal width of one puff, in metres.
    private let puffWidth: Double = 2_600

    private func puff(_ index: Int) -> SKSpriteNode {
        while pool.count <= index {
            let node = SKSpriteNode(texture: ProceduralTexture.cloudPuff(
                seed: UInt64(pool.count % 4) &+ 31, size: 96))
            node.blendMode = .alpha
            node.isHidden = true
            addChild(node)
            pool.append(node)
        }
        return pool[index]
    }

    /// Deterministic jitter in [0, 1) for a given anchor.
    private func jitter(_ anchor: Int, _ salt: Int) -> Double {
        var h = UInt64(truncatingIfNeeded: anchor &* 73856093 &+ salt &* 19349663)
        h ^= h >> 27
        h = h &* 0x94D049BB133111EB
        h ^= h >> 31
        return Double(h >> 11) / Double(1 << 53)
    }

    /// - Parameters:
    ///   - vesselPosition: body-centred, metres
    ///   - pointsPerMeter: the world scale
    ///   - viewSize: the scene's size in points
    func update(body: CelestialBody,
                vesselPosition: Vec2,
                pointsPerMeter: Double,
                viewSize: CGSize,
                bodyRotation: Double,
                sunElevation: Double,
                settings: VisualSettings) {

        guard settings.cloudsAndScattering,
              let atmo = body.atmosphere,
              pointsPerMeter > 0 else {
            hideAll()
            return
        }

        let baseAltitude = atmo.height * 0.045      // ~3.1 km on Terra
        let halfWidthMeters = Double(viewSize.width) / 2 / pointsPerMeter
        let halfHeightMeters = Double(viewSize.height) / 2 / pointsPerMeter

        // Only worth drawing when the layer is near enough to resolve and we are not
        // so far out that the whole planet is on screen.
        let altitude = vesselPosition.length - body.radius
        guard abs(altitude - baseAltitude) < halfHeightMeters + atmo.height * 0.5,
              halfWidthMeters < body.radius * 0.35 else {
            hideAll()
            return
        }

        let centreAngle = vesselPosition.angle
        let spacingAngle = spacingMeters / body.radius
        // Anchors are fixed in the body's rotating frame.
        let rotated = centreAngle - bodyRotation
        let span = (halfWidthMeters * 1.35) / body.radius
        let firstIndex = Int(((rotated - span) / spacingAngle).rounded(.down))
        let lastIndex = Int(((rotated + span) / spacingAngle).rounded(.up))

        // Lit from the side at sunrise and sunset, flat grey at night.
        let day = MathUtil.clamp(MathUtil.remap(sunElevation, -0.2, 0.2, 0, 1), 0, 1)
        let tint = SKColor(red: CGFloat(MathUtil.lerp(0.34, 1.0, day)),
                           green: CGFloat(MathUtil.lerp(0.36, 0.99, day)),
                           blue: CGFloat(MathUtil.lerp(0.46, 1.0, day)),
                           alpha: 1)

        var used = 0
        let budget = settings.cloudBandDensity * 3
        var index = firstIndex
        while index <= lastIndex && used < budget {
            defer { index += 1 }
            // Thin the layer out so it is patchy rather than a solid wall.
            if jitter(index, 5) > 0.72 { continue }

            let angle = Double(index) * spacingAngle + bodyRotation
            let puffAltitude = baseAltitude
                + (jitter(index, 1) - 0.5) * atmo.height * 0.030
            let radius = body.radius + puffAltitude
            let world = Vec2.polar(angle: angle, length: radius)
            let offset = world - vesselPosition

            let scenePoint = CGPoint(x: offset.x * pointsPerMeter, y: offset.y * pointsPerMeter)
            // Cull generously — a puff is wide.
            let margin = CGFloat(puffWidth * pointsPerMeter)
            if abs(scenePoint.x) > viewSize.width / 2 + margin
                || abs(scenePoint.y) > viewSize.height / 2 + margin { continue }

            let node = puff(used)
            used += 1
            let width = puffWidth * (0.6 + jitter(index, 2) * 0.9)
            node.isHidden = false
            node.position = scenePoint
            node.size = CGSize(width: CGFloat(width * pointsPerMeter),
                               height: CGFloat(width * 0.42 * pointsPerMeter))
            node.zRotation = CGFloat(angle - .pi / 2)
            node.alpha = CGFloat(0.45 + jitter(index, 3) * 0.45)
            node.color = tint
            node.colorBlendFactor = 0.85
        }

        for i in used..<pool.count { pool[i].isHidden = true }
    }

    private func hideAll() {
        for node in pool { node.isHidden = true }
    }
}
