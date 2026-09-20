import Foundation

/// Per-stage performance figures shown in the builder and on the flight HUD.
struct StageAnalysis: Identifiable {
    let id: Int
    let index: Int
    let startMass: Double      // kg at ignition
    let endMass: Double        // kg when the stage's propellant is gone
    let propellantMass: Double // kg
    let thrustVacuum: Double   // N
    let thrustSeaLevel: Double // N
    let ispVacuum: Double      // s
    let ispSeaLevel: Double    // s
    let deltaVVacuum: Double   // m/s
    let deltaVSeaLevel: Double // m/s
    let burnTime: Double       // s at full throttle
    let engineCount: Int
    let jettisonedMass: Double // kg dropped when this stage fires
    /// Thrust-to-weight at ignition, against Terra's surface gravity.
    let liftoffTWR: Double
}

/// Walks the staging sequence on paper: drops what each stage jettisons, lights the
/// engines it activates, and burns the propellant reachable from them.
struct DesignAnalysis {
    let design: VesselDesign
    let stages: [StageAnalysis]
    let totalMass: Double
    let totalDeltaV: Double
    let partCount: Int

    init(design: VesselDesign, referenceGravity: Double = SolarSystem.shared.home.surfaceGravity) {
        self.design = design
        self.partCount = design.parts.count

        var active = Set(design.parts.map(\.id))
        let byID = Dictionary(uniqueKeysWithValues: design.parts.map { ($0.id, $0) })

        // Which fuel section each part belongs to, and how much is left in each.
        let sections = design.fuelSections()
        var sectionOfPart: [UUID: Int] = [:]
        var sectionFuel: [Double] = []
        for (i, section) in sections.enumerated() {
            var fuel = 0.0
            for id in section {
                sectionOfPart[id] = i
                if let d = byID[id]?.definition, !d.isSolidBooster {
                    fuel += d.fuelCapacity
                }
            }
            sectionFuel.append(fuel)
        }

        /// Dry mass of the live parts (solid boosters include their own grain) plus the
        /// propellant still sitting in sections that have live parts.
        func currentMass(active: Set<UUID>, remaining: [Double], solidBurned: Set<UUID>) -> Double {
            var m = 0.0
            for id in active {
                guard let d = byID[id]?.definition else { continue }
                m += d.dryMass
                if d.isSolidBooster, !solidBurned.contains(id) { m += d.fuelCapacity }
            }
            for (i, section) in sections.enumerated() where !section.isDisjoint(with: active) {
                m += remaining[i]
            }
            return m
        }

        var remainingFuel = sectionFuel
        var solidBurned = Set<UUID>()
        var result: [StageAnalysis] = []
        var ignited = Set<UUID>()

        for stageIndex in 0..<max(design.stageCount, 0) {
            let staged = design.activatedParts(inStage: stageIndex)

            // 1. Jettison: decouplers in this stage, plus radial boosters already lit.
            var jettisoned = Set<UUID>()
            for p in staged {
                guard let d = p.definition else { continue }
                if d.isDecoupler {
                    jettisoned.formUnion(design.subtree(of: p.id))
                } else if d.isSolidBooster, p.attachKind == .radial, ignited.contains(p.id) {
                    jettisoned.formUnion(design.subtree(of: p.id))
                }
            }
            jettisoned.formIntersection(active)
            var jettisonedMass = 0.0
            for id in jettisoned {
                guard let d = byID[id]?.definition else { continue }
                jettisonedMass += d.dryMass
                if d.isSolidBooster, !solidBurned.contains(id) { jettisonedMass += d.fuelCapacity }
            }
            active.subtract(jettisoned)
            // Propellant that left with the jettisoned hardware is gone too.
            for (i, section) in sections.enumerated() where section.isDisjoint(with: active) {
                jettisonedMass += remainingFuel[i]
                remainingFuel[i] = 0
            }

            // 2. Ignition.
            let engines = staged.filter { $0.definition?.isEngine == true && active.contains($0.id) }
            ignited.formUnion(engines.map(\.id))

            let startMass = currentMass(active: active, remaining: remainingFuel, solidBurned: solidBurned)

            var thrustVac = 0.0, thrustSL = 0.0
            var flowVac = 0.0, flowSL = 0.0
            var propellant = 0.0
            var touchedSections = Set<Int>()

            for e in engines {
                guard let d = e.definition else { continue }
                thrustVac += d.thrustVacuum
                thrustSL += d.thrustSeaLevel
                flowVac += d.thrustVacuum / (d.ispVacuum * Units.g0)
                flowSL += d.thrustSeaLevel / (max(d.ispSeaLevel, 1) * Units.g0)
                if d.isSolidBooster {
                    if !solidBurned.contains(e.id) {
                        propellant += d.fuelCapacity
                        solidBurned.insert(e.id)
                    }
                } else if let s = sectionOfPart[e.id] {
                    touchedSections.insert(s)
                }
            }
            for s in touchedSections {
                propellant += remainingFuel[s]
                remainingFuel[s] = 0
            }

            guard !engines.isEmpty else { continue }

            let endMass = max(startMass - propellant, 1)
            let ispVac = flowVac > 0 ? thrustVac / (flowVac * Units.g0) : 0
            let ispSL = flowSL > 0 ? thrustSL / (flowSL * Units.g0) : 0
            let ratio = startMass / endMass
            let dvVac = ispVac * Units.g0 * log(ratio)
            let dvSL = ispSL * Units.g0 * log(ratio)
            let burn = flowVac > 0 ? propellant / flowVac : 0

            result.append(StageAnalysis(
                id: stageIndex,
                index: stageIndex,
                startMass: startMass,
                endMass: endMass,
                propellantMass: propellant,
                thrustVacuum: thrustVac,
                thrustSeaLevel: thrustSL,
                ispVacuum: ispVac,
                ispSeaLevel: ispSL,
                deltaVVacuum: dvVac.isFinite ? dvVac : 0,
                deltaVSeaLevel: dvSL.isFinite ? dvSL : 0,
                burnTime: burn,
                engineCount: engines.count,
                jettisonedMass: jettisonedMass,
                liftoffTWR: startMass > 0 ? thrustSL / (startMass * referenceGravity) : 0
            ))
        }

        self.stages = result
        self.totalDeltaV = result.reduce(0) { $0 + $1.deltaVVacuum }
        self.totalMass = design.parts.reduce(0) { $0 + ($1.definition?.wetMass ?? 0) }
    }
}
