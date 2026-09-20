import Foundation

enum Units {
    /// Standard gravity, used for the Isp -> exhaust-velocity conversion.
    static let g0: Double = 9.80665

    /// Formats a distance with an automatic m / km / Mm / Gm suffix.
    static func distance(_ meters: Double) -> String {
        let m = abs(meters)
        if m < 1_000 { return String(format: "%.0f m", meters) }
        if m < 1_000_000 { return String(format: "%.2f km", meters / 1_000) }
        if m < 1_000_000_000 { return String(format: "%.3f Mm", meters / 1_000_000) }
        return String(format: "%.3f Gm", meters / 1_000_000_000)
    }

    static func speed(_ mps: Double) -> String {
        abs(mps) < 1_000
            ? String(format: "%.1f m/s", mps)
            : String(format: "%.2f km/s", mps / 1_000)
    }

    static func mass(_ kg: Double) -> String {
        abs(kg) < 1_000
            ? String(format: "%.0f kg", kg)
            : String(format: "%.2f t", kg / 1_000)
    }

    static func force(_ newtons: Double) -> String {
        abs(newtons) < 1_000
            ? String(format: "%.0f N", newtons)
            : String(format: "%.1f kN", newtons / 1_000)
    }

    /// Formats a duration as `1y 24d 03:12:45`, dropping empty leading fields.
    /// Uses this universe's 6-hour day and 426-day year, like the in-game clock.
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "--" }
        let sign = seconds < 0 ? "-" : ""
        var s = Int(abs(seconds).rounded())
        let year = 426 * 6 * 3600
        let day = 6 * 3600
        let y = s / year; s -= y * year
        let d = s / day; s -= d * day
        let h = s / 3600; s -= h * 3600
        let m = s / 60; s -= m * 60
        let clock = String(format: "%02d:%02d:%02d", h, m, s)
        if y > 0 { return "\(sign)\(y)y \(d)d \(clock)" }
        if d > 0 { return "\(sign)\(d)d \(clock)" }
        return "\(sign)\(clock)"
    }

    /// Short countdown form used on burn timers: `T-01:23`.
    static func shortDuration(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--" }
        var s = Int(abs(seconds).rounded())
        let h = s / 3600; s -= h * 3600
        let m = s / 60; s -= m * 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}
