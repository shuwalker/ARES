// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Copyright © 2016 - 2026 Stefan Berg <isbeorn86+NINA@googlemail.com> and the N.I.N.A. contributors
// Ported from NINA.Astrometry to Swift for ARESCore.
//
// NOVAS 3.1 star position calculations.
// In NINA, NOVAS functions are P/Invoke calls to a native DLL.
// In this Swift port, we implement a simplified version that uses SOFA
// algorithms for the core calculations.

import Foundation

/// NOVAS 3.1 star position calculation structures and algorithms.
/// This is a simplified pure-Swift port that relies on SOFA for core algorithms.
@available(macOS 13.0, *)
public enum NOVAS {

    // MARK: - Enums

    public enum ObjectType: Int16, Sendable {
        case majorPlanetSunOrMoon = 0
        case minorPlanet = 1
        case objectLocatedOutsideSolarSystem = 2
    }

    public enum Body: Int16, Sendable {
        case mercury = 1
        case venus = 2
        case earth = 3
        case mars = 4
        case jupiter = 5
        case saturn = 6
        case uranus = 7
        case neptune = 8
        case pluto = 9
        case sun = 10
        case moon = 11
    }

    public enum CoordinateSystem: Int16, Sendable {
        case gcrs = 0
        case equinoxOfDate = 1
        case cioOfDate = 2
        case astrometric = 3
    }

    public enum ObserverLocation: Int16, Sendable {
        case earthGeoCenter = 0
        case earthSurface = 1
        case spaceNearEarth = 2
    }

    public enum GstType: Int16, Sendable {
        case greenwichMeanSiderealTime = 0
        case greenwichApparentSiderealTime = 1
    }

    public enum Method: Int16, Sendable {
        case cioBased = 0
        case equinoxBased = 1
    }

    public enum Accuracy: Int16, Sendable {
        case full = 0
        case reduced = 1
    }

    public enum RefractionOption: Int, Sendable {
        case noRefraction = 0
        case standardRefraction = 1
        case locationRefraction = 2
    }

    public enum SolarSystemOrigin: Int16, Sendable {
        case barycenter = 0
        case solarCenterOfMass = 1
    }

    // MARK: - Structures

    public struct CatalogueEntry: Sendable {
        public var starName: String
        public var catalog: String
        public var starNumber: Int
        public var ra: Double
        public var dec: Double
        public var proMoRA: Double
        public var proMoDec: Double
        public var parallax: Double
        public var radialVelocity: Double

        public init(starName: String = "", catalog: String = "XXX", starNumber: Int = 0,
                    ra: Double = 0, dec: Double = 0, proMoRA: Double = 0, proMoDec: Double = 0,
                    parallax: Double = 0, radialVelocity: Double = 0) {
            self.starName = starName
            self.catalog = catalog
            self.starNumber = starNumber
            self.ra = ra
            self.dec = dec
            self.proMoRA = proMoRA
            self.proMoDec = proMoDec
            self.parallax = parallax
            self.radialVelocity = radialVelocity
        }
    }

    public struct CelestialObject: Sendable {
        public var type: Int16
        public var number: Int16
        public var name: String
        public var star: CatalogueEntry

        public init(type: Int16 = 0, number: Int16 = 0, name: String = "", star: CatalogueEntry = CatalogueEntry()) {
            self.type = type
            self.number = number
            self.name = name
            self.star = star
        }
    }

    public struct OnSurface: Sendable {
        public var latitude: Double
        public var longitude: Double
        public var height: Double
        public var temperature: Double
        public var pressure: Double

        public init(latitude: Double = 0, longitude: Double = 0, height: Double = 0,
                    temperature: Double = 0, pressure: Double = 0) {
            self.latitude = latitude
            self.longitude = longitude
            self.height = height
            self.temperature = temperature
            self.pressure = pressure
        }
    }

    public struct InSpace: Sendable {
        public var scPos: [Double]
        public var scVel: [Double]

