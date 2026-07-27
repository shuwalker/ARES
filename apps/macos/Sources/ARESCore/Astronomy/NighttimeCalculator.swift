// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.
//
// Copyright © 2016 - 2026 Stefan Berg <isbeorn86+NINA@googlemail.com> and the N.I.N.A. contributors
// Ported from NINA.Astrometry to Swift for ARESCore.

import Foundation

/// Calculates night data for a given date and location.
/// Stripped of WPF/OxyPlot/UI dependencies; contains only domain calculations.
@available(macOS 13.0, *)
public enum NighttimeCalculator {

    /// Get the reference date (noon local time) for the given date.
    /// If after noon, use today's noon; if before noon, use yesterday's noon.
    public static func getReferenceDate(_ reference: Date) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let hour = calendar.component(.hour, from: reference)
        let minute = calendar.component(.minute, from: reference)

        var components = calendar.dateComponents([.year, .month, .day], from: reference)
        if hour > 12 || (hour == 12 && minute >= 0) {
            components.hour = 12
            components.minute = 0
            components.second = 0
        } else {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: reference)!
            components = calendar.dateComponents([.year, .month, .day], from: yesterday)
            components.hour = 12
            components.minute = 0
            components.second = 0
        }
        return calendar.date(from: components)!
    }
}