import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Form {
            Section("Controls") {
                Toggle("Left-handed layout", isOn: $app.leftHanded)
                Toggle("Invert rotation", isOn: $app.invertPitch)
                VStack(alignment: .leading) {
                    HStack {
                        Text("Sensitivity")
                        Spacer()
                        Text(String(format: "%.1fx", app.controlSensitivity))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $app.controlSensitivity, in: 0.4...2.0, step: 0.1)
                }
                Toggle("Haptics", isOn: $app.hapticsEnabled)
            }
            Section("Display") {
                Toggle("Advanced readouts", isOn: $app.showAdvancedReadouts)
                Toggle("Reduce effects", isOn: $app.reduceEffects)
            } footer: {
                Text("Reduce effects thins out exhaust particles and starfields. Worth turning on for longer sessions on battery.")
            }
            Section("Universe") {
                ForEach(SolarSystem.shared.bodies) { body in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(body.name).font(.headline)
                        Text(bodyDetail(body))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: app.hapticsEnabled) { _, _ in
            app.applySettingsToFlight()
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func bodyDetail(_ body: CelestialBody) -> String {
        var parts = [
            "Radius \(Units.distance(body.radius))",
            String(format: "Surface gravity %.2f m/s²", body.surfaceGravity)
        ]
        if let atmo = body.atmosphere {
            parts.append("Atmosphere to \(Units.distance(atmo.height))")
        } else {
            parts.append("No atmosphere")
        }
        parts.append(String(format: "Low orbit %.0f m/s",
                            body.circularOrbitSpeed(atAltitude: body.minimumSafeOrbitAltitude)))
        return parts.joined(separator: " · ")
    }
}
