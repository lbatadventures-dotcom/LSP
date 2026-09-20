import SwiftUI

/// The space centre. Everything starts here: resume a flight, pick a rocket, or build one.
struct MainMenuView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showSettings = false
    @State private var confirmDelete: VesselDesign? = nil

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .compact ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 14), count: count)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.05, green: 0.08, blue: 0.16),
                                        Color(red: 0.02, green: 0.03, blue: 0.06)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        if app.hasSavedFlight {
                            Button {
                                app.resumeFlight()
                            } label: {
                                HStack {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 26))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Resume flight")
                                            .font(Theme.label(16).weight(.semibold))
                                        Text("Pick up the mission in progress")
                                            .font(Theme.label(12))
                                            .foregroundStyle(Theme.dim)
                                    }
                                    Spacer()
                                }
                                .padding(14)
                                .panel()
                                .foregroundStyle(Theme.success)
                            }
                            .buttonStyle(.plain)
                        }

                        HStack {
                            Text("Rockets")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                            Spacer()
                            Button {
                                app.newDesign()
                            } label: {
                                Label("New", systemImage: "plus")
                                    .font(Theme.label(14).weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .frame(height: Theme.minimumTouchTarget)
                                    .background(Capsule().fill(Theme.accent))
                                    .foregroundStyle(.black)
                            }
                            .buttonStyle(.plain)
                        }
                        .foregroundStyle(.white)

                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(app.craft) { design in
                                craftCard(design)
                            }
                        }

                        missionBriefing
                    }
                    .padding(18)
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView().environmentObject(app)
                }
            }
            .alert("Delete rocket?", isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let d = confirmDelete { app.delete(d) }
                    confirmDelete = nil
                }
                Button("Cancel", role: .cancel) { confirmDelete = nil }
            } message: {
                Text(confirmDelete?.name ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Little Space Program")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("Build a rocket. Fly it yourself. Try not to lose the crew.")
                .font(Theme.label(14))
                .foregroundStyle(Theme.dim)
        }
        .padding(.top, 8)
    }

    private func craftCard(_ design: VesselDesign) -> some View {
        let analysis = DesignAnalysis(design: design)
        return HStack(spacing: 14) {
            CraftThumbnail(design: design)
                .frame(width: 64, height: 108)

            VStack(alignment: .leading, spacing: 5) {
                Text(design.name)
                    .font(Theme.label(17).weight(.semibold))
                    .foregroundStyle(.white)
                HStack(spacing: 12) {
                    stat("ΔV", String(format: "%.0f", analysis.totalDeltaV),
                         analysis.totalDeltaV >= 3_400 ? Theme.success : Theme.warning)
                    stat("Mass", Units.mass(analysis.totalMass), .white)
                    stat("Stages", "\(analysis.stages.count)", .white)
                }
                HStack(spacing: 8) {
                    Button {
                        app.launch(design)
                    } label: {
                        Label("Launch", systemImage: "paperplane.fill")
                            .font(Theme.label(13).weight(.bold))
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(Capsule().fill(Theme.success))
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)

                    Button {
                        app.edit(design)
                    } label: {
                        Label("Edit", systemImage: "wrench.and.screwdriver.fill")
                            .font(Theme.label(13))
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        confirmDelete = design
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                            .foregroundStyle(Theme.danger)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .panel()
    }

    private func stat(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(Theme.label(9))
                .foregroundStyle(Theme.dim)
            Text(value)
                .font(Theme.readout(13))
                .foregroundStyle(tint)
        }
    }

    private var missionBriefing: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Flight notes")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            ForEach(MainMenuView.tips, id: \.self) { tip in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .padding(.top, 6)
                    Text(tip).font(Theme.label(13))
                }
                .foregroundStyle(Theme.dim)
            }
        }
        .padding(14)
        .panel()
    }

    private static let tips = [
        "Go straight up to about 10 km, then tip east by roughly 45°. Gravity does the rest of the turn for you.",
        "Orbit means a periapsis above 70 km, not just altitude. Keep burning sideways until the low point clears the atmosphere.",
        "Time warp only works outside the atmosphere and with the engines off.",
        "Parachutes tear off above 350 m/s. Let the air slow you down first.",
        "Fins belong at the bottom. A rocket flips when its centre of pressure sits ahead of its centre of mass."
    ]
}

/// Scaled-down drawing of a whole rocket, used on the craft cards.
struct CraftThumbnail: View {
    let design: VesselDesign

    var body: some View {
        Canvas { context, size in
            let b = design.bounds
            let w = max(b.max.x - b.min.x, 1)
            let h = max(b.max.y - b.min.y, 1)
            let scale = min(size.width / w, size.height / h) * 0.9
            let cx = (b.min.x + b.max.x) / 2
            let cy = (b.min.y + b.max.y) / 2

            context.drawLayer { layer in
                layer.translateBy(x: size.width / 2, y: size.height / 2)
                layer.scaleBy(x: scale, y: -scale)
                layer.translateBy(x: -cx, y: -cy)
                for part in design.parts.sorted(by: { $0.attachKind == .radial && $1.attachKind != .radial }) {
                    guard let def = part.definition else { continue }
                    layer.drawLayer { partLayer in
                        partLayer.translateBy(x: part.position.x, y: part.position.y)
                        if part.side < 0 { partLayer.scaleBy(x: -1, y: 1) }
                        for pl in PartGeometry.layers(for: def) {
                            let path = Path(pl.path)
                            if let fill = pl.fill { partLayer.fill(path, with: .color(fill)) }
                        }
                    }
                }
            }
        }
    }
}
