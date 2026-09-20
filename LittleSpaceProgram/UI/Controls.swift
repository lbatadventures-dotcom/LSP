import SwiftUI

/// Vertical throttle. Sized for a thumb and draggable from anywhere along its length,
/// rather than requiring a hit on a small knob.
struct ThrottleControl: View {
    @Binding var value: Double
    var height: CGFloat = 200

    @State private var dragStart: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.45))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(colors: [Theme.accent.opacity(0.75), Theme.warning],
                                       startPoint: .bottom, endPoint: .top)
                    )
                    .frame(height: max(4, h * value))
                VStack {
                    Text("\(Int((value * 100).rounded()))")
                        .font(Theme.readout(13))
                        .foregroundStyle(.white)
                        .padding(.top, 6)
                    Spacer()
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if dragStart == nil { dragStart = value }
                        let fraction = 1 - (g.location.y / h)
                        value = MathUtil.clamp(Double(fraction), 0, 1)
                    }
                    .onEnded { _ in dragStart = nil }
            )
        }
        .frame(width: 54, height: height)
        .accessibilityLabel("Throttle")
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAdjustableAction { direction in
            value = MathUtil.clamp(value + (direction == .increment ? 0.1 : -0.1), 0, 1)
        }
    }
}

/// Horizontal rocker for pitch. There is only one rotation axis in a flat universe,
/// so a rocker beats a thumbstick: it is easier to hold at a steady deflection.
struct RotationRocker: View {
    @Binding var value: Double
    var sensitivity: Double = 1
    var inverted: Bool = false

    @State private var active = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                Capsule().fill(Color.black.opacity(0.45))
                Capsule().strokeBorder(Theme.hairline, lineWidth: 1)
                // Centre detent.
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(width: 1, height: geo.size.height * 0.5)
                Capsule()
                    .fill(active ? Theme.accent : Theme.accent.opacity(0.7))
                    .frame(width: 46, height: geo.size.height - 10)
                    .offset(x: CGFloat(value) * (w / 2 - 26))
                    .animation(active ? nil : .spring(response: 0.25, dampingFraction: 0.7),
                               value: value)
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Spacer()
                    Image(systemName: "arrow.clockwise")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.dim)
                .padding(.horizontal, 12)
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        active = true
                        let centred = (g.location.x - w / 2) / (w / 2)
                        let raw = MathUtil.clamp(Double(centred) * sensitivity, -1, 1)
                        value = inverted ? -raw : raw
                    }
                    .onEnded { _ in
                        active = false
                        value = 0
                    }
            )
        }
        .frame(height: 56)
        .accessibilityLabel("Rotation")
    }
}

/// Square HUD button with a consistent hit target.
struct HUDButton: View {
    let systemImage: String
    var title: String?
    var tint: Color = .white
    var active: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                if let title {
                    Text(title)
                        .font(Theme.label(9))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(enabled ? (active ? Color.black : tint) : Theme.dim)
            .frame(minWidth: Theme.minimumTouchTarget, minHeight: Theme.minimumTouchTarget)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(active ? tint : Color.black.opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(title ?? systemImage)
    }
}

/// The big one. Staging is the action players reach for under pressure, so it gets
/// the largest target on screen and a colour nothing else uses.
struct StageButton: View {
    var enabled: Bool
    var stagesRemaining: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 22, weight: .bold))
                Text("STAGE")
                    .font(Theme.label(11).weight(.heavy))
                if stagesRemaining > 0 {
                    Text("\(stagesRemaining) left")
                        .font(Theme.label(9))
                        .opacity(0.8)
                }
            }
            .foregroundStyle(enabled ? Color.black : Theme.dim)
            .frame(width: 78, height: 78)
            .background(
                Circle().fill(enabled
                    ? LinearGradient(colors: [Theme.warning, Theme.danger],
                                     startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [Color.black.opacity(0.45), Color.black.opacity(0.45)],
                                     startPoint: .top, endPoint: .bottom))
            )
            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("Activate next stage")
    }
}
