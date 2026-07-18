// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Copyright © 2016 - 2026 Stefan Berg <isbeorn86+NINA@googlemail.com> and the N.I.N.A. contributors
// Ported from NINA.Astrometry to Swift for ARESCore.

import Foundation

/// An immutable angle value type supporting Degree/Radians/Hours representations
/// and common trigonometric operations.
@available(macOS 13.0, *)
public struct Angle: Equatable, Hashable, Sendable {

    // MARK: - Stored properties

    public let degree: Double
    public let radians: Double
    public let hours: Double

    // MARK: - Computed properties

    public var arcMinutes: Double { degree * 60.0 }
    public var arcSeconds: Double { arcMinutes * 60.0 }

    // MARK: - Factory methods

    public static func byHours(_ hours: Double) -> Angle {
        let deg = AstroUtil.hoursToDegrees(hours)
        return Angle(degree: deg, radians: AstroUtil.toRadians(deg), hours: hours)
    }

    public static func byDegree(_ degree: Double) -> Angle {
        Angle(degree: degree, radians: AstroUtil.toRadians(degree), hours: AstroUtil.degreesToHours(degree))
    }

    public static func byRadians(_ radians: Double) -> Angle {
        let deg = AstroUtil.toDegree(radians)
        Angle(degree: deg, radians: radians, hours: AstroUtil.degreesToHours(deg))
    }

    public static let zero = Angle.byDegree(0)

    // MARK: - Private init

    private init(degree: Double, radians: Double, hours: Double) {
        self.degree = degree
        self.radians = radians
        self.hours = hours
    }

    // MARK: - Trig operations

    public func sin() -> Angle { .byRadians(Foundation.sin(self.radians)) }
    public func asin() -> Angle { .byRadians(Foundation.asin(self.radians)) }
    public func cos() -> Angle { .byRadians(Foundation.cos(self.radians)) }
    public func acos() -> Angle { .byRadians(Foundation.acos(self.radians)) }
    public func atan() -> Angle { .byRadians(Foundation.atan(self.radians)) }
    public func abs() -> Angle { .byRadians(Swift.abs(self.radians)) }

    public func atan2(_ angle: Angle) -> Angle {
        .byRadians(Foundation.atan2(self.radians, angle.radians))
    }

    public static func atan2(_ y: Angle, _ x: Angle) -> Angle {
        .byRadians(Foundation.atan2(y.radians, x.radians))
    }

    // MARK: - Equality with tolerance

    private static let equalsEpsilon = 1e-13

    public func equals(_ that: Angle, tolerance: Angle) -> Bool {
        let thisDeg = AstroUtil.euclidianModulus(self.degree, 360.0)
        let thatDeg = AstroUtil.euclidianModulus(that.degree, 360.0)
        let diffDeg = Swift.abs(thisDeg - thatDeg)
        let tolDeg = AstroUtil.euclidianModulus(tolerance.degree, 360.0)
        return (diffDeg - tolDeg) <= Self.equalsEpsilon
            || ((360.0 - diffDeg) - tolDeg) <= Self.equalsEpsilon
    }

    public func equals(_ that: Angle, tolerance: Angle, oneEightyIsEqual: Bool) -> Bool {
        if !oneEightyIsEqual { return equals(that, tolerance: tolerance) }
        let thisDeg = AstroUtil.euclidianModulus(self.degree, 180.0)
        let thatDeg = AstroUtil.euclidianModulus(that.degree, 180.0)
        let diffDeg = Swift.abs(thisDeg - thatDeg)
        let tolDeg = AstroUtil.euclidianModulus(tolerance.degree, 180.0)
        return (diffDeg - tolDeg) <= Self.equalsEpsilon
            || ((180.0 - diffDeg) - tolDeg) <= Self.equalsEpsilon
    }

    // MARK: - Copy

    public func copy() -> Angle { .byRadians(self.radians) }
    public func copyByDegree() -> Angle { .byDegree(self.degree) }

    // MARK: - Description

    public var description: String { AstroUtil.degreesToDMS(degree) }

    // MARK: - Operators

    public static prefix func - (a: Angle) -> Angle { .byRadians(-a.radians) }

    public static func + (a: Angle, b: Angle) -> Angle { .byRadians(a.radians + b.radians) }
    public static func + (a: Double, b: Angle) -> Angle { .byRadians(a + b.radians) }
    public static func + (a: Angle, b: Double) -> Angle { .byRadians(a.radians + b) }

    public static func - (a: Angle, b: Angle) -> Angle { .byRadians(a.radians - b.radians) }
    public static func - (a: Double, b: Angle) -> Angle { .byRadians(a - b.radians) }
    public static func - (a: Angle, b: Double) -> Angle { .byRadians(a.radians - b) }

    public static func * (a: Angle, b: Angle) -> Angle { .byRadians(a.radians * b.radians) }
    public static func * (a: Double, b: Angle) -> Angle { .byRadians(a * b.radians) }

    public static func / (a: Angle, b: Angle) -> Angle { .byRadians(a.radians / b.radians) }
    public static func / (a: Angle, b: Double) -> Angle { .byRadians(a.radians / b) }
    public static func / (a: Double, b: Angle) -> Angle { .byRadians(a / b.radians) }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(degree)
        hasher.combine(radians)
        hasher.combine(hours)
    }
}