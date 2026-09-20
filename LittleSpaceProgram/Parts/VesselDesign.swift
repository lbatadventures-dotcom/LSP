import Foundation

/// One part placed in a rocket. Parts form a tree rooted at `VesselDesign.rootID`;
/// firing a decoupler drops that part's whole subtree.
struct PlacedPart: Identifiable, Codable, Equatable {
    var id: UUID
    var definitionID: String
    /// Centre of the part in design space, metres, +y toward the nose.
    var position: Vec2
    var parentID: UUID?
    var attachKind: AttachKind
    /// Stage group. Stage 0 fires first.
    var stage: Int
    /// Parts placed as a mirrored pair share a symmetry group and are edited together.
    var symmetryGroupID: UUID?
    /// -1 on the left flank, +1 on the right, 0 for inline parts.
    var side: Int

    init(id: UUID = UUID(), definitionID: String, position: Vec2, parentID: UUID? = nil,
         attachKind: AttachKind = .bottom, stage: Int = 0,
         symmetryGroupID: UUID? = nil, side: Int = 0) {
        self.id = id
        self.definitionID = definitionID
        self.position = position
        self.parentID = parentID
        self.attachKind = attachKind
        self.stage = stage
        self.symmetryGroupID = symmetryGroupID
        self.side = side
    }

    var definition: PartDefinition? { PartCatalog.part(definitionID) }
}