        public init(scPos: [Double] = [0, 0, 0], scVel: [Double] = [0, 0, 0]) {
            self.scPos = scPos
            self.scVel = scVel
        }
    }

    public struct Observer: Sendable {
        public var where_: Int16
        public var onSurf: OnSurface
        public var nearEarth: InSpace

        public init(where: Int16 = 1, onSurf: OnSurface = OnSurface(), nearEarth: InSpace = InSpace()) {
            self.where_ = `where`
            self.onSurf = onSurf
            self.nearEarth = nearEarth
        }
    }

    public struct SkyPosition: Sendable {
        public var rHat: [Double]
        public var ra: Double
        public var dec: Double
        public var dis: Double
        public var rv: Double

        public init(rHat: [Double] = [0, 0, 0], ra: Double = 0, dec: Double = 0,
                    dis: Double = 0, rv: Double = 0) {
            self.rHat = rHat
            self.ra = ra
            self.dec = dec
            self.dis = dis
            self.rv = rv
        }
    }

    // MARK: - Core Functions

    /// Calculate sidereal time.
    /// Simplified implementation using GMST formula.
    public static func siderealTime(_ jdHigh: Double, jdLow: Double, deltaT: Double,
                                     gstType: GstType, method: Method, accuracy: Accuracy,
                                     gst: inout Double) -> Int16 {
        // Greenwich Mean Sidereal Time calculation
        let jd = jdHigh + jdLow
        let t = (jd - 2451545.0) / 36525.0
        let t2 = t * t
        let t3 = t2 * t

        // GMST in seconds
        var gmst = 24110.54841 + 8640184.812866 * t + 0.093104 * t2 - 6.2e-6 * t3
        gmst += deltaT * 1.00273790935 // UT1 correction

        // Normalize to [0, 86400)
        gmst = gmst.truncatingRemainder(dividingBy: 86400.0)
        if gmst < 0 { gmst += 86400.0 }

        // Convert to degrees
        gst = gmst / 240.0 // seconds to degrees (86400s = 360°)
        if gstType == .greenwichApparentSiderealTime {
            // Apply equation of equinoxes (simplified)
            let eo = SOFA.eo06a(jdHigh, date2: jdLow)
            gst += AstroUtil.toDegree(eo)
        }
        return 0
    }

    /// Convert Julian date from calendar components.
    public static func julianDate(year: Int16, month: Int16, day: Int16, hour: Double) -> Double {
        var y = Int(year)
        var m = Int(month)
        if m <= 2 {
            y -= 1
            m += 12
        }
        let a = Int(Double(y) / 100.0)
        let b = 2 - a + Int(Double(a) / 4.0)
        let term1 = Int(365.25 * Double(y + 4716))
        let term2 = Int(30.6001 * Double(m + 1))
        let jdInt = term1 + term2 + Int(day) + b
        return Double(jdInt) - 1524.5 + hour / 24.0
    }

    /// Convert Julian date to calendar date.
    public static func calDate(_ jtd: Double, year: inout Int16, month: inout Int16, day: inout Int16, hour: inout Double) -> Double {
        let jd = jtd + 0.5
        let z = Int(floor(jd))
        let f = jd - Double(z)

        var alpha: Int
        if z < 2299161 {
            alpha = z
        } else {
            alpha = Int((Double(z) - 1867216.25) / 36524.25)
            alpha = z + 1 + alpha - alpha / 4
        }

        let b = alpha + 1524
        let c = Int((Double(b) - 122.1) / 365.25)
        let d = Int(365.25 * Double(c))
        let e = Int((Double(b) - Double(d)) / 30.6001)

        day = Int16(b - d - Int(30.6001 * Double(e)))
        if e < 14 {
            month = Int16(e - 1)
        } else {
            month = Int16(e - 13)
        }
        if month > 2 {
            year = Int16(c - 4716)
        } else {
            year = Int16(c - 4715)
        }
        hour = Double(f) * 24.0
        return jtd
    }

