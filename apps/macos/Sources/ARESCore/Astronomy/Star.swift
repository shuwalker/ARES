// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Copyright © 2016 - 2026 Stefan Berg <isbeorn86+NINA@googlemail.com> and the N.I.N.A. contributors
// Ported from NINA.Astrometry to Swift for ARESCore.

import Foundation

/// Catalog star model.
@available(macOS 13.0, *)
public struct Star: Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let coords: Coordinates
    public let magnitude: Float

    public init(id: Int, name: String, coords: Coordinates, magnitude: Float) {
        self.id = id
        self.name = name
        self.coords = coords
        self.magnitude = magnitude
    }
}