struct VesselDesign: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var parts: [PlacedPart]
    var rootID: UUID?
    var modifiedAt: Date

    init(id: UUID = UUID(), name: String = "Untitled Rocket",
         parts: [PlacedPart] = [], rootID: UUID? = nil, modifiedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.parts = parts
        self.rootID = rootID
        self.modifiedAt = modifiedAt
    }

    // MARK: - Tree access

    func part(_ id: UUID) -> PlacedPart? { parts.first { $0.id == id } }

    func children(of id: UUID) -> [PlacedPart] { parts.filter { $0.parentID == id } }

    /// `id` and every part hanging off it.
    func subtree(of id: UUID) -> [UUID] {
        var result: [UUID] = []
        var queue: [UUID] = [id]
        while let next = queue.popLast() {
            guard !result.contains(next) else { continue }
            result.append(next)
            queue.append(contentsOf: children(of: next).map(\.id))
        }
        return result
    }

    var root: PlacedPart? {
        if let rootID, let p = part(rootID) { return p }
        return parts.first { $0.parentID == nil }
    }

    var isEmpty: Bool { parts.isEmpty }

    var stageCount: Int { (parts.map(\.stage).max() ?? -1) + 1 }

    var commandPart: PlacedPart? {
        parts.first { $0.definition?.category == .command }
    }

    var hasCommand: Bool { commandPart != nil }

    /// Problems worth warning the player about before they light the engines.
    var warnings: [String] {
        var out: [String] = []
        if !hasCommand { out.append("No command pod or probe core — nothing to fly the rocket.") }
        let analysis = DesignAnalysis(design: self)
        if analysis.stages.isEmpty {
            out.append("No engines staged.")
        } else if let first = analysis.stages.first, first.thrustSeaLevel > 0,
                  first.liftoffTWR < 1.0 {
            out.append(String(format: "First-stage thrust-to-weight is %.2f — it will not leave the pad.",
                              first.liftoffTWR))
        }
        if !parts.contains(where: { $0.definition?.isParachute == true }) {
            out.append("No parachute — re-entry will be a one-way trip.")
        }
        if analysis.totalDeltaV < 3_400 {
            out.append(String(format: "Only %.0f m/s of delta-v. Orbit around Terra needs about 3400.",
                              analysis.totalDeltaV))
        }
        return out
    }

    // MARK: - Geometry

    /// Axis-aligned bounds of the rocket in design space, in metres.
    var bounds: (min: Vec2, max: Vec2) {
        guard !parts.isEmpty else { return (.zero, .zero) }
        var lo = Vec2(.greatestFiniteMagnitude, .greatestFiniteMagnitude)
        var hi = Vec2(-.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
        for p in parts {
            guard let d = p.definition else { continue }
            let half = d.size / 2
            lo = Vec2(min(lo.x, p.position.x - half.x), min(lo.y, p.position.y - half.y))
            hi = Vec2(max(hi.x, p.position.x + half.x), max(hi.y, p.position.y + half.y))
        }
        return (lo, hi)
    }

    var height: Double { bounds.max.y - bounds.min.y }

    /// Design-space centre of mass with every tank full.
    var centerOfMass: Vec2 {
        var sum = Vec2.zero
        var total = 0.0
        for p in parts {
            guard let d = p.definition else { continue }
            let m = d.wetMass
            sum += p.position * m
            total += m
        }
        return total > 0 ? sum / total : .zero
    }

    // MARK: - Staging

    /// Assigns stages the way a player usually would: engines and decouplers fire from
    /// the bottom of the stack upward, and parachutes come last.
    mutating func autoAssignStages() {
        let ordered = parts
            .filter { p in
                guard let d = p.definition else { return false }
                return d.isEngine || d.isDecoupler || d.isParachute
            }
            .sorted { $0.position.y < $1.position.y }

        // Bottom-up: engines join the current stage, and each decoupler opens a new one
        // (stage N ignites engines, stage N+1 drops them and lights the next set).
        var stage = 0
        var assignment: [UUID: Int] = [:]

        for p in ordered {
            guard let d = p.definition, !d.isParachute else { continue }
            if d.isDecoupler { stage += 1 }
            assignment[p.id] = stage
        }

        let lastStage = (assignment.values.max() ?? 0) + 1
        for p in ordered where p.definition?.isParachute == true {
            assignment[p.id] = lastStage
        }

        for i in parts.indices {
            parts[i].stage = assignment[parts[i].id] ?? 0
        }
        normalizeStages()
    }

    /// Removes gaps in the stage numbering so the staging list has no blank rows.
    mutating func normalizeStages() {
        let active = Set(parts.compactMap { p -> Int? in
            guard let d = p.definition else { return nil }
            return (d.isEngine || d.isDecoupler || d.isParachute) ? p.stage : nil
        })
        let sorted = active.sorted()
        var remap: [Int: Int] = [:]
        for (newIndex, old) in sorted.enumerated() { remap[old] = newIndex }
        for i in parts.indices {
            guard let d = parts[i].definition else { continue }
            if d.isEngine || d.isDecoupler || d.isParachute {
                parts[i].stage = remap[parts[i].stage] ?? 0
            } else {
                parts[i].stage = 0
            }
        }
    }

    /// Parts that do something when the given stage fires.
    func activatedParts(inStage stage: Int) -> [PlacedPart] {
        parts.filter { p in
            guard let d = p.definition else { return false }
            return p.stage == stage && (d.isEngine || d.isDecoupler || d.isParachute)
        }
    }

    // MARK: - Fuel sections

    /// Groups of parts that share propellant. Decouplers block crossfeed, so each
    /// group is a maximal set of connected parts with no decoupler on the path.
    /// Solid boosters are always their own section.
    func fuelSections() -> [Set<UUID>] {
        var parentOf: [UUID: UUID] = [:]

        func find(_ a: UUID) -> UUID {
            var x = a
            while let p = parentOf[x], p != x { x = p }
            return x
        }
        func union(_ a: UUID, _ b: UUID) {
            let ra = find(a), rb = find(b)
            if ra != rb { parentOf[ra] = rb }
        }

        for p in parts { parentOf[p.id] = p.id }

        for p in parts {
            guard let parentID = p.parentID,
                  let d = p.definition,
                  let pd = part(parentID)?.definition else { continue }
            // A decoupler on either end of the joint cuts the flow.
            if d.isDecoupler || pd.isDecoupler { continue }
            // Solid boosters keep their propellant to themselves.
            if d.isSolidBooster || pd.isSolidBooster { continue }
            union(p.id, parentID)
        }

        var groups: [UUID: Set<UUID>] = [:]
        for p in parts {
            groups[find(p.id), default: []].insert(p.id)
        }
        return Array(groups.values)
    }
}
