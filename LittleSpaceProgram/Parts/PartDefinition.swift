import Foundation
import SwiftUI

enum PartCategory: String, CaseIterable, Identifiable {
    case command, fuel, engine, structural, aero, utility
    var id: String { rawValue }

    var title: String {
        switch self {
        case .command: return "Pods"
        case .fuel: return "Tanks"
        case .engine: return "Engines"
        case .structural: return "Structure"
        case .aero: return "Aero"
        case .utility: return "Utility"
        }
    }

    var symbol: String {
        switch self {
        case .command: return "person.fill"
        case .fuel: return "drop.fill"
        case .engine: return "flame.fill"
        case .structural: return "square.stack.3d.up.fill"
        case .aero: return "wind"
        case .utility: return "wrench.and.screwdriver.fill"
        }
    }
}

/// How a part is drawn. Every part is rendered procedurally, so the app ships with
/// no bitmap art and stays small enough to download over cellular.
enum PartShapeStyle: String {
    case pod, tank, engine, solidBooster, decoupler, noseCone, fin, parachute, landingLegs, adapter
}

enum AttachKind: String, Codable {
    case top, bottom, radial
}

struct AttachNode {
    let kind: AttachKind
    /// Offset from the part's centre, in part-local metres (+y toward the nose).
    let offset: Vec2
}

/// Static description of a part type. Instances in a rocket are `PlacedPart`s that
/// reference this by `id`.
struct PartDefinition: Identifiable {
    let id: String
    let name: String
    let blurb: String
    let category: PartCategory
    let style: PartShapeStyle
    /// Width and height in metres.
    let size: Vec2

    let dryMass: Double          // kg
    let fuelCapacity: Double     // kg of propellant

    let thrustVacuum: Double     // N
    let thrustSeaLevel: Double   // N
    let ispVacuum: Double        // s
    let ispSeaLevel: Double      // s
    let gimbalRange: Double      // rad
    let throttleable: Bool

    let dragCoefficient: Double  // dimensionless, multiplied by frontal area
    let liftAuthority: Double    // aerodynamic restoring authority (fins)
    let reactionTorque: Double   // N*m from reaction wheels

    let isDecoupler: Bool
    let isParachute: Bool
    let parachuteDrag: Double    // effective Cd*A when fully deployed, m^2
    let crewCapacity: Int
    let impactTolerance: Double  // m/s
    let tint: Color

    init(id: String, name: String, blurb: String, category: PartCategory,
         style: PartShapeStyle, size: Vec2, dryMass: Double,
         fuelCapacity: Double = 0,
         thrustVacuum: Double = 0, thrustSeaLevel: Double = 0,
         ispVacuum: Double = 0, ispSeaLevel: Double = 0,
         gimbalRange: Double = 0, throttleable: Bool = true,
         dragCoefficient: Double = 0.25, liftAuthority: Double = 0,
         reactionTorque: Double = 0, isDecoupler: Bool = false,
         isParachute: Bool = false, parachuteDrag: Double = 0,
         crewCapacity: Int = 0, impactTolerance: Double = 8,
         tint: Color = Color(white: 0.82)) {
        self.id = id
        self.name = name
        self.blurb = blurb
        self.category = category
        self.style = style
        self.size = size
        self.dryMass = dryMass
        self.fuelCapacity = fuelCapacity
        self.thrustVacuum = thrustVacuum
        self.thrustSeaLevel = thrustSeaLevel
        self.ispVacuum = ispVacuum
        self.ispSeaLevel = ispSeaLevel
        self.gimbalRange = gimbalRange
        self.throttleable = throttleable
        self.dragCoefficient = dragCoefficient
        self.liftAuthority = liftAuthority
        self.reactionTorque = reactionTorque
        self.isDecoupler = isDecoupler
        self.isParachute = isParachute
        self.parachuteDrag = parachuteDrag
        self.crewCapacity = crewCapacity
        self.impactTolerance = impactTolerance
        self.tint = tint
    }

    var wetMass: Double { dryMass + fuelCapacity }
    var isEngine: Bool { thrustVacuum > 0 }
    /// Solid boosters carry their own propellant and cannot be throttled or shut down.
    var isSolidBooster: Bool { isEngine && !throttleable }
    var isTank: Bool { fuelCapacity > 0 && !isEngine }
    var frontalArea: Double { size.x * size.x * .pi / 4 }

    /// Thrust at a given ambient pressure (Pa), linearly interpolated between the
    /// sea-level and vacuum figures like the real engine curves.
    func thrust(atPressure p: Double) -> Double {
        let f = MathUtil.clamp(p / 101_325, 0, 1)
        return MathUtil.lerp(thrustVacuum, thrustSeaLevel, f)
    }

    func isp(atPressure p: Double) -> Double {
        let f = MathUtil.clamp(p / 101_325, 0, 1)
        return max(1, MathUtil.lerp(ispVacuum, ispSeaLevel, f))
    }

    /// Propellant mass flow at full throttle, kg/s.
    func massFlow(atPressure p: Double) -> Double {
        thrust(atPressure: p) / (isp(atPressure: p) * Units.g0)
    }

    var attachNodes: [AttachNode] {
        let halfH = size.y / 2
        switch style {
        case .pod:
            return [AttachNode(kind: .top, offset: Vec2(0, halfH)),
                    AttachNode(kind: .bottom, offset: Vec2(0, -halfH))]
        case .noseCone, .parachute:
            return [AttachNode(kind: .bottom, offset: Vec2(0, -halfH))]
        case .engine:
            return [AttachNode(kind: .top, offset: Vec2(0, halfH))]
        case .solidBooster:
            return [AttachNode(kind: .top, offset: Vec2(0, halfH)),
                    AttachNode(kind: .radial, offset: Vec2(0, 0))]
        case .fin, .landingLegs:
            return []
        default:
            return [AttachNode(kind: .top, offset: Vec2(0, halfH)),
                    AttachNode(kind: .bottom, offset: Vec2(0, -halfH)),
                    AttachNode(kind: .radial, offset: Vec2(0, 0))]
        }
    }

    /// True when this part can be surface-attached to the side of another part.
    var canAttachRadially: Bool {
        switch style {
        case .solidBooster, .fin, .landingLegs: return true
        default: return false
        }
    }

    /// True when another part can stack on top of this one.
    var acceptsTopAttachment: Bool {
        attachNodes.contains { $0.kind == .top }
    }

    var acceptsBottomAttachment: Bool {
        attachNodes.contains { $0.kind == .bottom }
    }
}
