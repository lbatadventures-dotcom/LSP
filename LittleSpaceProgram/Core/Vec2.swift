import CoreGraphics
import Foundation

/// A double-precision 2D vector. All simulation math runs in `Double`;
/// conversion to `CGFloat` happens only at the rendering boundary.
struct Vec2: Equatable, Codable {
    var x: Double
    var y: Double

    init(_ x: Double = 0, _ y: Double = 0) {
        self.x = x
        self.y = y
    }

    static let zero = Vec2(0, 0)

    /// Unit vector at `angle` radians counter-clockwise from +x, scaled by `length`.
    static func polar(angle: Double, length: Double = 1) -> Vec2 {
        Vec2(cos(angle) * length, sin(angle) * length)
    }

    var length: Double { (x * x + y * y).squareRoot() }
    var lengthSquared: Double { x * x + y * y }
    var angle: Double { atan2(y, x) }

    var normalized: Vec2 {
        let l = length
        return l > 1e-12 ? Vec2(x / l, y / l) : .zero
    }

    /// Rotated 90 degrees counter-clockwise.
    var perpendicular: Vec2 { Vec2(-y, x) }

    func dot(_ o: Vec2) -> Double { x * o.x + y * o.y }

    /// The z component of the 3D cross product; positive when `o` is CCW of `self`.
    func cross(_ o: Vec2) -> Double { x * o.y - y * o.x }

    func rotated(by a: Double) -> Vec2 {
        let c = cos(a), s = sin(a)
        return Vec2(x * c - y * s, x * s + y * c)
    }

    /// Signed angle from `self` to `o`, in (-pi, pi].
    func signedAngle(to o: Vec2) -> Double {
        atan2(cross(o), dot(o))
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }

    static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
    static func * (s: Double, a: Vec2) -> Vec2 { Vec2(a.x * s, a.y * s) }
    static func / (a: Vec2, s: Double) -> Vec2 { Vec2(a.x / s, a.y / s) }
    static prefix func - (a: Vec2) -> Vec2 { Vec2(-a.x, -a.y) }
    static func += (a: inout Vec2, b: Vec2) { a = a + b }
    static func -= (a: inout Vec2, b: Vec2) { a = a - b }
    static func *= (a: inout Vec2, s: Double) { a = a * s }
}

enum MathUtil {
    /// Wraps an angle into (-pi, pi].
    static func wrapAngle(_ a: Double) -> Double {
        var r = fmod(a + .pi, 2 * .pi)
        if r < 0 { r += 2 * .pi }
        return r - .pi
    }

    /// Wraps an angle into [0, 2pi).
    static func wrapAngle2Pi(_ a: Double) -> Double {
        var r = fmod(a, 2 * .pi)
        if r < 0 { r += 2 * .pi }
        return r
    }

    static func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
        min(hi, max(lo, v))
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * clamp(t, 0, 1)
    }

    /// Maps `v` from [inLo, inHi] to [outLo, outHi], clamped.
    static func remap(_ v: Double, _ inLo: Double, _ inHi: Double, _ outLo: Double, _ outHi: Double) -> Double {
        guard inHi != inLo else { return outLo }
        return lerp(outLo, outHi, (v - inLo) / (inHi - inLo))
    }
}
