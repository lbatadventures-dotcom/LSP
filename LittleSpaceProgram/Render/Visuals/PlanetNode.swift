import SpriteKit

/// A body seen from space, with EVE's cloud sheet, a day/night terminator and
/// Scatterer's lit limb.
///
/// Four stacked sprites rather than a shader: the textures are generated once and the
/// per-frame cost is four transform updates.
final class PlanetNode: SKNode {

    private let surface = SKSpriteNode()
    private let clouds = SKSpriteNode()
    private let night = SKSpriteNode()
    private let limb = SKSpriteNode()

    private var configuredKey: String?

    // No initialisers declared, so SKNode's are inherited.

    private func buildIfNeeded() {
        guard surface.parent == nil else { return }
        surface.zPosition = 0
        clouds.zPosition = 1
        night.zPosition = 2
        limb.zPosition = 3
        limb.blendMode = .add
        addChild(surface)
        addChild(clouds)
        addChild(night)
        addChild(limb)
    }

    /// - Parameters:
    ///   - radiusPoints: the body's radius on screen
    ///   - atmosphereFraction: atmosphere height as a fraction of the body's radius
    ///   - cloudPhase: slow rotation of the cloud sheet, radians
    func update(body: CelestialBody,
                radiusPoints: Double,
                bodyRotation: Double,
                sunDirection: Vec2,
                cloudPhase: Double,
                settings: VisualSettings) {
        buildIfNeeded()

        let key = "\(body.id)-\(settings.textureResolution)"
        if configuredKey != key {
            configuredKey = key
            surface.texture = ProceduralTexture.surface(for: body, size: settings.textureResolution)
            clouds.texture = ProceduralTexture.clouds(for: body, size: settings.textureResolution)
            limb.texture = ProceduralTexture.limb(
                inner: body.radius / (body.radius + (body.atmosphere?.height ?? body.radius * 0.02))
            )
            limb.color = Scattering.limbGlow(for: body) ?? .clear
            limb.colorBlendFactor = 1
            // Air spreads the terminator out; an airless world cuts sharply.
            night.texture = ProceduralTexture.terminator(softness: body.hasAtmosphere ? 1.0 : 0.18)
        }

        let diameter = CGFloat(radiusPoints * 2)
        surface.size = CGSize(width: diameter, height: diameter)
        surface.zRotation = CGFloat(bodyRotation)

        let showClouds = settings.cloudsAndScattering && body.hasAtmosphere
        clouds.isHidden = !showClouds
        if showClouds {
            // The sheet sits just above the ground and drifts relative to it.
            clouds.size = CGSize(width: diameter * 1.012, height: diameter * 1.012)
            clouds.zRotation = CGFloat(bodyRotation + cloudPhase)
            clouds.alpha = 0.82
        }

        night.size = CGSize(width: diameter * 1.004, height: diameter * 1.004)
        // The texture's +x edge is the night pole, so point it away from the sun.
        night.zRotation = CGFloat(sunDirection.angle + .pi)
        night.isHidden = !settings.cloudsAndScattering

        let hasAir = body.hasAtmosphere && settings.cloudsAndScattering
        limb.isHidden = !hasAir
        if hasAir, let atmo = body.atmosphere {
            let outer = CGFloat((body.radius + atmo.height) / body.radius * radiusPoints * 2)
            limb.size = CGSize(width: outer, height: outer)
            // Brightest on the sunward side.
            limb.zRotation = CGFloat(sunDirection.angle)
            limb.alpha = 0.95
        }
    }
}
