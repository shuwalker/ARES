// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Copyright © 2016 - 2026 Stefan Berg <isbeorn86+NINA@googlemail.com> and the N.I.N.A. contributors
// Ported from NINA.Astrometry to Swift for ARESCore.

import Foundation

/// Moon information: position, phase, illumination, and separation from a target.
/// Stripped of WPF/OxyPlot/UI dependencies.
@available(macOS 13.0, *)
public struct MoonInfo: Equatable, Sendable {
    public var coordinates: Coordinates
    public var separation: Double
    public var separationText: String
    public var phase: AstroUtil.MoonPhase
    public var illumination: Double?

    public init(coordinates: Coordinates) {
        self.coordinates = coordinates
        self.separation = 0
        self.separationText = "000°"
        self.phase = .unknown
        self.illumination = nil
    }

    /// Set the reference date and observer, then calculate moon data.
    public mutating func setReferenceDateAndObserver(_ date: Date, observer: ObserverInfo) {
        phase = AstroUtil.getMoonPhase(date: date, observerInfo: observer)
        illumination = AstroUtil.getMoonIllumination(date: date, observerInfo: observer)
        calculateSeparation(date: date, observer: observer)
    }

    private mutating func calculateSeparation(date: Date, observer: ObserverInfo) {
        let moonPos = AstroUtil.getMoonPosition(date: date, observerInfo: observer)
        let moonRaRad = AstroUtil.toRadians(AstroUtil.hoursToDegrees(moonPos.ra))
        let moonDecRad = AstroUtil.toRadians(moonPos.dec)

        let target = coordinates.transform(to: .JNOW)
        let targetRaRad = AstroUtil.toRadians(target.raDegrees)
        let targetDecRad = AstroUtil.toRadians(target.dec)

        let theta = SOFA.seps(moonRaRad, moonDecRad, targetRaRad, targetDecRad)
        separation = AstroUtil.toDegree(theta)
        separationText = String(format: "%03d°", Int(round(separation)))
    }
}