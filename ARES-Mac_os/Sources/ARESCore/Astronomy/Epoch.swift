// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Copyright © 2016 - 2026 Stefan Berg <isbeorn86+NINA@googlemail.com> and the N.I.N.A. contributors
// Ported from NINA.Astrometry to Swift for ARESCore.

import Foundation

/// Coordinate epoch types for astronomical coordinate systems.
@available(macOS 13.0, *)
public enum Epoch: String, Sendable {
    case J2000
    case JNOW
    case B1950
    case J2050
}

/// Direction enum for altitude/azimuth queries.
@available(macOS 13.0, *)
public enum Direction: String, Sendable {
    case altitude
    case azimuth
}