// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Copyright © 2016 - 2026 Stefan Berg <isbeorn86+NINA@googlemail.com> and the N.I.N.A. contributors
// Ported from NINA.Astrometry to Swift for ARESCore.

import Foundation

/// Twilight duration calculator.
@available(macOS 13.0, *)
public enum TwilightCalculator {

    /// Calculate the duration of twilight for a given date and location.
    public static func getTwilightDuration(date: Date, latitude: Double, longitude: Double, elevation: Double = 0) -> TimeInterval {
        let nightRise = AstroUtil.getNightTimes(date: date, latitude: latitude, longitude: longitude, elevation: elevation).rise
        let sunRiseAndSet = AstroUtil.getSunRiseAndSet(date: date, latitude: latitude, longitude: longitude, elevation: elevation)

        guard let nightRiseTime = nightRise,
              let sunRiseTime = sunRiseAndSet.rise,
              let sunSetTime = sunRiseAndSet.set else {
            return 0
        }

        if nightRiseTime > sunRiseTime {
            return sunRiseTime.timeIntervalSince(sunSetTime)
        }

        return sunRiseTime.timeIntervalSince(nightRiseTime)
    }
}