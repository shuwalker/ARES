// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Copyright © 2016 - 2026 Stefan Berg <isbeorn86+NINA@googlemail.com> and the N.I.N.A. contributors
// Ported from NINA.Astrometry to Swift for ARESCore.

import Foundation

/// Constellation model.
@available(macOS 13.0, *)
public struct Constellation: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var goesOverRaZero: Bool
    public var stars: [Star]
    public var starConnections: [(Star, Star)]

    public init(id: String, name: String? = nil) {
        self.id = id
        self.name = name ?? id
        self.goesOverRaZero = false
        self.stars = []
        self.starConnections = []
    }

    public static func == (lhs: Constellation, rhs: Constellation) -> Bool {
        guard lhs.id == rhs.id,
              lhs.name == rhs.name,
              lhs.goesOverRaZero == rhs.goesOverRaZero,
              lhs.stars == rhs.stars,
              lhs.starConnections.count == rhs.starConnections.count else {
            return false
        }
        for i in 0..<lhs.starConnections.count {
            if lhs.starConnections[i].0 != rhs.starConnections[i].0 ||
               lhs.starConnections[i].1 != rhs.starConnections[i].1 {
                return false
            }
        }
        return true
    }
}