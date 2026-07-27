// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Copyright © 2016 - 2026 Stefan Berg <isbeorn86+NINA@googlemail.com> and the N.I.N.A. contributors
// Ported from NINA.Astrometry to Swift for ARESCore.

import Foundation

/// Abstract base for rise/set event calculations.
/// Uses a quadratic interpolation method to find rise/set times.
@available(macOS 13.0, *)
public class RiseAndSetEvent: Equatable, @unchecked Sendable {
    public let date: Date
    public let latitude: Double
    public let longitude: Double
    public let elevation: Double
    public var rise: Date?
    public var set: Date?

    public init(date: Date, latitude: Double, longitude: Double, elevation: Double = 0) {
        self.date = date
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
    }

    public static func == (lhs: RiseAndSetEvent, rhs: RiseAndSetEvent) -> Bool {
        guard type(of: lhs) == type(of: rhs) else { return false }
        return lhs.date == rhs.date &&
               lhs.latitude == rhs.latitude &&
               lhs.longitude == rhs.longitude &&
               lhs.elevation == rhs.elevation &&
               lhs.rise == rhs.rise &&
               lhs.set == rhs.set
    }

    /// Subclasses override to adjust body altitude for the specific event type
    /// (e.g. sun at -18° for astronomical twilight).
    open func adjustAltitude(body: BasicBody) -> Double {
        body.altitude
    }

    /// Subclasses override to provide the appropriate celestial body.
    open func getBody(date: Date) -> BasicBody {
        fatalError("Subclasses must override getBody(date:)")
    }

    /// Calculate rise and set times using quadratic interpolation.
    @discardableResult
    public func compute() -> Bool {
        var offset = 0
        let calendar = Calendar(identifier: .gregorian)

        repeat {
            let offsetDate = date.addingTimeInterval(Double(offset) * 3600.0)

            let body0 = getBody(date: offsetDate)
            let body1 = getBody(date: offsetDate.addingTimeInterval(3600))
            let body2 = getBody(date: offsetDate.addingTimeInterval(7200))

            body0.calculate()
            body1.calculate()
            body2.calculate()

            let altitude0 = adjustAltitude(body: body0)
            let altitude1 = adjustAltitude(body: body1)
            let altitude2 = adjustAltitude(body: body2)

            // Quadratic fit: ax² + bx + c
            let a = 0.5 * (altitude2 + altitude0) - altitude1
            let b = 2.0 * altitude1 - 0.5 * altitude2 - 1.5 * altitude0
            let c = altitude0

            let discriminant = (b * b) - (4.0 * a * c)
            let epsilon = 1e-5
            let discEps = 1e-10

            if discriminant >= -discEps {
                let disc = discriminant < 0 ? 0 : discriminant
                let sqrtD = sqrt(disc)

                var x1: Double, x2: Double
                if abs(a) < epsilon {
                    if abs(b) < epsilon { offset += 2; continue }
                    x1 = -c / b
                    x2 = x1
                } else {
                    x1 = (-b + sqrtD) / (2.0 * a)
                    x2 = (-b - sqrtD) / (2.0 * a)
                }

                let x1Valid = !x1.isNaN && x1 >= -epsilon && x1 <= 2.0 + epsilon && abs(x1 - x2) > epsilon
                let x2Valid = !x2.isNaN && x2 >= -epsilon && x2 <= 2.0 + epsilon && abs(x1 - x2) > epsilon

                let clampedX1 = x1.clamped(to: 0...2)
                let clampedX2 = x2.clamped(to: 0...2)

                if x1Valid { assignEvent(x: clampedX1, a: a, b: b, offsetDate: offsetDate) }
                if x2Valid { assignEvent(x: clampedX2, a: a, b: b, offsetDate: offsetDate) }
            }

            offset += 2
        } while !(rise != nil && set != nil) && offset <= 24

        return rise != nil || set != nil
    }

    private func assignEvent(x: Double, a: Double, b: Double, offsetDate: Date) {
        let slope = 2 * a * x + b
        let eventTime = offsetDate.addingTimeInterval(x * 3600.0)

        if slope > 0 {
            if rise == nil || eventTime < rise! { rise = eventTime }
        } else {
            if set == nil || eventTime < set! { set = eventTime }
        }
    }
}

// MARK: - Concrete rise/set types

/// Astronomical twilight (-18° sun altitude).
@available(macOS 13.0, *)
public class AstronomicalTwilightRiseAndSet: SunCustomRiseAndSet {
    public init(date: Date, latitude: Double, longitude: Double, elevation: Double = 0) {
        super.init(date: date, latitude: latitude, longitude: longitude, elevation: elevation, sunAltitude: -18)
    }
}

/// Nautical twilight (-12° sun altitude).
@available(macOS 13.0, *)
public class NauticalTwilightRiseAndSet: SunCustomRiseAndSet {
    public init(date: Date, latitude: Double, longitude: Double, elevation: Double = 0) {
        super.init(date: date, latitude: latitude, longitude: longitude, elevation: elevation, sunAltitude: -12)
    }
}

/// Civil twilight (-6° sun altitude).
@available(macOS 13.0, *)
public class CivilTwilightRiseAndSet: SunCustomRiseAndSet {
    public init(date: Date, latitude: Double, longitude: Double, elevation: Double = 0) {
        super.init(date: date, latitude: latitude, longitude: longitude, elevation: elevation, sunAltitude: -6)
    }
}

