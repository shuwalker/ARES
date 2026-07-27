// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Copyright © 2016 - 2026 Stefan Berg <isbeorn86+NINA@googlemail.com> and the N.I.N.A. contributors
// Ported from NINA.Astrometry to Swift for ARESCore.

import Foundation

/// Input coordinates model for UI binding. Stripped of INotifyPropertyChanged.
@available(macOS 13.0, *)
public struct InputCoordinates: Equatable, Sendable {
    public var coordinates: Coordinates
    public var negativeDec: Bool

    public init(coordinates: Coordinates) {
        self.coordinates = coordinates
        self.negativeDec = coordinates.dec < 0
    }

    public init() {
        self.coordinates = Coordinates(ra: .zero, dec: .zero, epoch: .J2000)
        self.negativeDec = false
    }

    // MARK: - RA components

    public var raHours: Int {
        get { Int(trunc(coordinates.ra)) }
        set { coordinates.ra = coordinates.ra - Double(self.raHours) + Double(newValue) }
    }

    public var raMinutes: Int {
        get {
            let minutes = abs(coordinates.ra * 60.0).truncatingRemainder(dividingBy: 60)
            let seconds = Int(round(abs(coordinates.ra * 3600.0).truncatingRemainder(dividingBy: 60)))
            var m = Int(floor(minutes))
            if seconds > 59 { m += 1 }
            return m
        }
        set { coordinates.ra = coordinates.ra - Double(raMinutes) / 60.0 + Double(newValue) / 60.0 }
    }

    public var raSeconds: Double {
        get {
            var seconds = round(abs(coordinates.ra * 3600.0).truncatingRemainder(dividingBy: 60) * 100000) / 100000
            if seconds >= 60.0 { seconds = 0 }
            return seconds
        }
        set { coordinates.ra = coordinates.ra - raSeconds / 3600.0 + newValue / 3600.0 }
    }

    // MARK: - Dec components

    public var decDegrees: Int {
        get { Int(trunc(coordinates.dec)) }
        set {
            if negativeDec {
                coordinates.dec = Double(newValue) - Double(decMinutes) / 60.0 - decSeconds / 3600.0
            } else {
                coordinates.dec = Double(newValue) + Double(decMinutes) / 60.0 + decSeconds / 3600.0
            }
        }
    }

    public var decMinutes: Int {
        get {
            let minutes = abs(coordinates.dec * 60.0).truncatingRemainder(dividingBy: 60)
            let seconds = Int(round(abs(coordinates.dec * 3600.0).truncatingRemainder(dividingBy: 60)))
            var m = Int(floor(minutes))
            if seconds > 59 { m += 1 }
            return m
        }
        set {
            if negativeDec {
                coordinates.dec = coordinates.dec + Double(decMinutes) / 60.0 - Double(newValue) / 60.0
            } else {
                coordinates.dec = coordinates.dec - Double(decMinutes) / 60.0 + Double(newValue) / 60.0
            }
        }
    }

    public var decSeconds: Double {
        get {
            var seconds = round(abs(coordinates.dec * 3600.0).truncatingRemainder(dividingBy: 60) * 100000) / 100000
            if seconds >= 60.0 { seconds = 0 }
            return seconds
        }
        set {
            if negativeDec {
                coordinates.dec = coordinates.dec + decSeconds / 3600.0 - newValue / 3600.0
            } else {
                coordinates.dec = coordinates.dec - decSeconds / 3600.0 + newValue / 3600.0
            }
        }
    }

    public func clone() -> InputCoordinates {
        InputCoordinates(coordinates: coordinates.clone())
    }

    private func trunc(_ value: Double) -> Double {
        value >= 0 ? floor(value) : ceil(value)
    }
}