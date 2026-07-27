// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Copyright © 2016 - 2026 Stefan Berg <isbeorn86+NINA@googlemail.com> and the N.I.N.A. contributors
// Ported from NINA.Astrometry to Swift for ARESCore.

import Foundation

/// Static astronomical utility functions for degree/radian conversions,
/// HMS/DMS formatting, sidereal time, refraction, night times, moon phase,
/// moon illumination, and coordinate transforms.
@available(macOS 13.0, *)
public enum AstroUtil {

    // MARK: - Constants

    public static let degreeToRadiansFactor = Double.pi / 180.0
    public static let radiansToDegreeFactor = 180.0 / Double.pi
    public static let radiansToHourFactor = 12.0 / Double.pi
    public static let daysToSecondsFactor = 60.0 * 60.0 * 24.0
    public static let secondsToDaysFactor = 1.0 / (60.0 * 60.0 * 24.0)
    public static let siderealRateArcsecPerSecond = 15.041
    public static let arcSecPerPixConversionFactor = radiansToDegreeFactor * 60.0 * 60.0 / 1000.0

    public static let moonUpperLimbApparentHorizonAltitude = 0.583
    public static let sunUpperLimbApparentHorizonAltitude = 0.833

    // MARK: - Conversion helpers

    public static func toRadians(_ val: Double) -> Double { degreeToRadiansFactor * val }
    public static func toDegree(_ angle: Double) -> Double { angle * radiansToDegreeFactor }
    public static func radianToHour(_ radian: Double) -> Double { radian * radiansToHourFactor }
    public static func degreeToArcmin(_ degree: Double) -> Double { degree * 60.0 }
    public static func degreeToArcsec(_ degree: Double) -> Double { degree * 3600.0 }
    public static func arcminToArcsec(_ arcmin: Double) -> Double { arcmin * 60.0 }
    public static func arcminToDegree(_ arcmin: Double) -> Double { arcmin / 60.0 }
    public static func arcsecToArcmin(_ arcsec: Double) -> Double { arcsec / 60.0 }
    public static func arcsecToDegree(_ arcsec: Double) -> Double { arcsec / 3600.0 }
    public static func hoursToDegrees(_ hours: Double) -> Double { hours * 15.0 }
    public static func degreesToHours(_ deg: Double) -> Double { deg / 15.0 }

    public static func euclidianModulus(_ x: Double, _ y: Double) -> Double {
        if y > 0 {
            let r = x.truncatingRemainder(dividingBy: y)
            return r < 0 ? r + y : r
        } else if y < 0 {
            return -1 * euclidianModulus(-1 * x, -1 * y)
        } else {
            return Double.nan
        }
    }

    public static func mathMod(_ a: Double, _ b: Double) -> Double { euclidianModulus(a, b) }

    public static func secondsToDays(_ seconds: Double) -> Double { seconds * secondsToDaysFactor }
    public static func daysToSeconds(_ days: Double) -> Double { days * daysToSecondsFactor }

    // MARK: - Julian date helpers

    public static func getJulianDate(_ date: Date) -> Double {
        let (utc1, utc2) = getJulianDateUTCParts(date)
        return utc1 + utc2
    }

