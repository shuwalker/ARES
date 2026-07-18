// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Copyright © 2016 - 2026 Stefan Berg <isbeorn86+NINA@googlemail.com> and the N.I.N.A. contributors
// Ported from NINA.Astrometry to Swift for ARESCore.

import Foundation

/// Topocentric (Altitude/Azimuth) coordinate pair.
@available(macOS 13.0, *)
public struct TopocentricCoordinates: Equatable, Sendable {

    public enum AltitudeSite: Sendable {
        case east
        case west
    }

    public var azimuth: Angle
    public var altitude: Angle
    public let latitude: Angle
    public let longitude: Angle
    public let elevation: Double

    public var altitudeSite: AltitudeSite {
        azimuth.degree >= 0 && azimuth.degree < 180 ? .east : .west
    }

    public init(azimuth: Angle, altitude: Angle, latitude: Angle, longitude: Angle, elevation: Double = 0.0) {
        self.azimuth = azimuth
        self.altitude = altitude
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
    }

    /// Transform observed coordinates to ICRS astrometric coordinates while applying refraction.
    public func transform(
        to epoch: Epoch,
        pressureHPa: Double = 0.0,
        tempCelsius: Double = 0.0,
        relativeHumidity: Double = 0.0,
        wavelength: Double = 0.0,
        now: Date = Date()
    ) -> Coordinates {
        let zenithDistance = AstroUtil.toRadians(90.0 - altitude.degree)
        let deltaUT = AstroUtil.deltaUT(now)

        var raRad = 0.0, decRad = 0.0
        let (utc1, utc2) = AstroUtil.getJulianDateUTCParts(now)
        SOFA.topocentricToCelestial(
            type: "A",
            ob1: azimuth.radians, ob2: zenithDistance,
            utc1: utc1, utc2: utc2, dut1: deltaUT,
            elong: longitude.radians, phi: latitude.radians, hm: elevation,
            xp: 0.0, yp: 0.0,
            phpa: pressureHPa, tc: tempCelsius, rh: relativeHumidity, wl: wavelength,
            rc: &raRad, dc: &decRad
        )

        let ra = Angle.byRadians(raRad)
        let dec = Angle.byRadians(decRad)
        var coordinates = Coordinates(ra: ra, dec: dec, epoch: .J2000, referenceDate: now)
        return coordinates.transform(to: epoch)
    }

    public func clone() -> TopocentricCoordinates {
        TopocentricCoordinates(
            azimuth: azimuth.copyByDegree(),
            altitude: altitude.copyByDegree(),
            latitude: latitude.copyByDegree(),
            longitude: longitude.copyByDegree(),
            elevation: elevation
        )
    }

    public var description: String { "Alt: \(altitude); Az: \(azimuth)" }
}