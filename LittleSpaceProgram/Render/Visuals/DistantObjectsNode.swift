import SpriteKit
import SwiftUI

/// Distant Object Enhancement: bodies too small to render as discs still show up, as
/// bright flares sized by how much light they actually throw at you. Plus the sun,
/// which is what every other effect here is lit by.
///
/// Without this, everything beyond the current planet simply vanishes, and space reads
/// as empty rather than distant.
final class DistantObjectsNode: SKNode {

    private var flares: [String: SKSpriteNode] = [:]
    private let sunFlare = SKSpriteNode()
    private var built = false

    /// Set after each update: how much the sky should be dimmed because something
    /// bright is on screen. The scene uses it to fade the starfield.
    private(set) var skyDimming: Double = 0

    private func buildIfNeeded() {
        guard !built else { return }
        built = true
        sunFlare.texture = ProceduralTexture.flare
        sunFlare.blendMode = .add
        sunFlare.color = SKColor(red: 1.0, green: 0.95, blue: 0.82, alpha: 1)
        sunFlare.colorBlendFactor = 1
        sunFlare.zPosition = 1
        addChild(sunFlare)
    }

    private func flare(for id: String) -> SKSpriteNode {
        if let existing = flares[id] { return existing }
        let node = SKSpriteNode(texture: ProceduralTexture.flare)
        node.blendMode = .add
        node.colorBlendFactor = 1
        node.zPosition = 0
        addChild(node)
        flares[id] = node
        return node
    }

    /// - Parameters:
    ///   - pointsPerMeter: world scale
    ///   - viewSize: scene size in points
    func update(system: SolarSystem,
                vessel: Vessel,
                time: Double,
                pointsPerMeter: Double,
                viewSize: CGSize,
                settings: VisualSettings) {

        guard settings.distantObjects else {
            isHidden = true
            skyDimming = 0
            return
        }
        isHidden = false
        buildIfNeeded()

        var dimming = 0.0
        let diagonal = Double(max(viewSize.width, viewSize.height))

        // Other bodies.
        for body in system.bodies {
            let node = flare(for: body.id)
            guard body !== vessel.body else {
                node.isHidden = true
                continue
            }
            let relative = body.position(at: time, relativeTo: vessel.body) - vessel.position
            let distance = relative.length
            guard distance > 1 else { node.isHidden = true; continue }

            let point = CGPoint(x: relative.x * pointsPerMeter, y: relative.y * pointsPerMeter)
            // Keep drawing a little past the edge so flares do not pop at the border.
            let margin = diagonal * 0.35
            guard abs(Double(point.x)) < Double(viewSize.width) / 2 + margin,
                  abs(Double(point.y)) < Double(viewSize.height) / 2 + margin else {
                node.isHidden = true
                continue
            }

            // Apparent radius on screen. Once it is a few points across the scene draws
            // the real disc, so the flare bows out.
            let apparent = body.radius * pointsPerMeter
            guard apparent < 5 else { node.isHidden = true; continue }

            // Brightness falls off with distance, and a bigger body throws more light.
            let brightness = MathUtil.clamp(
                MathUtil.remap(log10(max(body.radius / distance, 1e-9)), -5.0, -2.0, 0, 1), 0, 1)
            let size = CGFloat(8 + 34 * brightness)

            node.isHidden = false
            node.position = point
            node.size = CGSize(width: size, height: size)
            node.alpha = CGFloat(0.35 + 0.65 * brightness)
            node.color = SKColor(body.surfaceColor)
            dimming = max(dimming, brightness * 0.35)
        }

        // The sun sits at infinity, so it is pinned just outside the shorter screen axis
        // in its own direction.
        let sunDirection = system.sunDirection
        let reach = diagonal * 0.46
        sunFlare.position = CGPoint(x: sunDirection.x * reach, y: sunDirection.y * reach)
        // Dimmer through thick air, blinding in vacuum.
        let air = vessel.body.atmosphere.map {
            1 - $0.spaceFraction(atAltitude: vessel.altitude)
        } ?? 0
        let strength = 1 - air * 0.75
        sunFlare.size = CGSize(width: CGFloat(diagonal * 0.30 * strength),
                               height: CGFloat(diagonal * 0.30 * strength))
        sunFlare.alpha = CGFloat(0.30 * strength)
        dimming = max(dimming, strength * 0.4)

        skyDimming = dimming
    }
}
