// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Copyright © 2016 - 2026 Stefan Berg <isbeorn86+NINA@googlemail.com> and the N.I.N.A. contributors
// Ported from NINA.Astrometry to Swift for ARESCore.

import Foundation

/// Observer location (latitude, longitude, elevation).
@available(macOS 13.0, *)
public struct Location: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var elevation: Double

    public init(latitude: Double = 0, longitude: Double = 0, elevation: Double = 0) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
    }
}