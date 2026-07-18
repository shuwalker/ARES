// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Copyright © 2016 - 2026 Stefan Berg <isbeorn86+NINA@googlemail.com> and the N.I.N.A. contributors
// Ported from NINA.Astrometry to Swift for ARESCore.

import Foundation

/// Meridian flip calculations.
/// Stripped of NINA Profile/INPC dependencies.
@available(macOS 13.0, *)
public enum MeridianFlip {

    /// Pier side enum (simplified).
    public enum PierSide: Sendable {
        case pierUnknown
        case pierWest
        case pierEast
    }

    /// Time to meridian for given coordinates.
    public static func timeToMeridian(coordinates: Coordinates, localSiderealTime: Angle) -> TimeInterval {
        let transformed = coordinates.transform(to: .JNOW)
        let rightAscension = Angle.byHours(transformed.ra)
        var hoursToMeridian = (rightAscension.hours - localSiderealTime.hours).truncatingRemainder(dividingBy: 12.0)
        if hoursToMeridian < 0 { hoursToMeridian += 12.0 }
        return TimeInterval(hoursToMeridian * 3600.0)
    }

    /// Expected pier side for coordinates.
    public static func expectedPierSide(coordinates: Coordinates, localSiderealTime: Angle) -> PierSide {
        let transformed = coordinates.transform(to: .JNOW)
        let rightAscension = Angle.byHours(transformed.ra)
        var hoursToLST = (rightAscension.hours - localSiderealTime.hours).truncatingRemainder(dividingBy: 24.0)
        if hoursToLST < 0 { hoursToLST += 24.0 }

        return hoursToLST < 12.0 ? .pierWest : .pierEast
    }
}