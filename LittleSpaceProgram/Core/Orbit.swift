import Foundation

/// A two-body Keplerian orbit in a plane, expressed in a body-centred inertial frame.
///
/// Retrograde (clockwise) orbits are handled by mirroring the state vectors about the
/// x axis on the way in and on the way out, so the element solver only ever has to deal
/// with the counter-clockwise case.
struct Orbit {
    let mu: Double
    /// Semi-major axis. Negative for hyperbolic trajectories.
    let semiMajorAxis: Double
    let eccentricity: Double
    /// Argument of periapsis, measured in the un-mirrored (counter-clockwise) frame.
    let argumentOfPeriapsis: Double
    let meanAnomalyAtEpoch: Double
    let epoch: Double
    /// True when the vessel travels clockwise (negative specific angular momentum).
    let clockwise: Bool

    // MARK: - Construction

    init(position pIn: Vec2, velocity vIn: Vec2, mu: Double, epoch: Double) {
        self.mu = mu
        self.epoch = epoch

        let cw = pIn.cross(vIn) < 0
        self.clockwise = cw

        // Mirror into the canonical counter-clockwise frame.
        let p = cw ? Vec2(pIn.x, -pIn.y) : pIn
        let v = cw ? Vec2(vIn.x, -vIn.y) : vIn

        let r = max(p.length, 1e-6)
        let v2 = v.lengthSquared
        let energy = v2 / 2 - mu / r
        var a = -mu / (2 * energy)

        let rv = p.dot(v)
        let k = v2 - mu / r
        let ev = (p * k - v * rv) / mu
        var e = ev.length

        // Exactly parabolic orbits have no usable mean-anomaly form; nudge off the singularity.
        if abs(e - 1) < 1e-9 {
            e = e < 1 ? 1 - 1e-9 : 1 + 1e-9
        }
        if !a.isFinite || abs(a) < 1e-6 {
            a = e < 1 ? r : -r
        }

        self.semiMajorAxis = a
        self.eccentricity = e

        let nu: Double
        if e > 1e-8 {
            self.argumentOfPeriapsis = atan2(ev.y, ev.x)
            let cosNu = MathUtil.clamp(ev.dot(p) / (e * r), -1, 1)
            nu = rv < 0 ? -acos(cosNu) : acos(cosNu)
        } else {
            // Circular: periapsis is undefined, so anchor it at +x.
            self.argumentOfPeriapsis = 0
            nu = atan2(p.y, p.x)
        }

        self.meanAnomalyAtEpoch = Orbit.meanAnomaly(trueAnomaly: nu, eccentricity: e)
    }

    /// Builds an orbit directly from elements (used when splicing predicted patches).
    init(mu: Double, semiMajorAxis: Double, eccentricity: Double, argumentOfPeriapsis: Double,
         meanAnomalyAtEpoch: Double, epoch: Double, clockwise: Bool) {
        self.mu = mu
        self.semiMajorAxis = semiMajorAxis
        self.eccentricity = eccentricity
        self.argumentOfPeriapsis = argumentOfPeriapsis
        self.meanAnomalyAtEpoch = meanAnomalyAtEpoch
        self.epoch = epoch
        self.clockwise = clockwise
    }

    // MARK: - Derived quantities

    var isClosed: Bool { eccentricity < 1 }
    var semiLatusRectum: Double { semiMajorAxis * (1 - eccentricity * eccentricity) }
    var periapsis: Double { semiMajorAxis * (1 - eccentricity) }
    /// Apoapsis radius, or nil for escape trajectories.
    var apoapsis: Double? { isClosed ? semiMajorAxis * (1 + eccentricity) : nil }
    var meanMotion: Double { (mu / pow(abs(semiMajorAxis), 3)).squareRoot() }
    var period: Double? { isClosed ? 2 * .pi / meanMotion : nil }

    /// Speed at a given radius, from the vis-viva equation.
    func speed(atRadius r: Double) -> Double {
        max(0, mu * (2 / r - 1 / semiMajorAxis)).squareRoot()
    }

    // MARK: - Anomaly conversions

    static func meanAnomaly(trueAnomaly nu: Double, eccentricity e: Double) -> Double {
        if e < 1 {
            let ecc = 2 * atan2((1 - e).squareRoot() * sin(nu / 2),
                                (1 + e).squareRoot() * cos(nu / 2))
            return ecc - e * sin(ecc)
        } else {
            let t = MathUtil.clamp(((e - 1) / (e + 1)).squareRoot() * tan(nu / 2),
                                   -1 + 1e-12, 1 - 1e-12)
            let h = 2 * atanh(t)
            return e * sinh(h) - h
        }
    }

    /// Newton iteration on Kepler's equation `M = E - e sin E`.
    private func eccentricAnomaly(meanAnomaly m: Double) -> Double {
        let e = eccentricity
        let mw = MathUtil.wrapAngle(m)
        var ecc = mw + e * sin(mw)
        for _ in 0..<60 {
            let f = ecc - e * sin(ecc) - mw
            let fp = 1 - e * cos(ecc)
            guard abs(fp) > 1e-14 else { break }
            let d = f / fp
            ecc -= d
            if abs(d) < 1e-13 { break }
        }
        return ecc
    }

