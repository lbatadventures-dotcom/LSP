import SwiftUI

/// The assembly building.
///
/// Parts are placed by tapping: pick one from the palette, and every legal attachment
/// point lights up as a dot. Dragging a small part onto a small target with a finger is
/// fiddly, so the game does the aiming and leaves the player the decision.
struct BuilderView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var vm: BuilderViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var panAnchor: Vec2? = nil
    @State private var zoomAnchor: Double? = nil
    @State private var showRename = false
    @State private var draftName = ""
    @State private var didFit = false

    init(design: VesselDesign) {
        _vm = StateObject(wrappedValue: BuilderViewModel(design: design))
    }

    private var isCompact: Bool { horizontalSizeClass == .compact }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.08, green: 0.10, blue: 0.14),
                                    Color(red: 0.04, green: 0.05, blue: 0.08)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            if isCompact {
                VStack(spacing: 0) {
                    topBar
                    canvasArea
                    palette
                        .frame(height: 148)
                }
            } else {
                VStack(spacing: 0) {
                    topBar
                    HStack(spacing: 0) {
                        palette
                            .frame(width: 280)
                        canvasArea
                    }
                }
            }
        }
        .alert("Rename rocket", isPresented: $showRename) {
            TextField("Name", text: $draftName)
            Button("Save") { vm.design.name = draftName }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                app.save(vm.design)
                app.screen = .menu
            } label: {
                Label("Base", systemImage: "chevron.left")
                    .font(Theme.label(14))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)

            Button {
                draftName = vm.design.name
                showRename = true
            } label: {
                HStack(spacing: 4) {
                    Text(vm.design.name).font(Theme.label(16).weight(.semibold))
                    Image(systemName: "pencil").font(.system(size: 11))
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            statsStrip

            Spacer(minLength: 8)

            HUDButton(systemImage: "arrow.uturn.backward", title: "Clear") { vm.clearAll() }
            HUDButton(systemImage: "square.and.arrow.down", title: "Save") {
                app.save(vm.design)
            }
            Button {
                app.save(vm.design)
                app.launch(vm.design)
            } label: {
                Label("Launch", systemImage: "paperplane.fill")
                    .font(Theme.label(14).weight(.bold))
                    .padding(.horizontal, 14)
                    .frame(height: Theme.minimumTouchTarget)
                    .background(Capsule().fill(vm.canLaunch ? Theme.success : Color.gray.opacity(0.4)))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .disabled(!vm.canLaunch)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.panelSolid)
    }

    private var statsStrip: some View {
        let a = vm.analysis
        return HStack(spacing: 14) {
            Readout(title: "Mass", value: Units.mass(a.totalMass), size: 14)
            Readout(title: "Total ΔV", value: String(format: "%.0f m/s", a.totalDeltaV),
                    tint: a.totalDeltaV >= 3_400 ? Theme.success : Theme.warning, size: 14)
            if let first = a.stages.first {
                Readout(title: "Liftoff TWR", value: String(format: "%.2f", first.liftoffTWR),
                        tint: first.liftoffTWR >= 1 ? Theme.success : Theme.danger, size: 14)
            }
            Readout(title: "Parts", value: "\(a.partCount)", size: 14)
            if !vm.design.warnings.isEmpty {
                Button {
                    vm.showWarnings = true
                } label: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warning)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $vm.showWarnings) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(vm.design.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.circle")
                                .font(Theme.label(13))
                        }
                    }
                    .padding()
                    .frame(maxWidth: 320)
                    .presentationCompactAdaptation(.popover)
                }
            }
        }
        .frame(maxWidth: isCompact ? 320 : 560)
    }

    // MARK: - Canvas

    private var canvasArea: some View {
        GeometryReader { geo in
            ZStack {
                Canvas { context, size in
                    draw(in: &context, size: size)
                }
                .contentShape(Rectangle())
                .gesture(tapGesture(in: geo.size))
                .simultaneousGesture(panGesture)
                .simultaneousGesture(zoomGesture)

                VStack {
                    Spacer()
                    if let id = vm.selectedPartID, let part = vm.design.part(id) {
                        selectionBar(part)
                    } else if vm.pendingDefinition != nil {
                        hintBar("Tap a highlighted point to attach")
                    }
                }
                .padding(.bottom, 12)

                VStack {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            HUDButton(systemImage: "plus.magnifyingglass") {
                                vm.zoom = min(120, vm.zoom * 1.35)
                            }
                            HUDButton(systemImage: "minus.magnifyingglass") {
                                vm.zoom = max(2, vm.zoom / 1.35)
                            }
                            HUDButton(systemImage: "scope") { vm.fit(in: geo.size) }
                            HUDButton(systemImage: symmetryIcon, title: "Sym",
                                      active: vm.symmetry) { vm.symmetry.toggle() }
                        }
                        .padding(.trailing, 12)
                    }
                    Spacer()
                }
                .padding(.top, 12)
            }
            .onAppear {
                if !didFit {
                    didFit = true
                    vm.fit(in: geo.size)
                }
            }
        }
    }

    private var symmetryIcon: String {
        vm.symmetry ? "rectangle.righthalf.inset.filled.arrow.right" : "rectangle"
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        func screen(_ p: Vec2) -> CGPoint {
            CGPoint(x: size.width / 2 + (p.x - vm.pan.x) * vm.zoom,
                    y: size.height / 2 - (p.y - vm.pan.y) * vm.zoom)
        }

        // Ground reference line, so "which way is up" is never in doubt.
        let b = vm.design.bounds
        let groundY = screen(Vec2(0, b.min.y)).y
        context.stroke(Path { p in
            p.move(to: CGPoint(x: 0, y: groundY))
            p.addLine(to: CGPoint(x: size.width, y: groundY))
        }, with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))

        for part in vm.design.parts.sorted(by: { $0.attachKind == .radial && $1.attachKind != .radial }) {
            guard let def = part.definition else { continue }
            drawPart(part, def, in: &context, screen: screen)
        }

        // Selection outline.
        if let id = vm.selectedPartID, let part = vm.design.part(id), let def = part.definition {
            let c = screen(part.position)
            let w = def.size.x * vm.zoom, h = def.size.y * vm.zoom
            context.stroke(Path(roundedRect: CGRect(x: c.x - w / 2 - 3, y: c.y - h / 2 - 3,
                                                    width: w + 6, height: h + 6),
                                cornerRadius: 5),
                           with: .color(Theme.accent), lineWidth: 2)
        }

        // Attachment dots and a ghost of what would be placed.
        if let def = vm.pendingDefinition {
            for target in vm.attachmentTargets {
                let c = screen(target.position)
                context.fill(Path(ellipseIn: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)),
                             with: .color(Theme.success.opacity(0.35)))
                context.stroke(Path(ellipseIn: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)),
                               with: .color(Theme.success), lineWidth: 1.5)
            }
            context.draw(Text(def.name).font(Theme.label(11)).foregroundStyle(Theme.success),
                         at: CGPoint(x: size.width / 2, y: 22))
        }
    }

    private func drawPart(_ part: PlacedPart, _ def: PartDefinition,
                          in context: inout GraphicsContext, screen: (Vec2) -> CGPoint) {
        let origin = screen(part.position)
        context.drawLayer { layer in
            layer.translateBy(x: origin.x, y: origin.y)
            // Design space has +y up; the canvas has +y down.
            layer.scaleBy(x: vm.zoom, y: -vm.zoom)
            if part.side < 0 { layer.scaleBy(x: -1, y: 1) }
            for pl in PartGeometry.layers(for: def) {
                let path = Path(pl.path)
                if let fill = pl.fill { layer.fill(path, with: .color(fill)) }
                if let stroke = pl.stroke {
                    layer.stroke(path, with: .color(stroke), lineWidth: pl.lineWidth)
                }
            }
        }
        // Stage badge on parts that do something when staged.
        if def.isEngine || def.isDecoupler || def.isParachute, vm.zoom > 6 {
            let badge = screen(Vec2(part.position.x + def.size.x / 2 + 0.35, part.position.y))
            context.draw(Text("\(part.stage + 1)")
                            .font(Theme.readout(10))
                            .foregroundStyle(Theme.warning),
                         at: badge)
        }
    }

    // MARK: - Gestures

    private func tapGesture(in size: CGSize) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let point = Vec2((value.location.x - size.width / 2) / vm.zoom + vm.pan.x,
                                 (size.height / 2 - value.location.y) / vm.zoom + vm.pan.y)
                if vm.pendingDefinition != nil {
                    // Snap to the nearest highlighted target within a finger's reach.
                    let reach = 26.0 / vm.zoom
                    let nearest = vm.attachmentTargets.min {
                        ($0.position - point).length < ($1.position - point).length
                    }
                    if let nearest, (nearest.position - point).length < max(reach, 0.8) {
                        vm.place(at: nearest)
                    } else {
                        vm.pendingDefinition = nil
                    }
                } else {
                    vm.selectedPartID = vm.part(at: point)?.id
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { g in
                if panAnchor == nil { panAnchor = vm.pan }
                guard let anchor = panAnchor else { return }
                vm.pan = Vec2(anchor.x - g.translation.width / vm.zoom,
                              anchor.y + g.translation.height / vm.zoom)
            }
            .onEnded { _ in panAnchor = nil }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if zoomAnchor == nil { zoomAnchor = vm.zoom }
                guard let anchor = zoomAnchor else { return }
                vm.zoom = MathUtil.clamp(anchor * max(value.magnification, 0.05), 2, 120)
            }
            .onEnded { _ in zoomAnchor = nil }
    }

    // MARK: - Contextual bars

    private func selectionBar(_ part: PlacedPart) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(part.definition?.name ?? "Part")
                    .font(Theme.label(13).weight(.semibold))
                Text(Units.mass(part.definition?.wetMass ?? 0))
                    .font(Theme.label(10))
                    .foregroundStyle(Theme.dim)
            }
            .frame(minWidth: 120, alignment: .leading)

            if let def = part.definition, def.isEngine || def.isDecoupler || def.isParachute {
                HStack(spacing: 4) {
                    Text("Stage \(part.stage + 1)")
                        .font(Theme.label(12))
                        .foregroundStyle(Theme.warning)
                    HUDButton(systemImage: "minus") { vm.moveSelectedStage(by: -1) }
                    HUDButton(systemImage: "plus") { vm.moveSelectedStage(by: 1) }
                }
            }

            HUDButton(systemImage: "trash", title: "Delete", tint: Theme.danger,
                      enabled: part.id != vm.design.rootID) {
                vm.deleteSelection()
            }
            HUDButton(systemImage: "xmark") { vm.selectedPartID = nil }
        }
        .padding(10)
        .panel()
        .padding(.horizontal, 12)
    }

    private func hintBar(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap.fill")
            Text(text).font(Theme.label(13))
            Button("Cancel") { vm.pendingDefinition = nil }
                .font(Theme.label(13))
                .foregroundStyle(Theme.accent)
        }
        .padding(10)
        .panel()
    }

    // MARK: - Palette

    private var palette: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PartCategory.allCases) { cat in
                        Button {
                            vm.category = cat
                        } label: {
                            Label(cat.title, systemImage: cat.symbol)
                                .font(Theme.label(12))
                                .padding(.horizontal, 10)
                                .frame(height: 34)
                                .background(Capsule().fill(vm.category == cat
                                                           ? Theme.accent : Color.white.opacity(0.08)))
                                .foregroundStyle(vm.category == cat ? .black : .white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
            }
            .padding(.vertical, 8)

            ScrollView(isCompact ? .horizontal : .vertical, showsIndicators: false) {
                let items = PartCatalog.parts(in: vm.category)
                if isCompact {
                    HStack(spacing: 8) {
                        ForEach(items) { paletteCell($0) }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                } else {
                    VStack(spacing: 8) {
                        ForEach(items) { paletteCell($0) }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
            }
        }
        .background(Theme.panelSolid)
    }

    private func paletteCell(_ def: PartDefinition) -> some View {
        Button {
            vm.pendingDefinition = vm.pendingDefinition?.id == def.id ? nil : def
            vm.selectedPartID = nil
        } label: {
            HStack(spacing: 8) {
                PartThumbnail(definition: def)
                    .frame(width: 34, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(def.name)
                        .font(Theme.label(12).weight(.medium))
                        .lineLimit(1)
                    Text(statLine(def))
                        .font(Theme.label(10))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .frame(width: isCompact ? 190 : nil, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(vm.pendingDefinition?.id == def.id
                      ? Theme.accent.opacity(0.25) : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(vm.pendingDefinition?.id == def.id ? Theme.accent : .clear,
                              lineWidth: 1.5))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func statLine(_ def: PartDefinition) -> String {
        if def.isEngine {
            return String(format: "%.0f kN · Isp %.0f/%.0f",
                          def.thrustVacuum / 1_000, def.ispSeaLevel, def.ispVacuum)
        }
        if def.fuelCapacity > 0 {
            return "\(Units.mass(def.fuelCapacity)) fuel · \(Units.mass(def.dryMass)) dry"
        }
        if def.isParachute { return "\(Units.mass(def.dryMass)) · canopy \(Int(def.parachuteDrag)) m²" }
        if def.liftAuthority > 0 { return "\(Units.mass(def.dryMass)) · authority \(def.liftAuthority)" }
        return Units.mass(def.dryMass)
    }
}

/// Small procedural preview of a part, used in the palette.
struct PartThumbnail: View {
    let definition: PartDefinition

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / max(definition.size.x, 0.1),
                            size.height / max(definition.size.y, 0.1)) * 0.82
            context.drawLayer { layer in
                layer.translateBy(x: size.width / 2, y: size.height / 2)
                layer.scaleBy(x: scale, y: -scale)
                for pl in PartGeometry.layers(for: definition) {
                    let path = Path(pl.path)
                    if let fill = pl.fill { layer.fill(path, with: .color(fill)) }
                    if let stroke = pl.stroke {
                        layer.stroke(path, with: .color(stroke), lineWidth: pl.lineWidth)
                    }
                }
            }
        }
    }
}
