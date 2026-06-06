import Foundation

public extension ISO8601DateFormatter {
    public static func fractionalSecondsFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

public enum DateFormatters {
    public static func relativeFormatter() -> RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }

    public static func shortDateTimeFormatter() -> DateFormatter {
        let cacheKey = "ARESDesktop.shortDateTimeFormatter"
        if let formatter = Thread.current.threadDictionary[cacheKey] as? DateFormatter {
            return formatter
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        Thread.current.threadDictionary[cacheKey] = formatter
        return formatter
    }

    public static func shortDateTimeString(from date: Date) -> String {
        shortDateTimeFormatter().string(from: date)
    }
}