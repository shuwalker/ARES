// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Copyright © 2016 - 2026 Stefan Berg <isbeorn86+NINA@googlemail.com> and the N.I.N.A. contributors
// Ported from NINA.Astrometry to Swift for ARESCore.

import Foundation

/// DSO object type filter model.
@available(macOS 13.0, *)
public struct DSOObjectType: Equatable, Sendable {
    public var name: String
    public var selected: Bool

    public init(name: String, selected: Bool = false) {
        self.name = name
        self.selected = selected
    }
}