// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Copyright © 2016 - 2026 Stefan Berg <isbeorn86+NINA@googlemail.com> and the N.I.N.A. contributors
// Ported from NINA.Astrometry to Swift for ARESCore.

import Foundation

/// Nighttime data model. Stripped of OxyPlot/UI dependencies.
@available(macOS 13.0, *)
public struct NighttimeData: Equatable, Sendable {
    public let date: Date
    public let referenceDate: Date
    public let moonPhase: AstroUtil.MoonPhase
    public let illumination: Double?
    public let twilightRiseAndSet: RiseAndSetEvent?
    public let nauticalTwilightRiseAndSet: RiseAndSetEvent?
    public let civilTwilightRiseAndSet: RiseAndSetEvent?
    public let sunRiseAndSet: RiseAndSetEvent?
    public let moonRiseAndSet: RiseAndSetEvent?

    public init(
        date: Date,
        referenceDate: Date,
        moonPhase: AstroUtil.MoonPhase,
        illumination: Double?,
        twilightRiseAndSet: RiseAndSetEvent?,
        nauticalTwilightRiseAndSet: RiseAndSetEvent?,
        civilTwilightRiseAndSet: RiseAndSetEvent?,
        sunRiseAndSet: RiseAndSetEvent?,
        moonRiseAndSet: RiseAndSetEvent?
    ) {
        self.date = date
        self.referenceDate = referenceDate
        self.moonPhase = moonPhase
        self.illumination = illumination
        self.twilightRiseAndSet = twilightRiseAndSet
        self.nauticalTwilightRiseAndSet = nauticalTwilightRiseAndSet
        self.civilTwilightRiseAndSet = civilTwilightRiseAndSet
        self.sunRiseAndSet = sunRiseAndSet
        self.moonRiseAndSet = moonRiseAndSet
    }
}