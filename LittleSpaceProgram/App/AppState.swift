import Combine
import SwiftUI

enum Screen: Equatable {
    case menu
    case builder(VesselDesign)
    case flight
}

/// Top-level app state: which screen is up, the craft library, and player settings.
final class AppState: ObservableObject {
    @Published var screen: Screen = .menu
    @Published var craft: [VesselDesign] = []
    @Published var flight: FlightModel? = nil

    // Settings are plain @Published properties that write through to UserDefaults.
    // @AppStorage only publishes changes when it lives on a View, so inside an
    // ObservableObject it would update the defaults without redrawing anything.
    @Published var hapticsEnabled: Bool { didSet { Defaults.set(hapticsEnabled, .haptics) } }
    @Published var showAdvancedReadouts: Bool { didSet { Defaults.set(showAdvancedReadouts, .advancedReadouts) } }
    @Published var invertPitch: Bool { didSet { Defaults.set(invertPitch, .invertPitch) } }
    @Published var controlSensitivity: Double { didSet { Defaults.set(controlSensitivity, .sensitivity) } }
    @Published var leftHanded: Bool { didSet { Defaults.set(leftHanded, .leftHanded) } }
    @Published var reduceEffects: Bool { didSet { Defaults.set(reduceEffects, .reduceEffects) } }

    private let store = SaveStore.shared

    init() {
        hapticsEnabled = Defaults.bool(.haptics, default: true)
        showAdvancedReadouts = Defaults.bool(.advancedReadouts, default: true)
        invertPitch = Defaults.bool(.invertPitch, default: false)
        controlSensitivity = Defaults.double(.sensitivity, default: 1.0)
        leftHanded = Defaults.bool(.leftHanded, default: false)
        reduceEffects = Defaults.bool(.reduceEffects, default: false)
        store.installStockCraftIfNeeded()
        reloadCraft()
    }

    func reloadCraft() {
        craft = store.loadCraft()
        if craft.isEmpty {
            craft = StockCraft.all
            craft.forEach(store.save)
        }
    }

    // MARK: - Builder

    func newDesign() {
        var design = VesselDesign(name: "New Rocket")
        let pod = PlacedPart(definitionID: "pod-mk1", position: .zero)
        design.parts = [pod]
        design.rootID = pod.id
        screen = .builder(design)
    }

    func edit(_ design: VesselDesign) {
        screen = .builder(design)
    }

    func save(_ design: VesselDesign) {
        store.save(design)
        reloadCraft()
    }

    func delete(_ design: VesselDesign) {
        store.delete(design)
        reloadCraft()
    }

    // MARK: - Flight

    /// Propagates a settings change to a flight already in progress.
    func applySettingsToFlight() {
        flight?.hapticsEnabled = hapticsEnabled
    }

    func launch(_ design: VesselDesign) {
        store.clearFlight()
        let model = FlightModel(design: design)
        model.hapticsEnabled = hapticsEnabled
        flight = model
        screen = .flight
    }

    var hasSavedFlight: Bool { store.hasSavedFlight }

    func resumeFlight() {
        guard let save = store.loadFlight() else { return }
        let model = FlightModel(simulator: store.restore(save))
        model.hapticsEnabled = hapticsEnabled
        flight = model
        screen = .flight
    }

    func endFlight(saving: Bool) {
        if saving, let flight, flight.simulator.vessel.situation != .destroyed {
            store.saveFlight(flight.simulator)
        } else {
            store.clearFlight()
        }
        flight = nil
        screen = .menu
    }

    func revertToLaunch() {
        guard let flight else { return }
        let design = flight.simulator.vessel.design
        launch(design)
    }
}

/// Thin, typed wrapper over UserDefaults so the keys live in one place.
enum Defaults {
    enum Key: String {
        case haptics = "hapticsEnabled"
        case advancedReadouts = "showAdvancedReadouts"
        case invertPitch = "invertPitch"
        case sensitivity = "controlSensitivity"
        case leftHanded = "leftHanded"
        case reduceEffects = "reduceEffects"
    }

    static func set(_ value: Bool, _ key: Key) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }

    static func set(_ value: Double, _ key: Key) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }

    static func bool(_ key: Key, default fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key.rawValue) as? Bool ?? fallback
    }

    static func double(_ key: Key, default fallback: Double) -> Double {
        UserDefaults.standard.object(forKey: key.rawValue) as? Double ?? fallback
    }
}
