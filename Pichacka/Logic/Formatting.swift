import Foundation

/// České formátování čísel a dat (`cs_CZ`, Europe/Prague).
enum CzFormat {
    static let locale = Locale(identifier: "cs_CZ")

    private static func number(_ value: Decimal, fractionDigits: Int = 2) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter
    }

    static func decimal(_ value: Decimal) -> String {
        number(value).string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    /// `12,50 h`
    static func hours(seconds: Int) -> String {
        "\(decimal(Report.hours(fromSeconds: seconds))) h"
    }

    /// `18 750,00 Kč`
    static func money(_ amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(decimal(amount)) \(currency)"
    }

    private static func dateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = .prague
        formatter.timeZone = Calendar.prague.timeZone
        formatter.dateFormat = format
        return formatter
    }

    static func date(_ date: Date) -> String { dateFormatter("d. M. yyyy").string(from: date) }
    static func time(_ date: Date) -> String { dateFormatter("HH:mm").string(from: date) }
    static func dayHeading(_ date: Date) -> String { dateFormatter("EEEE d. MMMM yyyy").string(from: date) }

    /// `říjen 2026`
    static func month(_ month: ReportMonth) -> String {
        dateFormatter("LLLL yyyy").string(from: month.firstDay)
    }

    /// `08:00–12:30`, při přechodu přes půlnoc `22:00–02:00 (+1 d)`
    static func timeRange(start: Date, end: Date) -> String {
        let crossesMidnight = Calendar.prague.startOfDay(for: start) != Calendar.prague.startOfDay(for: end)
        return "\(time(start))–\(time(end))" + (crossesMidnight ? " (+1 d)" : "")
    }

    /// `1:23:45` nebo `3:05` (pod hodinu)
    static func elapsed(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func duration(seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 3600, seconds % 3600 / 60)
    }
}
