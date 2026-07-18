// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Copyright © 2016 - 2026 Stefan Berg <isbeorn86+NINA@googlemail.com> and the N.I.N.A. contributors
// Ported from NINA.Astrometry to Swift for ARESCore.

import Foundation

/// RA/Dec coordinate pair with an associated epoch.
/// Supports coordinate transformation between J2000 and JNOW via SOFA algorithms.
@available(macOS 13.0, *)
public struct Coordinates: Equatable, Sendable {

    // MARK: - RA type

    public enum RAType: Sendable {
        case degrees
        case hours
    }

    // MARK: - Properties

    /// Right Ascension in hours
    public var ra: Double {
        get { raAngle.hours }
        set { raAngle = .byHours(newValue) }
    }

    /// Right Ascension in degrees
    public var raDegrees: Double { raAngle.degree }

    /// Declination in degrees
    public var dec: Double {
        get { decAngle.degree }
        set { decAngle = .byDegree(newValue) }
    }

    /// Formatted RA string (HH:MM:SS)
    public var raString: String { AstroUtil.degreesToHMS(raDegrees) }

    /// Formatted Dec string (DD° MM' SS")
    public var decString: String { AstroUtil.degreesToDMS(dec) }

    /// The epoch of this coordinate pair
    public var epoch: Epoch

    // MARK: - Private

    private var raAngle: Angle
    private var decAngle: Angle
    private var referenceDate: Date

    // MARK: - Initializers

    public init(ra: Angle, dec: Angle, epoch: Epoch) {
        self.raAngle = ra
        self.decAngle = dec
        self.epoch = epoch
        self.referenceDate = Date()
    }

    public init(ra: Double, dec: Double, epoch: Epoch, raType: RAType = .hours) {
        self.raAngle = raType == .hours ? .byHours(ra) : .byDegree(ra)
        self.decAngle = .byDegree(dec)
        self.epoch = epoch
        self.referenceDate = Date()
    }

    public init(ra: Angle, dec: Angle, epoch: Epoch, referenceDate: Date) {
        self.raAngle = ra
        self.decAngle = dec
        self.epoch = epoch
        self.referenceDate = referenceDate
    }

    // MARK: - Transformations

    /// Transform coordinates from one epoch to another (J2000 ↔ JNOW).
    public func transform(to targetEpoch: Epoch) -> Coordinates {
        guard epoch != targetEpoch else {
            return Coordinates(ra: raAngle, dec: decAngle, epoch: epoch, referenceDate: referenceDate)
        }
        if targetEpoch == .JNOW {
            return transformToJNOW()
        } else if targetEpoch == .J2000 {
            return transformToJ2000()
        } else {
            return Coordinates(ra: raAngle, dec: decAngle, epoch: epoch, referenceDate: referenceDate)
        }
    }

    /// Transform from J2000 to JNOW (apparent place).
    private func transformToJNOW() -> Coordinates {
        let now = Date()
        let jdTT = AstroUtil.getJulianDateTT(now)

        var ri = 0.0, di = 0.0, eo = 0.0
        SOFA.celestialToIntermediate(
            rc: raAngle.radians, dc: decAngle.radians,
            pr: 0.0, pd: 0.0, px: 0.0, rv: 0.0,
            date1: jdTT, date2: 0.0,
            ri: &ri, di: &di, eo: &eo
        )

        let raApparent = Angle.byRadians(SOFA.anp(ri - eo))
        let decApparent = Angle.byRadians(di)
        return Coordinates(ra: raApparent, dec: decApparent, epoch: .JNOW, referenceDate: now)
    }

    /// Transform from JNOW to J2000 (astrometric place).
    private func transformToJ2000() -> Coordinates {
        let (jdTt1, jdTt2) = AstroUtil.getJulianDateTTParts(referenceDate)

        var rc = 0.0, dc = 0.0, eo = 0.0
        SOFA.intermediateToCelestial(
            ri: SOFA.anp(raAngle.radians + SOFA.eo06a(jdTt1, date2: jdTt2)),
            di: decAngle.radians,
            date1: jdTt1, date2: jdTt2,
            rc: &rc, dc: &dc, eo: &eo
        )

        return Coordinates(ra: .byRadians(rc), dec: .byRadians(dc), epoch: .J2000, referenceDate: referenceDate)
    }

    /// Transform to topocentric (Alt/Az) coordinates using observer location and conditions.
    public func transform(
        latitude: Angle,
        longitude: Angle,
        elevation: Double = 0.0,
        pressureHPa: Double = 0.0,
        tempCelsius: Double = 0.0,
        relativeHumidity: Double = 0.0,
        wavelength: Double = 0.0,
        now: Date = Date()
    ) -> TopocentricCoordinates {
        let j2000Coords = self.transform(to: .J2000)
        let (utc1, utc2) = AstroUtil.getJulianDateUTCParts(now)
        let deltaUT = AstroUtil.deltaUT(now)

        var aob = 0.0, zob = 0.0, hob = 0.0, dob = 0.0, rob = 0.0, eo = 0.0
        SOFA.celestialToTopocentric(
            rc: j2000Coords.raAngle.radians, dc: j2000Coords.decAngle.radians,
            pr: 0.0, pd: 0.0, px: 0.0, rv: 0.0,
            utc1: utc1, utc2: utc2, dut1: deltaUT,
            elong: longitude.radians, phi: latitude.radians, hm: elevation,
            xp: 0.0, yp: 0.0,
            phpa: pressureHPa, tc: tempCelsius, rh: relativeHumidity, wl: wavelength,
            aob: &aob, zob: &zob, hob: &hob, dob: &dob, rob: &rob, eo: &eo
        )

        let azimuth = Angle.byRadians(aob)
        let altitude = Angle.byDegree(90) - Angle.byRadians(zob)
        return TopocentricCoordinates(azimuth: azimuth, altitude: altitude, latitude: latitude, longitude: longitude, elevation: elevation)
    }

