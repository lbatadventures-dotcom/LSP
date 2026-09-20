import SwiftUI

/// Attitude indicator.
///
/// In a flat universe there is a single rotation axis, so the instrument shows the
/// nose fixed at twelve o'clock and rotates the world around it: sky and ground swing
/// as the rocket pitches over, and the velocity markers sit where you would look for
/// them on a navball.
struct NavballView: View {
    let hud: HUDSnapshot
    var size: CGFloat = 128

    /// Angle of the local "up" direction in instrument space, radians CCW from the top.
    private var worldRotation: Double {
        (hud.pitch - 90) * .pi / 180
    }

    private func markerAngle(_ worldAngle: Double) -> Double {
        MathUtil.wrapAngle(worldAngle - hud.heading)
    }

    var body: some View {
        ZStack {
            Canvas { context, canvasSize in
                let r = min(canvasSize.width, canvasSize.height) / 2
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let disc = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r,
                                                  width: r * 2, height: r * 2))
                context.clip(to: disc)

                // Sky and ground, rotated so "up" always points away from the planet.
                context.drawLayer { layer in
                    layer.translateBy(x: center.x, y: center.y)
                    // SwiftUI's y axis runs down, so a counter-clockwise world rotation
                    // is a clockwise rotation on screen.
                    layer.rotate(by: .radians(-worldRotation))
                    let big = r * 2.4
                    layer.fill(Path(CGRect(x: -big, y: -big, width: big * 2, height: big)),
                               with: .color(Color(red: 0.22, green: 0.46, blue: 0.78)))
                    layer.fill(Path(CGRect(x: -big, y: 0, width: big * 2, height: big)),
                               with: .color(Color(red: 0.42, green: 0.32, blue: 0.22)))
                    layer.stroke(Path { p in
                        p.move(to: CGPoint(x: -big, y: 0))
                        p.addLine(to: CGPoint(x: big, y: 0))
                    }, with: .color(.white.opacity(0.85)), lineWidth: 1.5)

                    // Pitch ladder every 30 degrees.
                    for step in stride(from: -60.0, through: 60.0, by: 30.0) where step != 0 {
                        let y = -r * (step / 90)
                        let w = r * 0.32
                        layer.stroke(Path { p in
                            p.move(to: CGPoint(x: -w, y: y))
                            p.addLine(to: CGPoint(x: w, y: y))
                        }, with: .color(.white.opacity(0.35)), lineWidth: 1)
                    }
                }

                context.stroke(disc, with: .color(.white.opacity(0.35)), lineWidth: 1.5)
            }

            // Velocity and radial markers ride the rim.
            markers(radius: size / 2 - 16)

            // Fixed nose reference.
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.warning)
                .offset(y: -size / 2 + 5)

            VStack {
                Spacer()
                Text(String(format: "%.0f°", hud.pitch))
                    .font(Theme.readout(12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .padding(.bottom, 6)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Attitude")
        .accessibilityValue(String(format: "Pitch %.0f degrees", hud.pitch))
    }

    @ViewBuilder
    private func markers(radius: CGFloat) -> some View {
        ZStack {
            marker("Pro", angle: markerAngle(hud.progradeAngle), radius: radius,
                   color: Theme.success, symbol: "circle.circle")
            marker("Ret", angle: markerAngle(hud.retrogradeAngle), radius: radius,
                   color: Theme.danger, symbol: "xmark.circle")
            marker("Up", angle: markerAngle(hud.radialAngle), radius: radius,
                   color: Theme.accent.opacity(0.8), symbol: "arrowtriangle.up.circle")
        }
    }

    private func marker(_ name: String, angle: Double, radius: CGFloat,
                        color: Color, symbol: String) -> some View {
        // Instrument angle 0 is straight up, increasing counter-clockwise.
        let x = -sin(angle) * Double(radius)
        let y = -cos(angle) * Double(radius)
        return Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(color)
            .shadow(color: .black.opacity(0.7), radius: 2)
            .offset(x: x, y: y)
            .accessibilityHidden(true)
    }
}
