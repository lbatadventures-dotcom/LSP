import CoreGraphics
import SwiftUI

/// One drawable layer of a part, in part-local metres with +y toward the nose.
struct PartLayer {
    var path: CGPath
    var fill: Color?
    var stroke: Color?
    /// Stroke width in metres.
    var lineWidth: Double = 0.03
    /// Marks a layer the renderer animates, such as the propellant level.
    var role: String?
}

/// Every part is drawn from code — no bitmaps ship with the app, so the whole thing
/// stays a few megabytes and renders crisply at any zoom on a Retina display.
enum PartGeometry {

    static func layers(for def: PartDefinition,
                       fuelFraction: Double = 1,
                       chuteOpen: Double = 0,
                       legsDeployed: Bool = true) -> [PartLayer] {
        switch def.style {
        case .tank: return tank(def, fuel: fuelFraction)
        case .pod: return pod(def)
        case .engine: return engine(def)
        case .solidBooster: return solidBooster(def, fuel: fuelFraction)
        case .decoupler: return decoupler(def)
        case .noseCone: return noseCone(def)
        case .fin: return fin(def)
        case .parachute: return parachute(def, open: chuteOpen)
        case .landingLegs: return legs(def, deployed: legsDeployed)
        case .adapter: return adapter(def)
        }
    }

    // MARK: - Helpers

    private static func roundedBox(_ size: Vec2, radius: Double) -> CGPath {
        let rect = CGRect(x: -size.x / 2, y: -size.y / 2, width: size.x, height: size.y)
        let r = min(radius, min(size.x, size.y) / 2)
        return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    }