    // MARK: - Shift (projection)

    public enum ProjectionType: Sendable {
        case gnomonic
        case stereographic
    }

    /// Shift coordinates by a delta in degrees using the specified projection type.
    public func shift(
        deltaX: Double,
        deltaY: Double,
        rotation: Double,
        scaleX: Double,
        scaleY: Double,
        type: ProjectionType = .stereographic
    ) -> Coordinates {
        let deltaXDeg = deltaX * AstroUtil.arcsecToDegree(scaleX)
        let deltaYDeg = deltaY * AstroUtil.arcsecToDegree(scaleY)
        return shift(deltaX: deltaXDeg, deltaY: deltaYDeg, rotation: rotation, type: type)
    }

    /// Shift coordinates by a delta in degrees using the specified projection type.
    public func shift(deltaX: Double, deltaY: Double, rotation: Double, type: ProjectionType = .stereographic) -> Coordinates {
        switch type {
        case .gnomonic: return shiftGnomonic(deltaX: deltaX, deltaY: deltaY, rotation: rotation)
        case .stereographic: return shiftStereographic(deltaX: deltaX, deltaY: deltaY, rotation: rotation)
        }
    }

    private func shiftGnomonic(deltaX: Double, deltaY: Double, rotation: Double) -> Coordinates {
        var deltaXAngle = Angle.byDegree(-deltaX)
        var deltaYAngle = Angle.byDegree(-deltaY)
        let rotationAngle = Angle.byDegree(rotation)

        if rotationAngle.degree != 0 {
            let originalDeltaX = deltaXAngle
            let rotationSin = rotationAngle.sin()
            let rotationCos = rotationAngle.cos()
            deltaXAngle = deltaXAngle * rotationCos - deltaYAngle * rotationSin
            deltaYAngle = deltaYAngle * rotationCos + originalDeltaX * rotationSin
        }

        let originDecSin = decAngle.sin()
        let originDecCos = decAngle.cos()

        let targetRA = raAngle + Angle.atan2(deltaXAngle, originDecCos - deltaYAngle * originDecSin)

        var targetDec = (targetRA - raAngle).cos() * (deltaYAngle * originDecCos + originDecSin) / (originDecCos - deltaYAngle * originDecSin)
        targetDec = targetDec.atan()

        var raDeg = targetRA.degree
        if raDeg < 0 { raDeg += 360 }
        if raDeg >= 360 { raDeg -= 360 }

        return Coordinates(ra: .byDegree(raDeg), dec: targetDec, epoch: epoch, referenceDate: referenceDate)
    }

    private func shiftStereographic(deltaX: Double, deltaY: Double, rotation: Double) -> Coordinates {
        var deltaXAngle = Angle.byDegree(-deltaX)
        var deltaYAngle = Angle.byDegree(-deltaY)
        let rotationAngle = Angle.byDegree(rotation)

        if rotationAngle.degree != 0 {
            let originalDeltaX = deltaXAngle
            let rotationSin = rotationAngle.sin()
            let rotationCos = rotationAngle.cos()
            deltaXAngle = deltaXAngle * rotationCos - deltaYAngle * rotationSin
            deltaYAngle = deltaYAngle * rotationCos + originalDeltaX * rotationSin
        }

        let originDecSin = decAngle.sin()
        let originDecCos = decAngle.cos()

        let sins = deltaXAngle * deltaXAngle + deltaYAngle * deltaYAngle
        let dz = (4.0 - sins.radians) / (4.0 + sins.radians)

        var targetDec = (dz * originDecSin.radians + deltaYAngle.radians * originDecCos.radians * (1.0 + dz) / 2.0)
        targetDec = Foundation.asin(targetDec)
        let targetDecAngle = Angle.byRadians(targetDec)

        var targetRA = Foundation.asin(deltaXAngle.radians * (1.0 + dz) / (2.0 * Foundation.cos(targetDec)))

        let mg = 2 * (Foundation.sin(targetDec) * originDecCos.radians - Foundation.cos(targetDec) * originDecSin.radians * Foundation.cos(targetRA)) /
            (1.0 + Foundation.sin(targetDec) * originDecSin.radians + Foundation.cos(targetDec) * originDecCos.radians * Foundation.cos(targetRA))

        if Swift.abs(Angle.byRadians(mg - deltaYAngle.radians).radians) > 1.0e-5 {
            targetRA = .pi - targetRA
        }

        targetRA += raAngle.radians

        var raDeg = Angle.byRadians(targetRA).degree
        if raDeg < 0 { raDeg += 360 }
        if raDeg >= 360 { raDeg -= 360 }

        return Coordinates(ra: .byDegree(raDeg), dec: targetDecAngle, epoch: epoch, referenceDate: referenceDate)
    }

    /// Calculate position angle between two coordinates (degrees).
    public static func calculatePositionAngle(a1Deg: Double, a2Deg: Double, d1Deg: Double, d2Deg: Double) -> Double {
        let a1 = AstroUtil.toRadians(a1Deg)
        let a2 = AstroUtil.toRadians(a2Deg)
        let d1 = AstroUtil.toRadians(d1Deg)
        let d2 = AstroUtil.toRadians(d2Deg)
        let numerator = sin(a1 - a2)
        let denominator = cos(d2) * tan(d1) - sin(d2) * cos(a1 - a2)
        return AstroUtil.toDegree(atan2(numerator, denominator))
    }

    // MARK: - Clone

    public func clone() -> Coordinates {
        Coordinates(ra: raAngle.copy(), dec: decAngle.copy(), epoch: epoch, referenceDate: referenceDate)
    }
}