    /// Newton iteration on the hyperbolic form `M = e sinh H - H`, with a damped step.
    private func hyperbolicAnomaly(meanAnomaly m: Double) -> Double {
        let e = eccentricity
        var h = abs(m) > 1 ? asinh(m / e) : m / (e - 1)
        for _ in 0..<100 {
            let f = e * sinh(h) - h - m
            let fp = e * cosh(h) - 1
            guard abs(fp) > 1e-14 else { break }
            let d = MathUtil.clamp(f / fp, -1, 1)
            h -= d
            if abs(d) < 1e-13 { break }
        }
        return h
    }

    func trueAnomaly(at t: Double) -> Double {
        let m = meanAnomalyAtEpoch + meanMotion * (t - epoch)
        if isClosed {
            let ecc = eccentricAnomaly(meanAnomaly: m)
            let e = eccentricity
            return 2 * atan2((1 + e).squareRoot() * sin(ecc / 2),
                             (1 - e).squareRoot() * cos(ecc / 2))
        } else {
            let h = hyperbolicAnomaly(meanAnomaly: m)
            let e = eccentricity
            return 2 * atan2((e + 1).squareRoot() * sinh(h / 2),
                             (e - 1).squareRoot() * cosh(h / 2))
        }
    }

    // MARK: - Propagation

    /// Position and velocity at absolute time `t`, in the body-centred inertial frame.
    func state(at t: Double) -> (position: Vec2, velocity: Vec2) {
        let m = meanAnomalyAtEpoch + meanMotion * (t - epoch)
        let a = semiMajorAxis
        let e = eccentricity

        var p: Vec2
        var v: Vec2
        if isClosed {
            let ecc = eccentricAnomaly(meanAnomaly: m)
            let ce = cos(ecc), se = sin(ecc)
            let r = max(a * (1 - e * ce), 1e-6)
            let b = (1 - e * e).squareRoot()
            p = Vec2(a * (ce - e), a * b * se)
            let f = (mu * a).squareRoot() / r
            v = Vec2(-f * se, f * b * ce)
        } else {
            let h = hyperbolicAnomaly(meanAnomaly: m)
            let ch = cosh(h), sh = sinh(h)
            let r = max(a * (1 - e * ch), 1e-6)
            let b = (e * e - 1).squareRoot()
            p = Vec2(a * (ch - e), -a * b * sh)
            let f = (mu * (-a)).squareRoot() / r
            v = Vec2(-f * sh, f * b * ch)
        }

        p = p.rotated(by: argumentOfPeriapsis)
        v = v.rotated(by: argumentOfPeriapsis)
        if clockwise {
            p.y = -p.y
            v.y = -v.y
        }
        return (p, v)
    }

    /// Position at a given true anomaly — used to trace the orbit path for the map view.
    func position(atTrueAnomaly nu: Double) -> Vec2 {
        let r = semiLatusRectum / (1 + eccentricity * cos(nu))
        var p = Vec2(r * cos(nu), r * sin(nu)).rotated(by: argumentOfPeriapsis)
        if clockwise { p.y = -p.y }
        return p
    }

    /// Absolute time at which the vessel next reaches `nu`, at or after `after`.
    func time(atTrueAnomaly nu: Double, after: Double) -> Double? {
        let m = Orbit.meanAnomaly(trueAnomaly: nu, eccentricity: eccentricity)
        var t = epoch + (m - meanAnomalyAtEpoch) / meanMotion
        if let p = period {
            let k = ((after - t) / p).rounded(.up)
            t += k * p
            return t
        }
        return t >= after ? t : nil
    }

    /// Next time the orbital radius equals `radius`, at or after `after`.
    /// Returns nil when the orbit never reaches that radius.
    func time(atRadius radius: Double, after: Double) -> Double? {
        guard radius > 0 else { return nil }
        if eccentricity < 1e-9 {
            // Circular: either always at that radius or never.
            return abs(semiMajorAxis - radius) < 1 ? after : nil
        }
        let c = (semiLatusRectum / radius - 1) / eccentricity
        guard c >= -1, c <= 1 else { return nil }
        let nu = acos(MathUtil.clamp(c, -1, 1))
        let candidates = [nu, -nu].compactMap { time(atTrueAnomaly: $0, after: after) }
        return candidates.min()
    }

    /// Time of the next apoapsis passage, for closed orbits only.
    func timeOfApoapsis(after t: Double) -> Double? {
        guard isClosed else { return nil }
        return time(atTrueAnomaly: .pi, after: t)
    }

    func timeOfPeriapsis(after t: Double) -> Double? {
        time(atTrueAnomaly: 0, after: t)
    }

    /// True anomaly at which the trajectory escapes to infinity (hyperbolic asymptote).
    var asymptoteTrueAnomaly: Double? {
        guard eccentricity > 1 else { return nil }
        return acos(MathUtil.clamp(-1 / eccentricity, -1, 1))
    }
}
