import Foundation

/// Small helper for assembling a rocket in code, stacking parts downward from the pod.
final class StackBuilder {
    private(set) var design: VesselDesign
    private var bottomID: UUID
    private var bottomY: Double
    private var topID: UUID
    private var topY: Double

    init(name: String, root rootDefID: String) {
        let d = PartCatalog.part(rootDefID)!
        let root = PlacedPart(definitionID: rootDefID, position: .zero)
        design = VesselDesign(name: name, parts: [root], rootID: root.id)
        bottomID = root.id
        topID = root.id
        bottomY = -d.size.y / 2
        topY = d.size.y / 2
    }

    /// Stacks a part onto the bottom of the rocket.
    @discardableResult
    func add(_ defID: String) -> UUID {
        guard let d = PartCatalog.part(defID) else { return bottomID }
        let y = bottomY - d.size.y / 2
        let part = PlacedPart(definitionID: defID, position: Vec2(0, y),
                              parentID: bottomID, attachKind: .bottom)
        design.parts.append(part)
        bottomID = part.id
        bottomY = y - d.size.y / 2
        return part.id
    }

    /// Stacks a part onto the nose.
    @discardableResult
    func addNose(_ defID: String) -> UUID {
        guard let d = PartCatalog.part(defID) else { return topID }
        let y = topY + d.size.y / 2
        let part = PlacedPart(definitionID: defID, position: Vec2(0, y),
                              parentID: topID, attachKind: .top)
        design.parts.append(part)
        topID = part.id
        topY = y + d.size.y / 2
        return part.id
    }

    /// Adds a mirrored pair of radially-attached parts to `host`.
    @discardableResult
    func addPair(_ defID: String, to host: UUID, centerY: Double) -> [UUID] {
        guard let d = PartCatalog.part(defID),
              let hostPart = design.part(host),
              let hostDef = hostPart.definition else { return [] }
        let dx = hostDef.size.x / 2 + d.size.x / 2
        let group = UUID()
        var ids: [UUID] = []
        for side in [-1, 1] {
            let part = PlacedPart(definitionID: defID,
                                  position: Vec2(hostPart.position.x + Double(side) * dx, centerY),
                                  parentID: host, attachKind: .radial,
                                  symmetryGroupID: group, side: side)
            design.parts.append(part)
            ids.append(part.id)
        }
        return ids
    }

    /// Y coordinate of the bottom face of the lowest part.
    var currentBottomY: Double { bottomY }
    var lastAddedID: UUID { bottomID }

    func finish() -> VesselDesign {
        var d = design
        d.autoAssignStages()
        return d
    }
}

/// Rockets the game ships with, so a new player can fly something before they have to
/// design anything. Each one is a working answer to a specific mission.
enum StockCraft {
    static var all: [VesselDesign] { [sparrow, orbiter, seleneVoyager] }

    /// Sub-orbital hop. Teaches throttle, staging and parachutes.
    static var sparrow: VesselDesign {
        let b = StackBuilder(name: "Sparrow I", root: "pod-mk1")
        b.addNose("chute-mk16")
        let tank = b.add("tank-t400")
        b.add("engine-reliant")
        b.addPair("fin-basic", to: tank, centerY: -2.4)
        return b.finish()
    }

    /// Two stages to orbit, with margin to come home again.
    static var orbiter: VesselDesign {
        let b = StackBuilder(name: "Orbiter II", root: "pod-mk1")
        b.addNose("chute-mk16")
        b.add("tank-t400")
        b.add("engine-terrier")
        b.add("decoupler-125")
        b.add("tank-t800")
        let finHost = b.add("tank-t400")
        b.add("engine-swivel")
        b.addPair("fin-basic", to: finHost, centerY: -8.9)
        return b.finish()
    }

    /// Three stages: a solid-assisted lifter, a transfer stage, and a lander on legs.
    static var seleneVoyager: VesselDesign {
        let b = StackBuilder(name: "Selene Voyager", root: "pod-mk1")
        b.addNose("chute-mk16")
        let landerTank = b.add("tank-t400")
        b.add("engine-terrier")
        b.addPair("legs", to: landerTank, centerY: -2.4)
        b.add("decoupler-125")
        b.add("tank-t800")
        b.add("engine-terrier")
        b.add("adapter-250-125")
        b.add("decoupler-250")
        b.add("tank-x200-32")
        b.add("tank-x200-32")
        let core = b.add("tank-x200-32")
        b.add("engine-mainsail")
        b.addPair("fin-large", to: core, centerY: -20.0)
        b.addPair("booster-thumper", to: core, centerY: -16.0)
        return restageBoosters(b.finish())
    }

    /// Solid boosters ignite alongside the first-stage engine and are jettisoned by the
    /// stage after it, which is how a player would set them up by hand.
    private static func restageBoosters(_ design: VesselDesign) -> VesselDesign {
        var d = design
        let boosterIDs = d.parts.filter { $0.definition?.isSolidBooster == true }.map(\.id)
        guard !boosterIDs.isEmpty else { return d }
        let firstStage = d.parts
            .filter { $0.definition?.isEngine == true && $0.definition?.isSolidBooster == false }
            .map(\.stage).min() ?? 0
        for i in d.parts.indices where boosterIDs.contains(d.parts[i].id) {
            d.parts[i].stage = firstStage
        }
        return d
    }
}
