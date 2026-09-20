import SwiftUI

/// Orbital map: patched conics, spheres of influence and the planned burn.
///
/// Drawn with `Canvas` rather than SpriteKit — it is all lines and circles, and the
/// gesture handling for pinch-zoom and dragging a manoeuvre handle is far simpler in
/// SwiftUI.
struct MapView: View {
    @ObservedObject var model: FlightModel
    let system: SolarSystem

    @State private var metersPerPoint: Double = 4_000
    @State private var center: Vec2 = .zero
    @State private var dragAnchor: Vec2? = nil
    @State private var zoomAnchor: Double? = nil
    @State private var focusID: String? = nil
    @State private var didAutoFit = false

    private var focus: CelestialBody {
        if let focusID { return system.body(id: focusID) }
        return model.simulator.vessel.body
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.02, green: 0.025, blue: 0.05)
                canvas()
                controls
            }
            .contentShape(Rectangle())
            .gesture(panGesture)
            .simultaneousGesture(zoomGesture)
            .onAppear {
                if !didAutoFit {
                    didAutoFit = true
                    autoFit(in: geo.size)
                }
            }
            .onChange(of: model.simulator.vessel.body.id) { _, _ in
                focusID = nil
                autoFit(in: geo.size)
            }
        }
    }

    // MARK: - Drawing

    private func canvas() -> some View {
        Canvas { context, canvasSize in
            let origin = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let scale = 1 / metersPerPoint

            func screen(_ world: Vec2) -> CGPoint {
                CGPoint(x: origin.x + (world.x - center.x) * scale,
                        y: origin.y - (world.y - center.y) * scale)
            }

            let body = focus
            let t = model.simulator.vessel.universeTime

            // Focus body and its atmosphere.
            drawBody(body, at: .zero, in: &context, screen: screen, scale: scale)

            // Moons, their orbits and their spheres of influence.
            for moon in system.childBodies(of: body) {
                let p = moon.positionRelativeToParent(at: t)
                let orbitRadius = moon.orbitRadius * scale
                if orbitRadius > 6 {
                    context.stroke(circlePath(center: screen(.zero), radius: orbitRadius),
                                   with: .color(.white.opacity(0.14)), lineWidth: 1)
                }
                drawBody(moon, at: p, in: &context, screen: screen, scale: scale)
                let soi = moon.soiRadius * scale
                if soi > 10 && soi < 4_000 {
                    context.stroke(circlePath(center: screen(p), radius: soi),
                                   with: .color(Theme.accent.opacity(0.3)),
                                   style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                }
            }

            // If the vessel is in a moon's SOI but we are looking at the parent, show
            // the parent body too.
            if let parent = body.parent {
                let p = -body.positionRelativeToParent(at: t)
                drawBody(parent, at: p, in: &context, screen: screen, scale: scale)
            }

            // Trajectory patches, brighter for the one the vessel is on now.
            for (index, patch) in model.patches.enumerated() {
                let points = patch.points(in: body, count: 160)
                guard points.count > 1 else { continue }
                var path = Path()
                path.move(to: screen(points[0]))
                for p in points.dropFirst() { path.addLine(to: screen(p)) }

                let isPlanned = model.maneuver != nil && index == model.patches.count - 1
                    && model.patches.count > 1
                let color: Color = isPlanned ? Theme.warning : (index == 0 ? Theme.accent : Theme.accent.opacity(0.55))
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: isPlanned ? 1.8 : 2,
                                                  dash: isPlanned ? [6, 4] : []))

                if !isPlanned {
                    drawApsides(patch, in: &context, screen: screen, frame: body)
                    drawPatchEnd(patch, in: &context, screen: screen, frame: body)
                }
            }

            // The vessel.
            let vessel = model.simulator.vessel
            let vesselWorld = vessel.body === body
                ? vessel.position
                : vessel.position + vessel.body.position(at: t, relativeTo: body)
            drawVesselMarker(at: screen(vesselWorld), heading: vessel.heading, in: &context)

            // The manoeuvre node.
            if let node = model.maneuver, let first = model.patches.first {
                let p = first.position(at: min(node.time, first.endTime), in: body)
                let s = screen(p)
                context.stroke(circlePath(center: s, radius: 9),
                               with: .color(Theme.warning), lineWidth: 2)
                context.fill(circlePath(center: s, radius: 3), with: .color(Theme.warning))
            }
        }
    }

    private func circlePath(center: CGPoint, radius: Double) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                               width: radius * 2, height: radius * 2))
    }

    private func drawBody(_ body: CelestialBody, at position: Vec2,
                          in context: inout GraphicsContext,
                          screen: (Vec2) -> CGPoint, scale: Double) {
        let s = screen(position)
        let r = max(body.radius * scale, 2.5)
        if let atmo = body.atmosphere {
            let outer = (body.radius + atmo.height) * scale
            if outer > r + 1 {
                context.fill(circlePath(center: s, radius: outer),
                             with: .color(body.atmosphereColor.opacity(0.18)))
            }
        }
        context.fill(circlePath(center: s, radius: r), with: .color(body.surfaceColor))
        context.stroke(circlePath(center: s, radius: r),
                       with: .color(body.deepColor), lineWidth: 1)
        if r > 14 {
            context.draw(Text(body.name).font(Theme.label(10)).foregroundStyle(.white.opacity(0.7)),
                         at: CGPoint(x: s.x, y: s.y + r + 10))
        }
    }

    private func drawApsides(_ patch: TrajectoryPatch, in context: inout GraphicsContext,
                             screen: (Vec2) -> CGPoint, frame: CelestialBody) {
        let o = patch.orbit
        let now = model.simulator.vessel.universeTime
        let offset = patch.body === frame ? Vec2.zero : patch.body.position(at: patch.startTime, relativeTo: frame)

        if let ap = o.apoapsis, let t = o.timeOfApoapsis(after: now), t <= patch.endTime {
            let p = o.position(atTrueAnomaly: .pi) + offset
            label("Ap \(Units.distance(ap - patch.body.radius))", at: screen(p),
                  color: Theme.accent, in: &context)
        }
        if let t = o.timeOfPeriapsis(after: now), t <= patch.endTime {
            let p = o.position(atTrueAnomaly: 0) + offset
            let pe = o.periapsis - patch.body.radius
            label("Pe \(Units.distance(pe))", at: screen(p),
                  color: pe < 0 ? Theme.danger : Theme.accent, in: &context)
        }
    }

    private func drawPatchEnd(_ patch: TrajectoryPatch, in context: inout GraphicsContext,
                              screen: (Vec2) -> CGPoint, frame: CelestialBody) {
        switch patch.end {
        case .closedOrbit, .horizon:
            return
        case .impact, .atmosphericEntry, .escape, .encounter:
            let p = patch.position(at: patch.endTime, in: frame)
            let color: Color = {
                switch patch.end {
                case .impact: return Theme.danger
                case .atmosphericEntry: return Theme.warning
                default: return Theme.success
                }
            }()
            label(patch.end.label, at: screen(p), color: color, in: &context)
        }
    }

    private func label(_ text: String, at point: CGPoint, color: Color,
                       in context: inout GraphicsContext) {
        context.fill(circlePath(center: point, radius: 3.5), with: .color(color))
        context.draw(Text(text).font(Theme.label(10)).foregroundStyle(color),
                     at: CGPoint(x: point.x, y: point.y - 12))
    }

    private func drawVesselMarker(at point: CGPoint, heading: Double,
                                  in context: inout GraphicsContext) {
        var path = Path()
        let r = 7.0
        for i in 0..<3 {
            let a = heading + Double(i) * 2 * .pi / 3
            let p = CGPoint(x: point.x + cos(a) * r, y: point.y - sin(a) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        context.fill(path, with: .color(.white))
        context.stroke(path, with: .color(.black.opacity(0.6)), lineWidth: 1)
    }

    // MARK: - Camera

    private func autoFit(in size: CGSize) {
        let vessel = model.simulator.vessel
        let body = focus
        let span = max(vessel.orbit.apoapsis ?? vessel.position.length,
                       body.radius * 2.6)
        let shorter = Double(min(size.width, size.height))
        metersPerPoint = max(span * 2.4 / max(shorter, 1), 1)
        center = .zero
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { g in
                if dragAnchor == nil { dragAnchor = center }
                guard let anchor = dragAnchor else { return }
                center = Vec2(anchor.x - g.translation.width * metersPerPoint,
                              anchor.y + g.translation.height * metersPerPoint)
            }
            .onEnded { _ in dragAnchor = nil }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if zoomAnchor == nil { zoomAnchor = metersPerPoint }
                guard let anchor = zoomAnchor else { return }
                metersPerPoint = MathUtil.clamp(anchor / max(value.magnification, 0.01),
                                                0.5, 4_000_000)
            }
            .onEnded { _ in zoomAnchor = nil }
    }

    // MARK: - Overlaid controls

    private var controls: some View {
        VStack {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    HUDButton(systemImage: "plus.magnifyingglass") {
                        metersPerPoint = max(0.5, metersPerPoint / 1.6)
                    }
                    HUDButton(systemImage: "minus.magnifyingglass") {
                        metersPerPoint = min(4_000_000, metersPerPoint * 1.6)
                    }
                    HUDButton(systemImage: "scope") {
                        center = .zero
                    }
                    if focus.parent != nil {
                        HUDButton(systemImage: "arrow.up.left.and.arrow.down.right",
                                  title: "Out") {
                            focusID = focus.parent?.id
                            center = .zero
                            metersPerPoint = max(metersPerPoint, 40_000)
                        }
                    } else if focusID != nil {
                        HUDButton(systemImage: "arrow.down.right.and.arrow.up.left",
                                  title: "Ship") {
                            focusID = nil
                            center = .zero
                        }
                    }
                }
                .padding(.trailing, 10)
            }
            Spacer()
        }
        .padding(.top, 10)
    }
}
