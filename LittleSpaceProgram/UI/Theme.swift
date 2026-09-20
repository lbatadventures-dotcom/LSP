import SwiftUI

/// One place for the colours and type used across the HUD and menus, so the whole
/// app reads as a single instrument panel.
enum Theme {
    static let accent = Color(red: 0.36, green: 0.80, blue: 0.98)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.24)
    static let danger = Color(red: 1.0, green: 0.38, blue: 0.36)
    static let success = Color(red: 0.42, green: 0.88, blue: 0.56)
    static let panel = Color(red: 0.06, green: 0.08, blue: 0.12).opacity(0.82)
    static let panelSolid = Color(red: 0.07, green: 0.09, blue: 0.13)
    static let hairline = Color.white.opacity(0.12)
    static let dim = Color.white.opacity(0.55)

    /// Tabular figures keep readouts from jittering as the digits change.
    static func readout(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }

    static func label(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    /// Smallest comfortable touch target. Everything interactive meets it.
    static let minimumTouchTarget: CGFloat = 44
}

/// Frosted panel used behind every HUD cluster.
struct PanelBackground: ViewModifier {
    var cornerRadius: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Theme.panel)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func panel(cornerRadius: CGFloat = 14) -> some View {
        modifier(PanelBackground(cornerRadius: cornerRadius))
    }
}

/// A label-over-value readout, the HUD's basic unit.
struct Readout: View {
    let title: String
    let value: String
    var tint: Color = .white
    var size: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(Theme.label(size * 0.62))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
            Text(value)
                .font(Theme.readout(size))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
