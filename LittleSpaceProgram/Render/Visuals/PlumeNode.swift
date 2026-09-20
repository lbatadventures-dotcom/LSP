import SpriteKit

/// Waterfall: an engine plume built from layers rather than particles alone.
///
/// A rocket exhaust is over-expanded at sea level — tight, with shock diamonds where the
/// flow keeps re-compressing — and under-expanded in vacuum, where it blooms out into a
/// wide bell. That pressure dependence is the whole character of the effect, so ambient
/// pressure drives the width, the length and whether diamonds appear at all.
final class PlumeNode: SKNode {

    private let core = SKSpriteNode()
    private let outerGlow = SKSpriteNode()
    private var diamonds: [SKSpriteNode] = []
    private var emitter: SKEmitterNode?
    private var built = false

    /// Nozzle diameter and the engine's character, set once when the node is made.
    private var nozzleWidth: Double = 1
    private var hot = false

    func configure(definition: PartDefinition) {
        nozzleWidth = definition.size.x
        hot = definition.isSolidBooster
        guard !built else { return }
        built = true

        let texture = ProceduralTexture.plume(hot: hot)
        // Anchored at the top edge so scaling grows the plume downward from the nozzle.
        core.texture = texture
        core.anchorPoint = CGPoint(x: 0.5, y: 1)
        core.blendMode = .add
        core.zPosition = 1
        addChild(core)

        outerGlow.texture = texture
        outerGlow.anchorPoint = CGPoint(x: 0.5, y: 1)
        outerGlow.blendMode = .add
        outerGlow.alpha = 0.32
        outerGlow.zPosition = 0
        addChild(outerGlow)

        for _ in 0..<4 {
            let d = SKSpriteNode(texture: ProceduralTexture.shockDiamond)
            d.blendMode = .add
            d.isHidden = true
            d.zPosition = 2
            addChild(d)
            diamonds.append(d)
        }

        let e = SKEmitterNode()
        e.particleTexture = ProceduralTexture.particle
        e.particleBirthRate = 0
        e.particleLifetime = 0.34
        e.particleLifetimeRange = 0.18
        e.emissionAngle = -.pi / 2
        e.emissionAngleRange = 0.25
        e.particleSpeed = CGFloat(nozzleWidth * 10)
        e.particleSpeedRange = CGFloat(nozzleWidth * 4)
        e.particleAlpha = 0.55
        e.particleAlphaSpeed = -1.8
        e.particleScale = CGFloat(nozzleWidth * 0.45)
        e.particleScaleRange = CGFloat(nozzleWidth * 0.2)
        e.particleScaleSpeed = CGFloat(nozzleWidth * 0.9)
        e.particleColor = hot
            ? SKColor(red: 1.0, green: 0.72, blue: 0.38, alpha: 1)
            : SKColor(red: 0.70, green: 0.84, blue: 1.0, alpha: 1)
        e.particleColorBlendFactor = 1
        e.particleBlendMode = .add
        e.zPosition = -1
        addChild(e)
        emitter = e
    }

    /// - Parameters:
    ///   - intensity: 0...1, the engine's current output
    ///   - pressure: ambient pressure in pascals
    func update(intensity: Double, pressure: Double, settings: VisualSettings) {
        guard built else { return }

        let lit = intensity > 0.01
        core.isHidden = !lit
        outerGlow.isHidden = !lit
        emitter?.particleBirthRate = CGFloat(lit ? 260 * intensity * settings.particleScale : 0)
        if !lit {
            for d in diamonds { d.isHidden = true }
            return
        }

        // 1 at sea level, 0 in vacuum.
        let ambient = MathUtil.clamp(pressure / 101_325, 0, 1)
        let vacuum = 1 - ambient

        guard settings.volumetricPlumes else {
            // Fall back to a plain tapered flame.
            layout(core, width: nozzleWidth * 0.9, length: nozzleWidth * 3.2 * intensity, alpha: 0.85)
            outerGlow.isHidden = true
            for d in diamonds { d.isHidden = true }
            return
        }

        // Under-expanded flow spreads as the air thins; over-expanded flow stays tight.
        let width = nozzleWidth * (0.80 + 1.85 * vacuum) * (0.55 + 0.45 * intensity)
        let length = nozzleWidth * (3.0 + 5.5 * vacuum) * (0.35 + 0.65 * intensity)

        layout(core, width: width * 0.62, length: length * 0.92, alpha: 0.95 * intensity)
        layout(outerGlow, width: width * 1.5, length: length * 1.18, alpha: 0.30 * intensity)

        // Shock diamonds only form in a dense atmosphere, and only under real thrust.
        let showDiamonds = ambient > 0.22 && intensity > 0.35
        let spacing = nozzleWidth * (0.85 + 0.5 * (1 - ambient))
        for (i, d) in diamonds.enumerated() {
            let y = -spacing * Double(i + 1)
            let visible = showDiamonds && abs(y) < length * 0.8
            d.isHidden = !visible
            guard visible else { continue }
            let fade = 1 - Double(i) / Double(diamonds.count)
            d.position = CGPoint(x: 0, y: y)
            d.size = CGSize(width: CGFloat(nozzleWidth * 0.52 * fade),
                            height: CGFloat(nozzleWidth * 0.30 * fade))
            d.alpha = CGFloat(0.85 * fade * ambient * intensity)
        }

        emitter?.emissionAngleRange = CGFloat(0.12 + 0.55 * vacuum)
        emitter?.particleSpeed = CGFloat(nozzleWidth * (8 + 10 * vacuum) * intensity)
    }

    private func layout(_ node: SKSpriteNode, width: Double, length: Double, alpha: Double) {
        node.isHidden = false
        node.size = CGSize(width: CGFloat(max(width, 0.01)), height: CGFloat(max(length, 0.01)))
        node.alpha = CGFloat(MathUtil.clamp(alpha, 0, 1))
    }
}
