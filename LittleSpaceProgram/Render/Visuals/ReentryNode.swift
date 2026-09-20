import SpriteKit

/// Reentry Particle Effect: the plasma sheath that stands off in front of a vessel
/// coming in hot, and the trail of embers it sheds behind.
///
/// Intensity follows a convective heating proxy, rho * v^3. That is why a steep entry
/// from a high orbit lights up and a gentle one barely glows: the cube on velocity
/// dominates everything else.
final class ReentryNode: SKNode {

    private let sheath = SKSpriteNode()
    private let halo = SKSpriteNode()
    private var wake: SKEmitterNode?
    private var built = false

    /// Heat flux at which the sheath first becomes visible, and where it saturates.
    private let onsetFlux: Double = 9.0e5
    private let peakFlux: Double = 2.2e7

    private func buildIfNeeded() {
        guard !built else { return }
        built = true

        sheath.texture = ProceduralTexture.sheath
        // Anchored at the base so it stands off ahead of the vessel.
        sheath.anchorPoint = CGPoint(x: 0.5, y: 0)
        sheath.blendMode = .add
        sheath.zPosition = 1
        addChild(sheath)

        halo.texture = ProceduralTexture.glow
        halo.blendMode = .add
        halo.zPosition = 0
        addChild(halo)

        let e = SKEmitterNode()
        e.particleTexture = ProceduralTexture.particle
        e.particleBirthRate = 0
        e.particleLifetime = 1.1
        e.particleLifetimeRange = 0.7
        e.emissionAngleRange = 0.30
        e.particleAlpha = 0.9
        e.particleAlphaSpeed = -0.85
        e.particleScaleSpeed = -0.12
        e.particleColorBlendFactor = 1
        e.particleBlendMode = .add
        e.zPosition = -1
        addChild(e)
        wake = e
    }

    /// - Parameters:
    ///   - density: ambient density, kg/m^3
    ///   - airspeed: speed relative to the air, m/s
    ///   - travelAngle: direction of travel through the air, world radians
    ///   - vesselSize: rough radius of the vessel in points, to scale the effect
    func update(density: Double,
                airspeed: Double,
                travelAngle: Double,
                vesselSizePoints: Double,
                settings: VisualSettings) {

        guard settings.reentryEffects, density > 1e-8, airspeed > 250 else {
            isHidden = true
            wake?.particleBirthRate = 0
            return
        }
        buildIfNeeded()

        let flux = density * airspeed * airspeed * airspeed
        let intensity = MathUtil.clamp(
            MathUtil.remap(flux, onsetFlux, peakFlux, 0, 1), 0, 1)
        guard intensity > 0.01 else {
            isHidden = true
            wake?.particleBirthRate = 0
            return
        }
        isHidden = false

        // The whole assembly points along the direction of travel.
        zRotation = CGFloat(travelAngle - .pi / 2)

        let scale = max(vesselSizePoints, 6.0)
        let stand = scale * (0.30 + 0.35 * intensity)

        // Orange at first contact, white as the flux climbs.
        let white = pow(intensity, 1.6)
        let tint = SKColor(red: 1.0,
                           green: CGFloat(MathUtil.lerp(0.55, 0.95, white)),
                           blue: CGFloat(MathUtil.lerp(0.22, 0.92, white)),
                           alpha: 1)

        sheath.isHidden = false
        sheath.position = CGPoint(x: 0, y: CGFloat(stand))
        sheath.size = CGSize(width: CGFloat(scale * (1.5 + 1.4 * intensity)),
                             height: CGFloat(scale * (1.7 + 2.3 * intensity)))
        sheath.color = tint
        sheath.colorBlendFactor = 1
        sheath.alpha = CGFloat(0.35 + 0.55 * intensity)

        halo.size = CGSize(width: CGFloat(scale * 4.5 * (0.5 + intensity)),
                           height: CGFloat(scale * 4.5 * (0.5 + intensity)))
        halo.color = tint
        halo.colorBlendFactor = 1
        halo.alpha = CGFloat(0.18 * intensity)

        // Embers stream backwards, which in this node's frame is straight down.
        wake?.particleBirthRate = CGFloat(420 * intensity * settings.particleScale)
        wake?.emissionAngle = -.pi / 2
        wake?.particleSpeed = CGFloat(scale * (5 + 12 * intensity))
        wake?.particleSpeedRange = CGFloat(scale * 4)
        wake?.particleScale = CGFloat(scale * 0.07)
        wake?.particleScaleRange = CGFloat(scale * 0.05)
        wake?.particleColor = SKColor(red: 1.0,
                                      green: CGFloat(MathUtil.lerp(0.45, 0.80, white)),
                                      blue: CGFloat(MathUtil.lerp(0.14, 0.45, white)),
                                      alpha: 1)
        wake?.particleLifetime = CGFloat(0.7 + 0.9 * intensity)
    }
}
