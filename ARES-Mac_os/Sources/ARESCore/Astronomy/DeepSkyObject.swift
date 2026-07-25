// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Copyright © 2016 - 2026 Stefan Berg <isbeorn86+NINA@googlemail.com> and the N.I.N.A. contributors
// Ported from NINA.Astrometry to Swift for ARESCore.

import Foundation

/// Deep sky object model. Stripped of WPF/OxyPlot/UI dependencies;
/// contains only domain data (id, name, coordinates, type, magnitude, size).
@available(macOS 13.0, *)
public struct DeepSkyObject: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var coordinates: Coordinates
    public var dsoType: String?
    public var constellation: String?
    public var magnitude: Double?
    public var size: Double?
    public var sizeMin: Double?
    public var surfaceBrightness: Double?
    public var positionAngle: Angle?
    public var alsoKnownAs: [String] = []

    public init(id: String, coordinates: Coordinates) {
        self.id = id
        self.name = id
        self.coordinates = coordinates
    }

    public init(id: String, name: String, coordinates: Coordinates,
                dsoType: String? = nil, magnitude: Double? = nil,
                size: Double? = nil, sizeMin: Double? = nil,
                surfaceBrightness: Double? = nil, positionAngle: Angle? = nil) {
        self.id = id
        self.name = name
        self.coordinates = coordinates
        self.dsoType = dsoType
        self.magnitude = magnitude
        self.size = size
        self.sizeMin = sizeMin
        self.surfaceBrightness = surfaceBrightness
        self.positionAngle = positionAngle
    }

    /// Calculate whether the object transits south.
    public func doesTransitSouth(latitude: Double) -> Bool {
        let alt0 = AstroUtil.getAltitude(0, latitude: latitude, declination: coordinates.dec)
        let alt180 = AstroUtil.getAltitude(180, latitude: latitude, declination: coordinates.dec)
        let transit: Double
        if alt0 > alt180 {
            transit = AstroUtil.getAzimuth(0, altitude: alt0, latitude: latitude, declination: coordinates.dec)
        } else {
            transit = AstroUtil.getAzimuth(180, altitude: alt180, latitude: latitude, declination: coordinates.dec)
        }
        return !transit.isNaN && Int(transit) == 180
    }
}