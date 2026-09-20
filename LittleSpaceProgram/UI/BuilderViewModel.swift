import SwiftUI

/// A place a selected part could be attached, shown as a tappable dot in the builder.
struct AttachmentTarget: Identifiable, Equatable {
    let id = UUID()
    let hostID: UUID
    let kind: AttachKind
    /// Centre the new part would occupy, in design space.
    let position: Vec2
    let side: Int

    static func == (a: AttachmentTarget, b: AttachmentTarget) -> Bool { a.id == b.id }
}

/// Editing state for the assembly building.
final class BuilderViewModel: ObservableObject {
    @Published var design: VesselDesign
    @Published var category: PartCategory = .command
    @Published var pendingDefinition: PartDefinition? = nil
    @Published var selectedPartID: UUID? = nil
    @Published var symmetry: Bool = true
    @Published var zoom: Double = 14
    @Published var pan: Vec2 = .zero
    @Published var showWarnings = false

    init(design: VesselDesign) {
        self.design = design
        var d = design
        d.normalizeStages()
        self.design = d
        recentre()
    }

    var analysis: DesignAnalysis { DesignAnalysis(design: design) }

    // MARK: - Camera

    func recentre() {
        let b = design.bounds
        pan = Vec2((b.min.x + b.max.x) / 2, (b.min.y + b.max.y) / 2)
    }

    func fit(in size: CGSize) {
        guard !design.isEmpty else { return }
        let b = design.bounds
        let w = max(b.max.x - b.min.x, 2)
        let h = max(b.max.y - b.min.y, 2)
        let fitZoom = min(Double(size.width) * 0.55 / w, Double(size.height) * 0.78 / h)
        zoom = MathUtil.clamp(fitZoom, 2, 120)
        recentre()
    }

    // MARK: - Attachment

    private func hasChild(_ host: UUID, kind: AttachKind) -> Bool {
        design.children(of: host).contains { $0.attachKind == kind }
    }

    /// Every legal spot for the part currently picked out of the palette.
    var attachmentTargets: [AttachmentTarget] {
        guard let def = pendingDefinition else { return [] }
        var out: [AttachmentTarget] = []

        if def.canAttachRadially {
            // Fins, boosters and legs mount on the flanks, at a few anchor heights so a
            // single tap is enough — no freehand dragging on a phone.
            for host in design.parts {
                guard let hostDef = host.definition,
                      hostDef.style != .fin, hostDef.style != .landingLegs,
                      host.attachKind != .radial else { continue }
                let dx = hostDef.size.x / 2 + def.size.x / 2
                for fraction in [0.22, 0.5, 0.78] {
                    let y = host.position.y + hostDef.size.y * (0.5 - fraction)
                    for side in [-1, 1] {
                        out.append(AttachmentTarget(
                            hostID: host.id, kind: .radial,
                            position: Vec2(host.position.x + Double(side) * dx, y),
                            side: side))
                    }
                }
            }
            return out
        }

        for host in design.parts {
            guard let hostDef = host.definition else { continue }
            if def.acceptsTopAttachment, hostDef.acceptsBottomAttachment,
               !hasChild(host.id, kind: .bottom), host.attachKind != .radial {
                out.append(AttachmentTarget(
                    hostID: host.id, kind: .bottom,
                    position: Vec2(host.position.x,
                                   host.position.y - hostDef.size.y / 2 - def.size.y / 2),
                    side: 0))
            }
            if def.acceptsBottomAttachment, hostDef.acceptsTopAttachment,
               !hasChild(host.id, kind: .top), host.attachKind != .radial {
                out.append(AttachmentTarget(
                    hostID: host.id, kind: .top,
                    position: Vec2(host.position.x,
                                   host.position.y + hostDef.size.y / 2 + def.size.y / 2),
                    side: 0))
            }
        }
        return out
    }

    func place(at target: AttachmentTarget) {
        guard let def = pendingDefinition else { return }
        if target.kind == .radial && symmetry {
            let group = UUID()
            guard let host = design.part(target.hostID), let hostDef = host.definition else { return }
            let dx = hostDef.size.x / 2 + def.size.x / 2
            for side in [-1, 1] {
                design.parts.append(PlacedPart(
                    definitionID: def.id,
                    position: Vec2(host.position.x + Double(side) * dx, target.position.y),
                    parentID: target.hostID, attachKind: .radial,
                    symmetryGroupID: group, side: side))
            }
        } else {
            design.parts.append(PlacedPart(
                definitionID: def.id, position: target.position,
                parentID: target.hostID, attachKind: target.kind,
                side: target.side))
        }
        design.autoAssignStages()
        pendingDefinition = nil
        objectWillChange.send()
    }

    // MARK: - Selection and editing

    /// Topmost part under a point in design space. Smallest match wins, so a fin on the
    /// side of a tank is still selectable.
    func part(at point: Vec2) -> PlacedPart? {
        var best: PlacedPart?
        var bestArea = Double.greatestFiniteMagnitude
        for p in design.parts {
            guard let d = p.definition else { continue }
            let half = d.size / 2
            if abs(point.x - p.position.x) <= half.x, abs(point.y - p.position.y) <= half.y {
                let area = d.size.x * d.size.y
                if area < bestArea { bestArea = area; best = p }
            }
        }
        return best
    }

    func deleteSelection() {
        guard let id = selectedPartID, let part = design.part(id) else { return }
        guard id != design.rootID else { return }
        var doomed = Set(design.subtree(of: id))
        // Mirrored pairs come and go together.
        if let group = part.symmetryGroupID {
            for twin in design.parts where twin.symmetryGroupID == group {
                doomed.formUnion(design.subtree(of: twin.id))
            }
        }
        doomed.remove(design.rootID ?? UUID())
        design.parts.removeAll { doomed.contains($0.id) }
        design.autoAssignStages()
        selectedPartID = nil
    }

    func moveSelectedStage(by delta: Int) {
        guard let id = selectedPartID,
              let index = design.parts.firstIndex(where: { $0.id == id }) else { return }
        let newStage = MathUtil.clamp(design.parts[index].stage + delta, 0, design.stageCount)
        design.parts[index].stage = newStage
        if let group = design.parts[index].symmetryGroupID {
            for i in design.parts.indices where design.parts[i].symmetryGroupID == group {
                design.parts[i].stage = newStage
            }
        }
        design.normalizeStages()
        objectWillChange.send()
    }

    func clearAll() {
        guard let root = design.root else { return }
        design.parts = [root]
        design.rootID = root.id
        selectedPartID = nil
        design.normalizeStages()
    }

    var canLaunch: Bool {
        design.hasCommand && !analysis.stages.isEmpty
    }
}