    public static func getSecondOfMinuteWithFraction(_ date: Date) -> Double {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.second, .nanosecond], from: date)
        return Double(components.second ?? 0) + Double(components.nanosecond ?? 0) / 1_000_000_000.0
    }

    public static func getJulianDateUTCParts(_ date: Date) -> (Double, Double) {
        let utcDate = date
        var d1: Double = 0, d2: Double = 0
        SOFA.dtf2d("UTC", year: utcDate.year!, month: utcDate.month!, day: utcDate.day!,
                   hour: utcDate.hour!, minute: utcDate.minute!, second: getSecondOfMinuteWithFraction(utcDate),
                   d1: &d1, d2: &d2)
        return (d1, d2)
    }

    public static func getJulianDateTT(_ date: Date) -> Double {
        let (tt1, tt2) = getJulianDateTTParts(date)
        return tt1 + tt2
    }

    public static func getJulianDateTTParts(_ date: Date) -> (Double, Double) {
        var tai1: Double = 0, tai2: Double = 0, tt1: Double = 0, tt2: Double = 0
        var utc1: Double = 0, utc2: Double = 0

        SOFA.dtf2d("UTC", year: date.year!, month: date.month!, day: date.day!,
                   hour: date.hour!, minute: date.minute!, second: getSecondOfMinuteWithFraction(date),
                   d1: &utc1, d2: &utc2)

        SOFA.utctai(utc1, utc2, &tai1, &tai2)
        SOFA.taitt(tai1, tai2, &tt1, &tt2)

        return (tt1, tt2)
    }

    // MARK: - DeltaT / DeltaUT

    /// Calculates DeltaT (TT - UT1) for a given date.
    /// Simplified: returns 32.184 + (TAI-UTC) - DeltaUT as per NINA formula.
    /// Note: DeltaUT lookup from IERS database is not available in this port;
    /// a default of 0.0 is used for DeltaUT.
    public static func deltaT(_ date: Date) -> Double {
        var mutc1: Double = 0, mutc2: Double = 0, mutai1: Double = 0, mutai2: Double = 0

        SOFA.dtf2d("UTC", year: date.year!, month: date.month!, day: date.day!,
                   hour: date.hour!, minute: date.minute!, second: getSecondOfMinuteWithFraction(date),
                   d1: &mutc1, d2: &mutc2)

        SOFA.utctai(mutc1, mutc2, &mutai1, &mutai2)

        let utc = mutc1 + mutc2
        let tai = mutai1 + mutai2
        let deltaUTValue = deltaUT(date)
        return 32.184 + daysToSeconds(tai - utc) - deltaUTValue
    }

    /// Retrieve UT1 - UTC approximation.
    /// In this port, returns 0.0 as the IERS database is not available.
    public static func deltaUT(_ date: Date) -> Double {
        // Without the IERS database connection, return 0.0
        // This can be overridden by providing actual DeltaUT values
        return 0.0
    }

    // MARK: - Sidereal time

    /// Get local sidereal time in hours for a given date and longitude.
    public static func getLocalSiderealTime(_ date: Date, longitude: Double) -> Double {
        let deltaT = deltaT(date)
        let (tt1, tt2) = getJulianDateTTParts(date)

        let utHigh = Int(tt1)
        let utLow = (tt1 - Double(utHigh)) + tt2 - secondsToDays(deltaT)
        var lst: Double = 0
        NOVAS.siderealTime(Double(utHigh), jdLow: utLow, deltaT: deltaT,
                          gstType: NOVAS.GstType.greenwichApparentSiderealTime, method: NOVAS.Method.equinoxBased, accuracy: NOVAS.Accuracy.full, gst: &lst)
        lst = lst + degreesToHours(longitude)
        return lst
    }

    // MARK: - Hour angle

    public static func getHourAngle(_ siderealTime: Double, rightAscension: Double) -> Double {
        return getHourAngle(Angle.byHours(siderealTime), rightAscension: Angle.byHours(rightAscension)).hours
    }

    public static func getHourAngle(_ siderealTime: Angle, rightAscension: Angle) -> Angle {
        var hourAngle = siderealTime - rightAscension
        if hourAngle.hours < 0 { hourAngle = Angle.byHours(hourAngle.hours + 24) }
        return hourAngle
    }

    public static func getRightAscensionFromHourAngle(_ hourAngle: Angle, siderealTime: Angle) -> Angle {
        return siderealTime - hourAngle
    }

    // MARK: - Altitude / Azimuth

    public static func getAltitude(_ hourAngle: Double, latitude: Double, declination: Double) -> Double {
        return getAltitude(Angle.byDegree(hourAngle), latitude: Angle.byDegree(latitude), declination: Angle.byDegree(declination)).degree
    }

    public static func getAltitude(_ hourAngle: Angle, latitude: Angle, declination: Angle) -> Angle {
        return (declination.sin() * latitude.sin() + declination.cos() * latitude.cos() * hourAngle.cos()).asin()
    }

    public static func getAzimuth(_ hourAngle: Double, altitude: Double, latitude: Double, declination: Double) -> Double {
        return getAzimuth(Angle.byDegree(hourAngle), altitude: Angle.byDegree(altitude), latitude: Angle.byDegree(latitude), declination: Angle.byDegree(declination)).degree
    }

    public static func getAzimuth(_ hourAngle: Angle, altitude: Angle, latitude: Angle, declination: Angle) -> Angle {
        var cosAz = (declination.sin() - altitude.sin() * latitude.sin()) / (altitude.cos() * latitude.cos())
        if cosAz.radians < -1 { cosAz = Angle.byRadians(-1) }
        if cosAz.radians > 1 { cosAz = Angle.byRadians(1) }

        if hourAngle.sin().radians < 0 {
            return cosAz.acos()
        } else {
            return Angle.byDegree(360 - cosAz.acos().degree)
        }
    }

    // MARK: - AU

    public static func auToKilometer(_ au: Double) -> Double {
        let conversionFactor = 149_597_870.7
        return au * conversionFactor
    }

    // MARK: - Night times (rise/set)

    public static func getNightTimes(date: Date, latitude: Double, longitude: Double, elevation: Double = 0) -> RiseAndSetEvent {
        let riseAndSet = AstronomicalTwilightRiseAndSet(date: date, latitude: latitude, longitude: longitude, elevation: elevation)
        _ = riseAndSet.compute()
        return riseAndSet
    }

    public static func getNauticalNightTimes(date: Date, latitude: Double, longitude: Double, elevation: Double = 0) -> RiseAndSetEvent {
        let riseAndSet = NauticalTwilightRiseAndSet(date: date, latitude: latitude, longitude: longitude, elevation: elevation)
        _ = riseAndSet.compute()
        return riseAndSet
    }

    public static func getCivilNightTimes(date: Date, latitude: Double, longitude: Double, elevation: Double = 0) -> RiseAndSetEvent {
        let riseAndSet = CivilTwilightRiseAndSet(date: date, latitude: latitude, longitude: longitude, elevation: elevation)
        _ = riseAndSet.compute()
        return riseAndSet
    }

    public static func getMoonRiseAndSet(date: Date, latitude: Double, longitude: Double, elevation: Double = 0) -> RiseAndSetEvent {
        let riseAndSet = MoonRiseAndSet(date: date, latitude: latitude, longitude: longitude, elevation: elevation)
        _ = riseAndSet.compute()
        return riseAndSet
    }

    public static func getSunRiseAndSet(date: Date, latitude: Double, longitude: Double, elevation: Double = 0) -> RiseAndSetEvent {
        let riseAndSet = SunRiseAndSet(date: date, latitude: latitude, longitude: longitude, elevation: elevation)
        _ = riseAndSet.compute()
        return riseAndSet
    }

    // MARK: - Formatting

    public static func degreesToDMS(_ value: Double) -> String {
        degreesToDMS(value, pattern: "%02d° %02d' %02d\"")
    }

    private static func degreesToDMS(_ value: Double, pattern: String) -> String {
        var negative = false
        var val = value
        if val < 0 {
            negative = true
            val = -val
        }

        var degree = floor(val)
        var arcmin = floor(degreeToArcmin(val - degree))
        let arcminDeg = arcminToDegree(arcmin)

        var arcsec = round(degreeToArcsec(val - degree - arcminDeg))
        if arcsec == 60 {
            arcsec = 0
            arcmin += 1
            if arcmin == 60 {
                arcmin = 0
                degree += 1
            }
        }

        let sign = negative ? "-" : ""
        return "\(sign)\(String(format: pattern, Int(degree), Int(arcmin), Int(arcsec)))"
    }

    public static func degreesToHMS(_ deg: Double) -> String {
        degreesToDMS(degreesToHours(deg), pattern: "%02d:%02d:%02d")
    }

    public static func hoursToHMS(_ hours: Double) -> String {
        guard hours != Double.greatestFiniteMagnitude else { return "" }
        return degreesToDMS(hours, pattern: "%02d:%02d:%02d")
    }

    public static func degreesToFitsDMS(_ deg: Double) -> String {
        if deg >= 0 {
            return "+" + degreesToDMS(deg).replacingOccurrences(of: "°", with: "").replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\"", with: "")
        } else {
            return degreesToDMS(deg).replacingOccurrences(of: "°", with: "").replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\"", with: "")
        }
    }

    public static func hoursToFitsHMS(_ hours: Double) -> String {
        hoursToHMS(hours).replacingOccurrences(of: ":", with: " ")
    }

    public static func hmsToDegrees(_ hms: String) -> Double {
        degreesToHours(dmsToDegrees(hms))
    }

    public static func dmsToDegrees(_ dms: String) -> Double {
        let trimmed = dms.trimmingCharacters(in: .whitespaces)
        var signFactor = 1.0
        var str = trimmed
        if str.contains("-") { signFactor = -1.0 }

        let pattern = "[0-9\\.]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let nsRange = NSRange(str.startIndex..., in: str)
        let matches = regex.matches(in: str, range: nsRange)

        var degree = 0.0, minutes = 0.0, seconds = 0.0
        for (index, match) in matches.enumerated() {
            guard let range = Range(match.range, in: str) else { continue }
            let valueStr = String(str[range]).replacingOccurrences(of: ",", with: ".")
            guard let value = Double(valueStr) else { continue }
            switch index {
            case 0: degree = value
            case 1: minutes = arcminToDegree(value)
            case 2: seconds = arcsecToDegree(value)
            default: break
            }
        }

        return signFactor * (degree + minutes + seconds)
    }

    public static func isDMS(_ value: String) -> Bool {
        let pattern = "^[-+]?\\d{1,3}(\\s|°)\\d{1,2}(\\s|')\\d{1,2}(\\.\\d+)?"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    public static func isHMS(_ value: String) -> Bool {
        let pattern = "^\\d{1,2}(\\s|:)\\d{1,2}(\\s|:)\\d{1,2}(\\.\\d+)?"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Moon position / phase / illumination

    public static func getMoonPosition(date: Date, observerInfo: ObserverInfo) -> NOVAS.SkyPosition {
        let deltaTValue = deltaT(date)

        let onSurface = NOVAS.OnSurface(
            latitude: observerInfo.latitude,
            longitude: observerInfo.longitude,
            height: observerInfo.elevation,
            temperature: observerInfo.temperature,
            pressure: observerInfo.pressure
        )
        let observer = NOVAS.Observer(where: 1, onSurf: onSurface, nearEarth: NOVAS.InSpace())
        let celestialObject = NOVAS.CelestialObject(
            type: Int16(NOVAS.ObjectType.majorPlanetSunOrMoon.rawValue),
            number: Int16(NOVAS.Body.moon.rawValue),
            name: "Moon",
            star: NOVAS.CatalogueEntry()
        )

        var skyPosition = NOVAS.SkyPosition()
        let jdTT = getJulianDateTT(date)
        NOVAS.place(jdTT, celestialObject: celestialObject, observer: observer, deltaT: deltaTValue,
                    coordinateSystem: .equinoxOfDate, accuracy: .full, position: &skyPosition)
        return skyPosition
    }

    public static func getSunPosition(date: Date, observerInfo: ObserverInfo) -> NOVAS.SkyPosition {
        let deltaTValue = deltaT(date)

        let onSurface = NOVAS.OnSurface(
            latitude: observerInfo.latitude,
            longitude: observerInfo.longitude,
            height: observerInfo.elevation,
            temperature: observerInfo.temperature,
            pressure: observerInfo.pressure
        )
        let observer = NOVAS.Observer(where: 1, onSurf: onSurface, nearEarth: NOVAS.InSpace())
        let celestialObject = NOVAS.CelestialObject(
            type: Int16(NOVAS.ObjectType.majorPlanetSunOrMoon.rawValue),
            number: Int16(NOVAS.Body.sun.rawValue),
            name: "Sun",
            star: NOVAS.CatalogueEntry()
        )

        var skyPosition = NOVAS.SkyPosition()
        let jdTT = getJulianDateTT(date)
        NOVAS.place(jdTT, celestialObject: celestialObject, observer: observer, deltaT: deltaTValue,
                    coordinateSystem: .equinoxOfDate, accuracy: .full, position: &skyPosition)
        return skyPosition
    }

    public static func getMoonPositionAngle(date: Date, observerInfo: ObserverInfo) -> Double {
        let moonPos = getMoonPosition(date: date, observerInfo: observerInfo)
        let sunPos = getSunPosition(date: date, observerInfo: observerInfo)
        let diff = hoursToDegrees(moonPos.ra - sunPos.ra)
        if diff > 180 { return diff - 360 }
        else if diff < -180 { return diff + 360 }
        else { return diff }
    }

    public static func getMoonPhase(date: Date, observerInfo: ObserverInfo) -> MoonPhase {
        let angle = getMoonPositionAngle(date: date, observerInfo: observerInfo)
        if (angle >= -180.0 && angle < -135.0) || angle == 180.0 { return .fullMoon }
        else if angle >= -135.0 && angle < -90.0 { return .waningGibbous }
        else if angle >= -90.0 && angle < -45.0 { return .lastQuarter }
        else if angle >= -45.0 && angle < 0.0 { return .waningCrescent }
        else if angle >= 0.0 && angle < 45.0 { return .newMoon }
        else if angle >= 45.0 && angle < 90.0 { return .waxingCrescent }
        else if angle >= 90.0 && angle < 135.0 { return .firstQuarter }
        else if angle >= 135.0 && angle < 180.0 { return .waxingGibbous }
        else { return .unknown }
    }

    public static func getMoonIllumination(date: Date, observerInfo: ObserverInfo) -> Double {
        let moonPos = getMoonPosition(date: date, observerInfo: observerInfo)
        let sunPos = getSunPosition(date: date, observerInfo: observerInfo)

        let sunRAAngle = Angle.byHours(sunPos.ra)
        let sunDecAngle = Angle.byDegree(sunPos.dec)
        let moonRAAngle = Angle.byHours(moonPos.ra)
        let moonDecAngle = Angle.byDegree(moonPos.dec)

        let phi = (sunDecAngle.sin() * moonDecAngle.sin()
                   + sunDecAngle.cos() * moonDecAngle.cos() * (sunRAAngle - moonRAAngle).cos()).acos()

        let phaseAngle = Angle.atan2(sunPos.dis * phi.sin(), moonPos.dis - sunPos.dis * phi.cos())
        let illuminatedFraction = (1.0 + phaseAngle.cos().radians) / 2.0
        return illuminatedFraction
    }

    public static func getMoonAltitude(date: Date, observerInfo: ObserverInfo) -> Double {
        let moon = getMoonPosition(date: date, observerInfo: observerInfo)
        let siderealTime = getLocalSiderealTime(date, longitude: observerInfo.longitude)
        let hourAngle = hoursToDegrees(getHourAngle(siderealTime, rightAscension: moon.ra))
        return getAltitude(hourAngle, latitude: observerInfo.latitude, declination: moon.dec)
    }

    public static func getSunAltitude(date: Date, observerInfo: ObserverInfo) -> Double {
        let sun = getSunPosition(date: date, observerInfo: observerInfo)
        let siderealTime = getLocalSiderealTime(date, longitude: observerInfo.longitude)
        let hourAngle = hoursToDegrees(getHourAngle(siderealTime, rightAscension: sun.ra))
        return getAltitude(hourAngle, latitude: observerInfo.latitude, declination: sun.dec)
    }

    public static func calculateAltitudeForStandardRefraction(currentAltitude: Double, latitude: Double, longitude: Double, elevation: Double) -> Double {
        let zenithDistance = 90.0 - currentAltitude
        let location = NOVAS.OnSurface(latitude: latitude, longitude: longitude, height: elevation, temperature: 0, pressure: 0)
        let refraction = NOVAS.refract(location: location, option: .standardRefraction, zenithDistance: zenithDistance)
        return currentAltitude + refraction
    }

    // MARK: - Arcsec / pixel / FOV

    public static func arcsecPerPixel(pixelSize: Double, focalLength: Double) -> Double {
        return (pixelSize / focalLength) * arcSecPerPixConversionFactor
    }

    public static func maxFieldOfView(arcsecPerPixel: Double, width: Double, height: Double) -> Double {
        return arcsecToArcmin(arcsecPerPixel * max(width, height))
    }

    public static func fieldOfView(arcsecPerPixel: Double, width: Double) -> Double {
        return arcsecToArcmin(arcsecPerPixel * width)
    }

    // MARK: - Moon phase enum

    public enum MoonPhase: String, Sendable {
        case unknown
        case fullMoon
        case waningGibbous
        case lastQuarter
        case waningCrescent
        case newMoon
        case waxingCrescent
        case firstQuarter
        case waxingGibbous
    }

    // MARK: - Airmass / dew point / pressure

    /// Airmass calculated using Gueymard 1993.
    public static func airmass(_ altitude: Double) -> Double {
        guard altitude >= 0 && altitude <= 90 && !altitude.isNaN && !altitude.isInfinite else { return Double.nan }
        let Z = 90 - altitude
        let cosZ = cos(toRadians(Z))
        return 1.0 / (cosZ + 0.00176759 * Z * pow(94.37515 - Z, -1.21563))
    }

    /// Approximate dew point using Magnus Formula.
    public static func approximateDewPoint(temperature: Double, humidity: Double) -> Double {
        var b = 17.368
        var c = 233.88
        if temperature < 0 {
            b = 17.966
            c = 247.15
        }
        let gammaTRH = log(humidity / 100.0) + ((b * temperature) / (c + temperature))
        return (c * gammaTRH) / (b - gammaTRH)
    }

    /// Converts MSL pressure to local pressure using ISO 2533:1975 Standard Atmospheric Model.
    public static func mslToLocalPressure(_ mslPressure: Double, elevation: Double) -> Double {
        return mslPressure * pow(1.0 - 2.25577e-5 * elevation, 5.25588)
    }

    /// Calculate position angle between two coordinates (degrees).
    public static func calculatePositionAngle(a1Deg: Double, a2Deg: Double, d1Deg: Double, d2Deg: Double) -> Double {
        let a1 = toRadians(a1Deg)
        let a2 = toRadians(a2Deg)
        let d1 = toRadians(d1Deg)
        let d2 = toRadians(d2Deg)
        let numerator = sin(a1 - a2)
        let denominator = cos(d2) * tan(d1) - sin(d2) * cos(a1 - a2)
        return toDegree(atan2(numerator, denominator))
    }

    /// Calculate refracted altitude for a given topocentric altitude.
    public static func calculateRefractedAltitude(
        altitude: Double,
        pressureHPa: Double,
        tempCelsius: Double,
        relativeHumidity: Double,
        wavelength: Double,
        iterationIncrementInArcsec: Double = 1,
        maxIterations: Double = 1000
    ) -> Double {
        guard altitude >= 0 else { return Double.nan }

        var refa: Double = 0, refb: Double = 0
        let Z = toRadians(90 - altitude)
        SOFA.refractionConstants(pressureHPa, tc: tempCelsius, rh: relativeHumidity, wl: wavelength, refa: &refa, refb: &refb)

        let increment = toRadians(arcsecToDegree(iterationIncrementInArcsec))
        var roller = increment
        var iterations = 0
        repeat {
            let refractedZDRadian = Z - roller
            let dz2 = refa * tan(refractedZDRadian) + refb * pow(tan(refractedZDRadian), 3)
            if dz2.isNaN { return Double.nan }
            let originalZDRadian = refractedZDRadian + dz2
            if abs(originalZDRadian - Z) < toRadians(arcsecToDegree(iterationIncrementInArcsec)) {
                return 90 - toDegree(refractedZDRadian)
            }
            roller += increment
            iterations += 1
        } while Double(iterations) < maxIterations
        return Double.nan
    }

    // MARK: - Drift align error

    public static func determineDriftAlignError(startDeclination: Double, driftRate: Double, declinationError: Double) -> Double {
        let decRad = toRadians(startDeclination)
        let decErr = degreeToArcsec(declinationError)
        let t = driftRate * 4
        return toDegree(decErr / (900 * t * Foundation.cos(decRad)))
    }
}

// MARK: - Date helpers

extension Date {
    var year: Int? { Calendar(identifier: .gregorian).component(.year, from: self) }
    var month: Int? { Calendar(identifier: .gregorian).component(.month, from: self) }
    var day: Int? { Calendar(identifier: .gregorian).component(.day, from: self) }
    var hour: Int? { Calendar(identifier: .gregorian).component(.hour, from: self) }
    var minute: Int? { Calendar(identifier: .gregorian).component(.minute, from: self) }
}