    /// Calculate atmospheric refraction in zenith distance.
    /// Simplified implementation using Saemundsson's formula for standard conditions.
    public static func refract(location: OnSurface, option: RefractionOption, zenithDistance: Double) -> Double {
        switch option {
        case .noRefraction:
            return 0.0
        case .standardRefraction:
            // Standard refraction at sea level, 10°C, 1010 hPa
            let zd = zenithDistance * Double.pi / 180.0
            if zd <= 0 { return 0.0 }
            let tanZ = tan(zd)
            // Bennett's formula (in arcseconds, then convert)
            let r = 1.0 / tan(zd + 0.0031376 * (zd + 0.0816166 * (1.0 / tan(zd))))
            // Convert from arcminutes to degrees
            return r / 60.0
        case .locationRefraction:
            let zd = zenithDistance * Double.pi / 180.0
            if zd <= 0 { return 0.0 }
            let p = location.pressure
            let t = location.temperature
            // Adjusted Bennett formula
            let r = 1.0 / tan(zd + 0.0031376 * (zd + 0.0816166 * (1.0 / tan(zd))))
            let adjustedR = r * (p / 1010.0) * (283.0 / (273.0 + t)) / 60.0
            return adjustedR
        }
    }

    /// Compute the apparent direction of a celestial object.
    /// Simplified implementation using SOFA-based calculations.
    public static func place(_ jdTT: Double, celestialObject: CelestialObject, observer: Observer,
                              deltaT: Double, coordinateSystem: CoordinateSystem,
                              accuracy: Accuracy, position: inout SkyPosition) -> Int16 {
        // Get local sidereal time
        let jdHigh = Int(jdTT)
        let jdLow = jdTT - Double(jdHigh)
        var lst: Double = 0
        _ = siderealTime(Double(jdHigh), jdLow: jdLow, deltaT: deltaT,
                         gstType: .greenwichApparentSiderealTime, method: .equinoxBased, accuracy: accuracy, gst: &lst)

        // Calculate position using SOFA
        var ri: Double = 0, di: Double = 0, eo: Double = 0
        SOFA.celestialToIntermediate(
            rc: celestialObject.star.ra * Double.pi / 12.0,  // hours to radians
            dc: celestialObject.star.dec * Double.pi / 180.0, // degrees to radians
            pr: 0, pd: 0, px: 0, rv: 0,
            date1: Double(jdHigh), date2: jdLow,
            ri: &ri, di: &di, eo: &eo
        )

        // Convert to topocentric if surface observer
        if observer.where_ == 1 {
            let lat = observer.onSurf.latitude * Double.pi / 180.0
            let lon = observer.onSurf.longitude * Double.pi / 180.0

            // Parallax correction for Moon (simplified)
            if celestialObject.number == Body.moon.rawValue {
                // Simplified topocentric correction for Moon
                let ha = lst * 15.0 * Double.pi / 180.0 - ri
                let cosHA = cos(ha)
                let sinHA = sin(ha)
                let cosLat = cos(lat)
                let sinLat = sin(lat)
                let cosDec = cos(di)

                // Topocentric RA correction (simplified)
                let parallaxAngle = cosLat * cosHA / cosDec
                ri -= parallaxAngle * 0.0023 // Simplified parallax correction
            }

            position.ra = ri * 12.0 / Double.pi // radians to hours
            position.dec = di * 180.0 / Double.pi // radians to degrees
        } else {
            position.ra = ri * 12.0 / Double.pi
            position.dec = di * 180.0 / Double.pi
        }

        // Approximate distance (in AU)
        switch celestialObject.number {
        case Body.sun.rawValue: position.dis = 1.0
        case Body.moon.rawValue: position.dis = 0.00257
        default: position.dis = 0.0
        }

        return 0
    }
}