    private static func polygon(_ points: [Vec2]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first.cgPoint)
        for p in points.dropFirst() { path.addLine(to: p.cgPoint) }
        path.closeSubpath()
        return path
    }

    private static func line(_ a: Vec2, _ b: Vec2) -> CGPath {
        let path = CGMutablePath()
        path.move(to: a.cgPoint)
        path.addLine(to: b.cgPoint)
        return path
    }

    // MARK: - Shapes

    private static func tank(_ def: PartDefinition, fuel: Double) -> [PartLayer] {
        let s = def.size
        var out: [PartLayer] = [
            PartLayer(path: roundedBox(s, radius: s.x * 0.12), fill: def.tint,
                      stroke: Color.black.opacity(0.45), lineWidth: 0.035)
        ]
        // Propellant level, drawn from the bottom up. Always emitted so the flight
        // renderer can animate it by scaling rather than rebuilding the node.
        let h = s.y * 0.92 * MathUtil.clamp(fuel, 0, 1)
        if h > 0 {
            let rect = CGRect(x: -s.x * 0.34, y: -s.y * 0.46, width: s.x * 0.68, height: h)
            out.append(PartLayer(path: CGPath(roundedRect: rect, cornerWidth: s.x * 0.06,
                                              cornerHeight: s.x * 0.06, transform: nil),
                                 fill: Color(red: 0.36, green: 0.62, blue: 0.88).opacity(0.55),
                                 stroke: nil, role: "fuel"))
        }
        // Structural bands.
        let bands = max(1, Int(s.y / 1.2))
        for i in 1...bands {
            let y = -s.y / 2 + s.y * Double(i) / Double(bands + 1)
            out.append(PartLayer(path: line(Vec2(-s.x / 2, y), Vec2(s.x / 2, y)),
                                 fill: nil, stroke: Color.black.opacity(0.22), lineWidth: 0.04))
        }
        // Highlight down the left edge for a hint of cylinder.
        out.append(PartLayer(path: line(Vec2(-s.x * 0.32, -s.y * 0.44), Vec2(-s.x * 0.32, s.y * 0.44)),
                             fill: nil, stroke: Color.white.opacity(0.35), lineWidth: s.x * 0.10))
        return out
    }

    private static func pod(_ def: PartDefinition) -> [PartLayer] {
        let s = def.size
        let body = polygon([
            Vec2(-s.x / 2, -s.y / 2), Vec2(s.x / 2, -s.y / 2),
            Vec2(s.x * 0.30, s.y / 2), Vec2(-s.x * 0.30, s.y / 2)
        ])
        var out: [PartLayer] = [
            PartLayer(path: body, fill: def.tint, stroke: Color.black.opacity(0.5), lineWidth: 0.035)
        ]
        // Window.
        let r = s.x * 0.13
        let window = CGPath(ellipseIn: CGRect(x: -r, y: s.y * 0.06, width: r * 2, height: r * 2),
                            transform: nil)
        out.append(PartLayer(path: window, fill: Color(red: 0.24, green: 0.44, blue: 0.62),
                             stroke: Color.black.opacity(0.5), lineWidth: 0.03))
        // Heat shield along the base.
        let shield = CGRect(x: -s.x / 2, y: -s.y / 2, width: s.x, height: s.y * 0.16)
        out.append(PartLayer(path: CGPath(rect: shield, transform: nil),
                             fill: Color(red: 0.30, green: 0.26, blue: 0.24), stroke: nil))
        return out
    }

    private static func engine(_ def: PartDefinition) -> [PartLayer] {
        let s = def.size
        let topH = s.y * 0.35
        let mount = CGRect(x: -s.x * 0.34, y: s.y / 2 - topH, width: s.x * 0.68, height: topH)
        let bell = polygon([
            Vec2(-s.x * 0.28, s.y / 2 - topH), Vec2(s.x * 0.28, s.y / 2 - topH),
            Vec2(s.x * 0.5, -s.y / 2), Vec2(-s.x * 0.5, -s.y / 2)
        ])
        return [
            PartLayer(path: CGPath(rect: mount, transform: nil), fill: def.tint,
                      stroke: Color.black.opacity(0.5), lineWidth: 0.03),
            PartLayer(path: bell, fill: Color(red: 0.24, green: 0.22, blue: 0.21),
                      stroke: Color.black.opacity(0.55), lineWidth: 0.035),
            PartLayer(path: line(Vec2(-s.x * 0.38, -s.y * 0.38), Vec2(s.x * 0.38, -s.y * 0.38)),
                      fill: nil, stroke: Color.white.opacity(0.18), lineWidth: 0.05)
        ]
    }

    private static func solidBooster(_ def: PartDefinition, fuel: Double) -> [PartLayer] {
        let s = def.size
        let bodyH = s.y * 0.82
        let body = CGPath(roundedRect: CGRect(x: -s.x / 2, y: -s.y / 2, width: s.x, height: bodyH),
                          cornerWidth: s.x * 0.1, cornerHeight: s.x * 0.1, transform: nil)
        let cone = polygon([
            Vec2(-s.x / 2, -s.y / 2 + bodyH), Vec2(s.x / 2, -s.y / 2 + bodyH), Vec2(0, s.y / 2)
        ])
        var out: [PartLayer] = [
            PartLayer(path: body, fill: def.tint, stroke: Color.black.opacity(0.45), lineWidth: 0.035),
            PartLayer(path: cone, fill: def.tint.opacity(0.9),
                      stroke: Color.black.opacity(0.45), lineWidth: 0.035)
        ]
        let grain = bodyH * 0.9 * MathUtil.clamp(fuel, 0, 1)
        if grain > 0 {
            let rect = CGRect(x: -s.x * 0.3, y: -s.y * 0.47, width: s.x * 0.6, height: grain)
            out.append(PartLayer(path: CGPath(rect: rect, transform: nil),
                                 fill: Color(red: 0.42, green: 0.32, blue: 0.24).opacity(0.7),
                                 stroke: nil, role: "fuel"))
        }
        out.append(PartLayer(path: line(Vec2(-s.x / 2, -s.y / 2 + bodyH * 0.5),
                                        Vec2(s.x / 2, -s.y / 2 + bodyH * 0.5)),
                             fill: nil, stroke: Color.black.opacity(0.2), lineWidth: 0.05))
        return out
    }

    private static func decoupler(_ def: PartDefinition) -> [PartLayer] {
        let s = def.size
        return [
            PartLayer(path: roundedBox(s, radius: s.y * 0.2), fill: def.tint,
                      stroke: Color.black.opacity(0.5), lineWidth: 0.03),
            PartLayer(path: line(Vec2(-s.x / 2, 0), Vec2(s.x / 2, 0)),
                      fill: nil, stroke: Color.black.opacity(0.4), lineWidth: 0.05)
        ]
    }

    private static func noseCone(_ def: PartDefinition) -> [PartLayer] {
        let s = def.size
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -s.x / 2, y: -s.y / 2))
        path.addQuadCurve(to: CGPoint(x: 0, y: s.y / 2),
                          control: CGPoint(x: -s.x / 2, y: s.y * 0.18))
        path.addQuadCurve(to: CGPoint(x: s.x / 2, y: -s.y / 2),
                          control: CGPoint(x: s.x / 2, y: s.y * 0.18))
        path.closeSubpath()
        return [PartLayer(path: path, fill: def.tint, stroke: Color.black.opacity(0.45), lineWidth: 0.03)]
    }

    private static func fin(_ def: PartDefinition) -> [PartLayer] {
        let s = def.size
        // Drawn on the +x flank; the renderer mirrors it for the other side.
        let path = polygon([
            Vec2(-s.x / 2, s.y / 2), Vec2(s.x / 2, -s.y * 0.30), Vec2(s.x / 2, -s.y / 2),
            Vec2(-s.x / 2, -s.y / 2)
        ])
        return [PartLayer(path: path, fill: def.tint, stroke: Color.black.opacity(0.5), lineWidth: 0.03)]
    }

    private static func parachute(_ def: PartDefinition, open: Double) -> [PartLayer] {
        let s = def.size
        var out: [PartLayer] = [
            PartLayer(path: roundedBox(s, radius: s.x * 0.15), fill: def.tint,
                      stroke: Color.black.opacity(0.45), lineWidth: 0.03)
        ]
        guard open > 0.01 else { return out }
        // Canopy blooms above the pack as it opens.
        let span = s.x * (1.5 + 6.0 * open)
        let rise = s.y + span * 0.55
        let canopy = CGMutablePath()
        canopy.move(to: CGPoint(x: -span / 2, y: rise * 0.45))
        canopy.addQuadCurve(to: CGPoint(x: span / 2, y: rise * 0.45),
                            control: CGPoint(x: 0, y: rise * 1.35))
        canopy.closeSubpath()
        out.append(PartLayer(path: canopy, fill: Color(red: 0.92, green: 0.45, blue: 0.28).opacity(0.92),
                             stroke: Color.black.opacity(0.35), lineWidth: 0.04))
        for x in [-span * 0.42, 0, span * 0.42] {
            out.append(PartLayer(path: line(Vec2(x, rise * 0.45), Vec2(0, s.y / 2)),
                                 fill: nil, stroke: Color.white.opacity(0.7), lineWidth: 0.035))
        }
        return out
    }

    private static func legs(_ def: PartDefinition, deployed: Bool) -> [PartLayer] {
        let s = def.size
        let spread = deployed ? s.x : s.x * 0.3
        return [
            PartLayer(path: line(Vec2(-s.x * 0.1, s.y / 2), Vec2(spread * 0.5, -s.y / 2)),
                      fill: nil, stroke: def.tint, lineWidth: 0.12),
            PartLayer(path: line(Vec2(spread * 0.2, -s.y / 2), Vec2(spread * 0.75, -s.y / 2)),
                      fill: nil, stroke: def.tint, lineWidth: 0.16)
        ]
    }

    private static func adapter(_ def: PartDefinition) -> [PartLayer] {
        let s = def.size
        let topWidth = def.id.contains("250-125") ? s.x * 0.5 : s.x
        let path = polygon([
            Vec2(-s.x / 2, -s.y / 2), Vec2(s.x / 2, -s.y / 2),
            Vec2(topWidth / 2, s.y / 2), Vec2(-topWidth / 2, s.y / 2)
        ])
        return [PartLayer(path: path, fill: def.tint, stroke: Color.black.opacity(0.45), lineWidth: 0.03)]
    }
}