/// Sun rise/set (sun upper limb apparent horizon altitude).
@available(macOS 13.0, *)
public class SunRiseAndSet: SunCustomRiseAndSet {
    public init(date: Date, latitude: Double, longitude: Double, elevation: Double = 0) {
        super.init(date: date, latitude: latitude, longitude: longitude, elevation: elevation,
                    sunAltitude: -AstroUtil.sunUpperLimbApparentHorizonAltitude)
    }
}

/// Moon rise/set (moon upper limb apparent horizon altitude).
@available(macOS 13.0, *)
public class MoonRiseAndSet: MoonCustomRiseAndSet {
    public init(date: Date, latitude: Double, longitude: Double, elevation: Double = 0) {
        super.init(date: date, latitude: latitude, longitude: longitude, elevation: elevation,
                    moonAltitude: -AstroUtil.moonUpperLimbApparentHorizonAltitude)
    }
}

/// Sun-based custom altitude rise/set.
@available(macOS 13.0, *)
public class SunCustomRiseAndSet: RiseAndSetEvent {
    public let sunAltitude: Double

    public init(date: Date, latitude: Double, longitude: Double, elevation: Double, sunAltitude: Double) {
        self.sunAltitude = sunAltitude
        super.init(date: date, latitude: latitude, longitude: longitude, elevation: elevation)
    }

    override public func adjustAltitude(body: BasicBody) -> Double {
        return body.altitude - sunAltitude
    }

    override public func getBody(date: Date) -> BasicBody {
        return SunBody(date: date, latitude: latitude, longitude: longitude, elevation: elevation)
    }
}

/// Moon-based custom altitude rise/set.
@available(macOS 13.0, *)
public class MoonCustomRiseAndSet: RiseAndSetEvent {
    public let moonAltitude: Double

    public init(date: Date, latitude: Double, longitude: Double, elevation: Double, moonAltitude: Double) {
        self.moonAltitude = moonAltitude
        super.init(date: date, latitude: latitude, longitude: longitude, elevation: elevation)
    }

    override public func adjustAltitude(body: BasicBody) -> Double {
        return body.altitude - moonAltitude
    }

    override public func getBody(date: Date) -> BasicBody {
        return MoonBody(date: date, latitude: latitude, longitude: longitude, elevation: elevation)
    }
}

/// Custom rise/set with pre-set times.
@available(macOS 13.0, *)
public class CustomRiseAndSet: RiseAndSetEvent {
    public init(rise: Date?, set: Date?) {
        super.init(date: Date(), latitude: 0, longitude: 0, elevation: 0)
        self.rise = rise
        self.set = set
    }

    override public init(date: Date, latitude: Double, longitude: Double, elevation: Double) {
        super.init(date: date, latitude: latitude, longitude: longitude, elevation: elevation)
    }

    override public func compute() -> Bool { true }
    override public func adjustAltitude(body: BasicBody) -> Double { 0 }
    override public func getBody(date: Date) -> BasicBody { SunBody(date: date, latitude: 0, longitude: 0, elevation: 0) }
}

// MARK: - Celestial bodies for rise/set calculations

/// Base class for celestial body position calculations.
@available(macOS 13.0, *)
public class BasicBody {
    public let date: Date
    public let latitude: Double
    public let longitude: Double
    public let elevation: Double
    public private(set) var distance: Double = 0
    public private(set) var altitude: Double = 0

    public var radius: Double { 0 }

    public init(date: Date, latitude: Double, longitude: Double, elevation: Double = 0) {
        self.date = date
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
    }

    public func calculate() {
        let deltaT = AstroUtil.deltaT(date)
        let observer = NOVAS.Observer(where: 1,
                                       onSurf: NOVAS.OnSurface(latitude: latitude, longitude: longitude, height: elevation),
                                       nearEarth: NOVAS.InSpace())

        let bodyNumber: Int16
        let bodyName: String
        if self is SunBody {
            bodyNumber = Int16(NOVAS.Body.sun.rawValue)
            bodyName = "Sun"
        } else {
            bodyNumber = Int16(NOVAS.Body.moon.rawValue)
            bodyName = "Moon"
        }

        let celestialObject = NOVAS.CelestialObject(
            type: Int16(NOVAS.ObjectType.majorPlanetSunOrMoon.rawValue),
            number: bodyNumber,
            name: bodyName,
            star: NOVAS.CatalogueEntry()
        )

        var skyPosition = NOVAS.SkyPosition()
        let jdTT = AstroUtil.getJulianDate(date)
        _ = NOVAS.place(jdTT, celestialObject: celestialObject, observer: observer,
                        deltaT: deltaT, coordinateSystem: .equinoxOfDate, accuracy: .full, position: &skyPosition)

        distance = AstroUtil.auToKilometer(skyPosition.dis)
        let siderealTime = AstroUtil.getLocalSiderealTime(date, longitude: longitude)
        let hourAngle = AstroUtil.hoursToDegrees(AstroUtil.getHourAngle(siderealTime, rightAscension: skyPosition.ra))
        altitude = AstroUtil.getAltitude(hourAngle, latitude: latitude, declination: skyPosition.dec)
    }
}

@available(macOS 13.0, *)
public class SunBody: BasicBody {
    public override var radius: Double { 696342 }
    override public init(date: Date, latitude: Double, longitude: Double, elevation: Double = 0) {
        super.init(date: date, latitude: latitude, longitude: longitude, elevation: elevation)
    }
}

@available(macOS 13.0, *)
public class MoonBody: BasicBody {
    public override var radius: Double { 1738 }
    override public init(date: Date, latitude: Double, longitude: Double, elevation: Double = 0) {
        super.init(date: date, latitude: latitude, longitude: longitude, elevation: elevation)
    }
}

// MARK: - Helper

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}