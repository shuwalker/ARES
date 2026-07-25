// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Copyright © 2016 - 2026 Stefan Berg <isbeorn86+NINA@googlemail.com> and the N.I.N.A. contributors
// Ported from NINA.Astrometry to Swift for ARESCore.

import Foundation

/// Observer parameters for astronomical calculations (latitude, longitude, elevation, atmospheric conditions).
@available(macOS 13.0, *)
public struct ObserverInfo: Equatable, Sendable {

    /// Observer's latitude in degrees
    public var latitude: Double = 0

    /// Observer's longitude in degrees
    public var longitude: Double = 0

    /// Observer's elevation above mean sea level in meters
    public var elevation: Double = 0

    /// Observer's local air pressure in millibars/hectopascals
    public var pressure: Double = 1013.25

    /// Observer's local temperature in degrees Celsius
    public var temperature: Double = 20.0

    /// Observer's local humidity as a percentage (0-100)
    public var humidity: Double = 0

    public init(latitude: Double = 0, longitude: Double = 0, elevation: Double = 0,
                pressure: Double = 1013.25, temperature: Double = 20.0, humidity: Double = 0) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        self.pressure = pressure
        self.temperature = temperature
        self.humidity = humidity
    }
}