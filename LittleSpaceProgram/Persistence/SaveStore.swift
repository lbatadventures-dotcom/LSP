import Foundation

/// A flight frozen to disk, so a mission survives the app being swiped away.
struct FlightSave: Codable, Identifiable {
    var id: UUID = UUID()
    var vesselName: String
    var design: VesselDesign
    var bodyID: String
    var position: Vec2
    var velocity: Vec2
    var heading: Double
    var angularVelocity: Double
    var throttle: Double
    var currentStage: Int
    var missionTime: Double
    var universeTime: Double
    var situationRaw: String
    var activeParts: [UUID]
    var solidFuel: [UUID: Double]
    var ignited: [UUID]
    var chutesDeployed: [UUID]
    var sectionFuel: [Double]
    var savedAt: Date = Date()
}

/// JSON files in Application Support. Small enough that the whole library loads at
/// launch without a measurable delay, and easy to inspect when something goes wrong.
final class SaveStore {
    static let shared = SaveStore()

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        createDirectories()
    }

    private var root: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("LittleSpaceProgram", isDirectory: true)
    }

    private var craftDirectory: URL { root.appendingPathComponent("Craft", isDirectory: true) }
    private var flightURL: URL { root.appendingPathComponent("flight.json") }

    private func createDirectories() {
        try? fileManager.createDirectory(at: craftDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Craft

    func loadCraft() -> [VesselDesign] {
        guard let files = try? fileManager.contentsOfDirectory(at: craftDirectory,
                                                               includingPropertiesForKeys: nil) else {
            return []
        }
        var out: [VesselDesign] = []
        for url in files where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let design = try? decoder.decode(VesselDesign.self, from: data) {
                out.append(design)
            }
        }
        return out.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func save(_ design: VesselDesign) {
        createDirectories()
        var copy = design
        copy.modifiedAt = Date()
        guard let data = try? encoder.encode(copy) else { return }
        let url = craftDirectory.appendingPathComponent("\(copy.id.uuidString).json")
        try? data.write(to: url, options: .atomic)
    }

    func delete(_ design: VesselDesign) {
        let url = craftDirectory.appendingPathComponent("\(design.id.uuidString).json")
        try? fileManager.removeItem(at: url)
    }

    /// Writes the stock rockets once, the first time the app runs.
    func installStockCraftIfNeeded() {
        let marker = root.appendingPathComponent(".stock-installed")
        guard !fileManager.fileExists(atPath: marker.path) else { return }
        createDirectories()
        for design in StockCraft.all { save(design) }
        try? Data().write(to: marker)
    }

    // MARK: - Flight

    func saveFlight(_ simulator: FlightSimulator) {
        let v = simulator.vessel
        let save = FlightSave(
            vesselName: v.name,
            design: v.design,
            bodyID: v.body.id,
            position: v.position,
            velocity: v.velocity,
            heading: v.heading,
            angularVelocity: v.angularVelocity,
            throttle: v.throttle,
            currentStage: v.currentStage,
            missionTime: v.missionTime,
            universeTime: v.universeTime,
            situationRaw: v.situation.rawValue,
            activeParts: Array(v.activeParts),
            solidFuel: v.runtime.compactMapValues { $0.solidFuel > 0 ? $0.solidFuel : nil },
            ignited: v.runtime.filter { $0.value.ignited }.map(\.key),
            chutesDeployed: v.runtime.filter { $0.value.parachuteDeployed }.map(\.key),
            sectionFuel: v.fuelNetwork.fuel
        )
        guard let data = try? encoder.encode(save) else { return }
        try? data.write(to: flightURL, options: .atomic)
    }

    func loadFlight() -> FlightSave? {
        guard let data = try? Data(contentsOf: flightURL) else { return nil }
        return try? decoder.decode(FlightSave.self, from: data)
    }

    func clearFlight() {
        try? fileManager.removeItem(at: flightURL)
    }

    var hasSavedFlight: Bool { fileManager.fileExists(atPath: flightURL.path) }

    /// Rebuilds a live simulator from a save.
    func restore(_ save: FlightSave, system: SolarSystem = .shared) -> FlightSimulator {
        let body = system.body(id: save.bodyID)
        let vessel = Vessel(design: save.design, body: body,
                            position: save.position, velocity: save.velocity,
                            heading: save.heading)
        vessel.name = save.vesselName
        vessel.angularVelocity = save.angularVelocity
        vessel.throttle = save.throttle
        vessel.currentStage = save.currentStage
        vessel.missionTime = save.missionTime
        vessel.universeTime = save.universeTime
        vessel.situation = Situation(rawValue: save.situationRaw) ?? .flying
        vessel.activeParts = Set(save.activeParts)

        for id in save.ignited { vessel.runtime[id]?.ignited = true }
        for id in save.chutesDeployed {
            vessel.runtime[id]?.parachuteDeployed = true
            vessel.runtime[id]?.parachuteOpen = 1
        }
        for (id, fuel) in save.solidFuel { vessel.runtime[id]?.solidFuel = fuel }

        vessel.fuelNetwork = FuelNetwork(design: save.design, active: vessel.activeParts)
        if save.sectionFuel.count == vessel.fuelNetwork.fuel.count {
            vessel.fuelNetwork.fuel = save.sectionFuel
        }
        return FlightSimulator(vessel: vessel, system: system, universeTime: save.universeTime)
    }
}
