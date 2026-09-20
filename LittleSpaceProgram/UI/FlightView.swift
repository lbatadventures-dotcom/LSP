import SpriteKit
import SwiftUI

/// The flight screen: world view, HUD, and the touch controls.
///
/// The layout adapts to the size class. On an iPhone the readouts stack into a narrow
/// column and the controls hug the bottom corners where thumbs already are; on an iPad
/// the same clusters spread into the margins so nothing sits over the rocket.
struct FlightView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var model: FlightModel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase

    @State private var scene = FlightScene(size: CGSize(width: 800, height: 600))
    @State private var throttle: Double = 0
    @State private var rotation: Double = 0
    @State private var showStaging = false
    @State private var showMenu = false
    @State private var showManeuverPanel = false

    private var isCompact: Bool { horizontalSizeClass == .compact }

    var body: some View {
        ZStack {
            worldLayer
            if model.showMap {
                MapView(model: model, system: .shared)
                    .transition(.opacity)
            }
            hudLayer
            if let banner = model.banner {
                bannerView(banner)
            }
            if model.simulator.vessel.situation == .destroyed {
                failureOverlay
            }
        }
        .background(Color.black)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            scene.model = model
            scene.visuals = app.visualSettings
            throttle = model.simulator.vessel.throttle
        }
        .onChange(of: app.visualSettings) { _, settings in
            scene.visuals = settings
        }
        .onChange(of: scenePhase) { _, phase in
            model.setPaused(phase != .active)
        }
        .onChange(of: throttle) { _, value in
            model.setThrottle(value)
        }
        .onChange(of: rotation) { _, value in
            // The rocker already applies sensitivity and inversion.
            model.setRotation(value)
        }
        .sheet(isPresented: $showStaging) {
            StagingSheet(model: model)
        }
        .sheet(isPresented: $showMenu) {
            FlightMenuSheet(model: model, showMenu: $showMenu)
                .environmentObject(app)
        }
    }

    // MARK: - World

    private var worldLayer: some View {
        SpriteView(scene: scene, options: [.ignoresSiblingOrder])
            .ignoresSafeArea()
            .opacity(model.showMap ? 0 : 1)
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        scene.zoom(by: 1 + (value.magnification - 1) * 0.12)
                    }
            )
    }

    // MARK: - HUD

    private var hudLayer: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            bottomControls
        }
        .padding(.horizontal, isCompact ? 8 : 20)
        .padding(.vertical, 8)
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 8) {
            navigationReadouts
            Spacer(minLength: 0)
            if !isCompact { orbitReadouts }
            timeCluster
        }
    }

    private var navigationReadouts: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Readout(title: "Altitude", value: Units.distance(model.hud.altitude), size: 16)
                Readout(title: "Speed",
                        value: Units.speed(model.hud.isAtmospheric
                                           ? model.hud.surfaceSpeed : model.hud.orbitalSpeed),
                        size: 16)
                Readout(title: "Vert",
                        value: Units.speed(model.hud.verticalSpeed),
                        tint: model.hud.verticalSpeed < -1 ? Theme.warning : .white,
                        size: 16)
            }
            if isCompact {
                HStack(spacing: 10) {
                    Readout(title: "Ap", value: model.hud.apoapsis.map(Units.distance) ?? "—",
                            tint: Theme.accent, size: 13)
                    Readout(title: "Pe", value: Units.distance(model.hud.periapsis),
                            tint: model.hud.periapsis < 0 ? Theme.danger : Theme.accent, size: 13)
                }
            }
            HStack(spacing: 6) {
                Text(model.hud.situation.label)
                Text("·")
                Text(model.hud.bodyName)
                if model.hud.crew > 0 {
                    Text("·")
                    Label("\(model.hud.crew)", systemImage: "person.fill")
                        .labelStyle(.titleAndIcon)
                }
            }
            .font(Theme.label(11))
            .foregroundStyle(Theme.dim)
        }
        .padding(10)
        .panel()
        .frame(maxWidth: isCompact ? 230 : 320, alignment: .leading)
    }

    private var orbitReadouts: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Readout(title: "Apoapsis", value: model.hud.apoapsis.map(Units.distance) ?? "—",
                        tint: Theme.accent, size: 14)
                Readout(title: "T to Ap",
                        value: model.hud.timeToApoapsis.map(Units.shortDuration) ?? "—", size: 14)
            }
            HStack(spacing: 12) {
                Readout(title: "Periapsis", value: Units.distance(model.hud.periapsis),
                        tint: model.hud.periapsis < 0 ? Theme.danger : Theme.accent, size: 14)
                Readout(title: "T to Pe",
                        value: model.hud.timeToPeriapsis.map(Units.shortDuration) ?? "—", size: 14)
            }
            if app.showAdvancedReadouts {
                HStack(spacing: 12) {
                    Readout(title: "TWR", value: String(format: "%.2f", model.hud.twr), size: 14)
                    Readout(title: "Stage ΔV",
                            value: String(format: "%.0f m/s", model.hud.stageDeltaV), size: 14)
                    Readout(title: "Mass", value: Units.mass(model.hud.mass), size: 14)
                }
            }
        }
        .padding(10)
        .panel()
        .frame(maxWidth: 380)
    }

    private var timeCluster: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("T+ \(Units.duration(model.hud.missionTime))")
                .font(Theme.readout(13))
            HStack(spacing: 6) {
                HUDButton(systemImage: "backward.fill", enabled: model.warpIndex > 0) {
                    model.changeWarp(by: -1)
                }
                Text(model.hud.warpFactor < 10
                     ? String(format: "%.0fx", model.hud.warpFactor)
                     : "\(Int(model.hud.warpFactor))x")
                    .font(Theme.readout(13))
                    .frame(minWidth: 52)
                    .foregroundStyle(model.warpIndex > 0 ? Theme.warning : .white)
                HUDButton(systemImage: "forward.fill") {
                    model.changeWarp(by: 1)
                }
            }
            HStack(spacing: 6) {
                HUDButton(systemImage: model.showMap ? "globe.europe.africa.fill" : "map.fill",
                          title: model.showMap ? "Ship" : "Map",
                          active: model.showMap) {
                    withAnimation(.easeInOut(duration: 0.18)) { model.showMap.toggle() }
                }
                HUDButton(systemImage: "line.3.horizontal", title: "Menu") {
                    showMenu = true
                }
            }
        }
        .padding(10)
        .panel()
    }

    // MARK: - Bottom controls

    private var bottomControls: some View {
        HStack(alignment: .bottom, spacing: isCompact ? 10 : 22) {
            if app.leftHanded { rightCluster } else { leftCluster }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                RotationRocker(value: $rotation,
                               sensitivity: app.controlSensitivity,
                               inverted: app.invertPitch)
                    .frame(maxWidth: isCompact ? 240 : 380)
                sasRow
            }
            Spacer(minLength: 0)
            if app.leftHanded { leftCluster } else { rightCluster }
        }
    }

    private var leftCluster: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavballView(hud: model.hud, size: isCompact ? 104 : 136)
            ThrottleControl(value: $throttle, height: isCompact ? 150 : 200)
        }
    }

    private var rightCluster: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(spacing: 8) {
                HUDButton(systemImage: "list.bullet.rectangle", title: "Stages") {
                    showStaging = true
                }
                HUDButton(systemImage: "umbrella.fill", title: "Chutes",
                          tint: Theme.warning) {
                    model.deployChutes()
                }
            }
            fuelGauge
            StageButton(enabled: model.simulator.canStage,
                        stagesRemaining: model.hud.stagesRemaining) {
                model.stage()
            }
        }
    }

    private var sasRow: some View {
        HStack(spacing: 6) {
            ForEach([SASMode.stability, .prograde, .retrograde, .radialOut, .radialIn],
                    id: \.self) { mode in
                HUDButton(systemImage: mode.symbol, title: mode.label,
                          tint: Theme.accent, active: model.sasMode == mode) {
                    model.cycleSAS(to: mode)
                }
            }
        }
    }

    private var fuelGauge: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("FUEL")
                .font(Theme.label(9))
                .foregroundStyle(Theme.dim)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.5))
                Capsule()
                    .fill(model.hud.fuelFraction < 0.12 ? Theme.danger : Theme.success)
                    .frame(width: max(2, 110 * model.hud.fuelFraction))
            }
            .frame(width: 110, height: 9)
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .accessibilityLabel("Fuel remaining")
        .accessibilityValue("\(Int(model.hud.fuelFraction * 100)) percent")
    }

    // MARK: - Overlays

    private func bannerView(_ banner: FlightModel.BannerMessage) -> some View {
        VStack {
            Spacer()
            Text(banner.text)
                .font(Theme.label(15).weight(.semibold))
                .foregroundStyle(banner.isFailure ? Theme.danger : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .panel(cornerRadius: 12)
                .padding(.bottom, 200)
            Spacer().frame(height: 0)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
        .task(id: banner.id) {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if model.banner?.id == banner.id { model.banner = nil }
        }
    }

    private var failureOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.danger)
            Text("Vessel lost")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            if let reason = model.simulator.vessel.failureReason {
                Text(reason)
                    .font(Theme.label(14))
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button("Revert to launch") { app.revertToLaunch() }
                    .buttonStyle(.borderedProminent)
                Button("Back to base") { app.endFlight(saving: false) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(28)
        .panel(cornerRadius: 20)
        .padding(40)
    }
}

/// Staging list. Up/down buttons rather than drag-to-reorder: far easier to hit on a
/// phone, and it works one-handed.
struct StagingSheet: View {
    @ObservedObject var model: FlightModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(stages, id: \.index) { stage in
                        HStack(spacing: 12) {
                            Text("\(stage.index + 1)")
                                .font(Theme.readout(15))
                                .frame(width: 26)
                                .foregroundStyle(stage.index < model.hud.currentStage
                                                 ? Theme.dim : Theme.warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stage.summary)
                                    .font(Theme.label(14))
                                Text(stage.detail)
                                    .font(Theme.label(11))
                                    .foregroundStyle(Theme.dim)
                            }
                            Spacer()
                            if stage.index < model.hud.currentStage {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.dim)
                            }
                        }
                    }
                } header: {
                    Text("Staging sequence")
                } footer: {
                    Text("Stages fire from the top down. The next one to fire is highlighted.")
                }
            }
            .navigationTitle("Stages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private struct StageRow {
        let index: Int
        let summary: String
        let detail: String
    }

    private var stages: [StageRow] {
        let design = model.simulator.vessel.design
        let analysis = DesignAnalysis(design: design)
        return (0..<design.stageCount).map { index in
            let parts = design.activatedParts(inStage: index)
            let names = parts.compactMap { $0.definition?.name }
            let summary = names.isEmpty ? "Empty stage" : names.joined(separator: ", ")
            let stat = analysis.stages.first { $0.index == index }
            let detail = stat.map {
                String(format: "%.0f m/s · TWR %.2f · %.0f s burn",
                       $0.deltaVVacuum, $0.liftoffTWR, $0.burnTime)
            } ?? "No engines"
            return StageRow(index: index, summary: summary, detail: detail)
        }
    }
}

/// Pause menu.
struct FlightMenuSheet: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var model: FlightModel
    @Binding var showMenu: Bool

    var body: some View {
        NavigationStack {
            List {
                Section("Mission") {
                    LabeledContent("Vessel", value: model.simulator.vessel.name)
                    LabeledContent("Mission time", value: Units.duration(model.hud.missionTime))
                    LabeledContent("Situation", value: model.hud.situation.label)
                    LabeledContent("Body", value: model.hud.bodyName)
                }
                Section {
                    Button {
                        showMenu = false
                        app.revertToLaunch()
                    } label: {
                        Label("Revert to launch", systemImage: "arrow.counterclockwise")
                    }
                    Button {
                        showMenu = false
                        app.endFlight(saving: true)
                    } label: {
                        Label("Save and exit to base", systemImage: "tray.and.arrow.down.fill")
                    }
                    Button(role: .destructive) {
                        showMenu = false
                        app.endFlight(saving: false)
                    } label: {
                        Label("Abandon mission", systemImage: "xmark.circle")
                    }
                }
                Section {
                    NavigationLink {
                        SettingsView()
                            .environmentObject(app)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("Flight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Resume") { showMenu = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
