import Foundation
import SwiftUI

/// The part list. Numbers are tuned so a two-stage rocket of roughly 12 tonnes makes
/// orbit around Terra with a little margin, and a three-stage stack reaches Selene.
enum PartCatalog {
    static let all: [PartDefinition] = [
        // MARK: Command
        PartDefinition(
            id: "pod-mk1", name: "Mk1 Capsule",
            blurb: "One seat, a heat shield and just enough reaction wheel to point where you like.",
            category: .command, style: .pod, size: Vec2(1.25, 1.2),
            dryMass: 840, dragCoefficient: 0.22, reactionTorque: 6_000,
            crewCapacity: 1, impactTolerance: 14,
            tint: Color(white: 0.86)),
        PartDefinition(
            id: "pod-mk2", name: "Mk2 Lander Can",
            blurb: "Two seats and a strong reaction wheel. Wide, light and happy on legs.",
            category: .command, style: .pod, size: Vec2(2.5, 1.6),
            dryMass: 2_000, dragCoefficient: 0.30, reactionTorque: 16_000,
            crewCapacity: 2, impactTolerance: 12,
            tint: Color(white: 0.80)),
        PartDefinition(
            id: "probe-core", name: "Probe Core",
            blurb: "No crew, barely any mass, and it still holds an attitude.",
            category: .command, style: .adapter, size: Vec2(1.25, 0.3),
            dryMass: 90, dragCoefficient: 0.15, reactionTorque: 2_200,
            impactTolerance: 10,
            tint: Color(white: 0.55)),

        // MARK: Fuel
        PartDefinition(
            id: "tank-t100", name: "FL-T100 Tank",
            blurb: "A half-tonne of propellant for trimming an orbit.",
            category: .fuel, style: .tank, size: Vec2(1.25, 0.8),
            dryMass: 63, fuelCapacity: 500, dragCoefficient: 0.2,
            tint: Color(white: 0.88)),
        PartDefinition(
            id: "tank-t400", name: "FL-T400 Tank",
            blurb: "The workhorse upper-stage tank.",
            category: .fuel, style: .tank, size: Vec2(1.25, 1.9),
            dryMass: 250, fuelCapacity: 2_000, dragCoefficient: 0.2,
            tint: Color(white: 0.88)),
        PartDefinition(
            id: "tank-t800", name: "FL-T800 Tank",
            blurb: "Four tonnes of propellant in a 1.25 m body.",
            category: .fuel, style: .tank, size: Vec2(1.25, 3.7),
            dryMass: 500, fuelCapacity: 4_000, dragCoefficient: 0.2,
            tint: Color(white: 0.88)),
        PartDefinition(
            id: "tank-x200-16", name: "X200-16 Tank",
            blurb: "2.5 m class. Pair it with something loud.",
            category: .fuel, style: .tank, size: Vec2(2.5, 1.9),
            dryMass: 1_000, fuelCapacity: 8_000, dragCoefficient: 0.2,
            tint: Color(white: 0.84)),
        PartDefinition(
            id: "tank-x200-32", name: "X200-32 Tank",
            blurb: "Sixteen tonnes of propellant. Check your thrust-to-weight.",
            category: .fuel, style: .tank, size: Vec2(2.5, 3.7),
            dryMass: 2_000, fuelCapacity: 16_000, dragCoefficient: 0.2,
            tint: Color(white: 0.84)),

        // MARK: Engines
        PartDefinition(
            id: "engine-terrier", name: "LV-909 \"Terrier\"",
            blurb: "Vacuum engine. Useless at sea level, superb once you are up.",
            category: .engine, style: .engine, size: Vec2(1.25, 1.0),
            dryMass: 500,
            thrustVacuum: 60_000, thrustSeaLevel: 14_800,
            ispVacuum: 345, ispSeaLevel: 85,
            gimbalRange: 0.0698, dragCoefficient: 0.3,
            tint: Color(red: 0.75, green: 0.70, blue: 0.62)),
        PartDefinition(
            id: "engine-swivel", name: "LV-T45 \"Swivel\"",
            blurb: "Gimballed first-stage engine. Steers as well as it pushes.",
            category: .engine, style: .engine, size: Vec2(1.25, 1.5),
            dryMass: 1_500,
            thrustVacuum: 215_000, thrustSeaLevel: 167_900,
            ispVacuum: 320, ispSeaLevel: 250,
            gimbalRange: 0.0524, dragCoefficient: 0.3,
            tint: Color(red: 0.70, green: 0.66, blue: 0.60)),
        PartDefinition(
            id: "engine-reliant", name: "LV-T30 \"Reliant\"",
            blurb: "More thrust than the Swivel, but it will not steer. Bring fins.",
            category: .engine, style: .engine, size: Vec2(1.25, 1.5),
            dryMass: 1_250,
            thrustVacuum: 240_000, thrustSeaLevel: 205_200,
            ispVacuum: 310, ispSeaLevel: 265,
            gimbalRange: 0, dragCoefficient: 0.3,
            tint: Color(red: 0.66, green: 0.62, blue: 0.58)),
        PartDefinition(
            id: "engine-mainsail", name: "KR-2L \"Mainsail\"",
            blurb: "2.5 m heavy lifter. Drinks propellant at an alarming rate.",
            category: .engine, style: .engine, size: Vec2(2.5, 2.1),
            dryMass: 6_000,
            thrustVacuum: 1_500_000, thrustSeaLevel: 1_379_000,
            ispVacuum: 310, ispSeaLevel: 285,
            gimbalRange: 0.0349, dragCoefficient: 0.35,
            tint: Color(red: 0.62, green: 0.58, blue: 0.56)),
        PartDefinition(
            id: "engine-poodle", name: "RE-L10 \"Poodle\"",
            blurb: "2.5 m vacuum engine for transfer stages and landers.",
            category: .engine, style: .engine, size: Vec2(2.5, 1.6),
            dryMass: 1_750,
            thrustVacuum: 250_000, thrustSeaLevel: 64_300,
            ispVacuum: 350, ispSeaLevel: 90,
            gimbalRange: 0.0785, dragCoefficient: 0.32,
            tint: Color(red: 0.74, green: 0.70, blue: 0.66)),
        PartDefinition(
            id: "booster-thumper", name: "BACC \"Thumper\"",
            blurb: "Solid booster. Lights once, burns to the end, no take-backs.",
            category: .engine, style: .solidBooster, size: Vec2(1.25, 5.0),
            dryMass: 750, fuelCapacity: 6_500,
            thrustVacuum: 300_000, thrustSeaLevel: 250_000,
            ispVacuum: 195, ispSeaLevel: 170,
            gimbalRange: 0, throttleable: false, dragCoefficient: 0.3,
            tint: Color(red: 0.80, green: 0.78, blue: 0.74)),

        // MARK: Structural
        PartDefinition(
            id: "decoupler-125", name: "TD-12 Decoupler",
            blurb: "Splits a 1.25 m stack when its stage fires.",
            category: .structural, style: .decoupler, size: Vec2(1.25, 0.3),
            dryMass: 50, dragCoefficient: 0.2, isDecoupler: true,
            tint: Color(red: 0.85, green: 0.62, blue: 0.24)),
        PartDefinition(
            id: "decoupler-250", name: "TD-25 Decoupler",
            blurb: "The 2.5 m version, for heavier stacks.",
            category: .structural, style: .decoupler, size: Vec2(2.5, 0.4),
            dryMass: 150, dragCoefficient: 0.22, isDecoupler: true,
            tint: Color(red: 0.85, green: 0.62, blue: 0.24)),
        PartDefinition(
            id: "adapter-250-125", name: "2.5 m to 1.25 m Adapter",
            blurb: "Narrows a wide lower stage down to a 1.25 m payload.",
            category: .structural, style: .adapter, size: Vec2(2.5, 1.0),
            dryMass: 400, dragCoefficient: 0.2,
            tint: Color(white: 0.80)),
        PartDefinition(
            id: "separator-radial", name: "Radial Separator",
            blurb: "Throws a side booster clear when its stage fires.",
            category: .structural, style: .decoupler, size: Vec2(0.5, 0.5),
            dryMass: 40, dragCoefficient: 0.1, isDecoupler: true,
            tint: Color(red: 0.85, green: 0.62, blue: 0.24)),

        // MARK: Aero
        PartDefinition(
            id: "nose-cone", name: "Aerodynamic Nose Cone",
            blurb: "Cuts drag off the top of a stack.",
            category: .aero, style: .noseCone, size: Vec2(1.25, 1.0),
            dryMass: 30, dragCoefficient: -0.12,
            tint: Color(white: 0.90)),
        PartDefinition(
            id: "fin-basic", name: "AV-T1 Winglet",
            blurb: "Passive stability low in the atmosphere. Mount them low, in pairs.",
            category: .aero, style: .fin, size: Vec2(1.0, 1.2),
            dryMass: 50, dragCoefficient: 0.08, liftAuthority: 1.0,
            tint: Color(white: 0.72)),
        PartDefinition(
            id: "fin-large", name: "Delta Deluxe Winglet",
            blurb: "Twice the authority of the AV-T1, and twice the drag.",
            category: .aero, style: .fin, size: Vec2(1.5, 1.6),
            dryMass: 120, dragCoefficient: 0.14, liftAuthority: 2.2,
            tint: Color(white: 0.72)),

        // MARK: Utility
        PartDefinition(
            id: "chute-mk16", name: "Mk16 Parachute",
            blurb: "Deploy below 8 km and under 350 m/s, or it tears away.",
            category: .utility, style: .parachute, size: Vec2(1.25, 0.5),
            dryMass: 100, dragCoefficient: 0.2,
            isParachute: true, parachuteDrag: 55, impactTolerance: 12,
            tint: Color(red: 0.90, green: 0.52, blue: 0.30)),
        PartDefinition(
            id: "chute-radial", name: "Radial Drogue Chute",
            blurb: "Smaller canopy that survives faster, higher deployment.",
            category: .utility, style: .parachute, size: Vec2(0.6, 0.6),
            dryMass: 75, dragCoefficient: 0.12,
            isParachute: true, parachuteDrag: 22, impactTolerance: 12,
            tint: Color(red: 0.55, green: 0.70, blue: 0.90)),
        PartDefinition(
            id: "legs", name: "LT-1 Landing Struts",
            blurb: "Doubles your survivable touchdown speed. Mount in pairs.",
            category: .utility, style: .landingLegs, size: Vec2(0.7, 1.0),
            dryMass: 50, dragCoefficient: 0.05, impactTolerance: 22,
            tint: Color(white: 0.66)),
    ]

    private static let index: [String: PartDefinition] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }()

    static func part(_ id: String) -> PartDefinition? { index[id] }

    static func parts(in category: PartCategory) -> [PartDefinition] {
        all.filter { $0.category == category }
    }
}
