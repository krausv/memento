import Foundation

enum StatsPeriod: String, CaseIterable, Identifiable {
    case week, month, year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "Týden"
        case .month: "Měsíc"
        case .year: "Rok"
        }
    }

    var component: Calendar.Component {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    /// Týden a měsíc se člení po dnech, rok po měsících.
    var bucketComponent: Calendar.Component { self == .year ? .month : .day }
}

/// Vstup pro `StatsBuilder` – čistá hodnota bez závislosti na SwiftData.
struct StatsEntry: Equatable {
    var projectName: String
    var tags: [String]
    var start: Date
    /// `nil` = běží, počítá se do `now`.
    var end: Date?
}

struct Stats: Equatable {
    struct Point: Equatable, Identifiable {
        var bucket: Date
        var project: String
        var seconds: Int
        var id: String { "\(bucket.timeIntervalSinceReferenceDate)|\(project)" }
    }

    struct Slice: Equatable, Identifiable {
        var name: String
        var seconds: Int
        var id: String { name }
    }

    static let untaggedName = "Bez štítku"

    let period: StatsPeriod
    let interval: DateInterval
    /// Začátky všech sloupců grafu včetně prázdných.
    let buckets: [Date]
    let points: [Point]
    let byProject: [Slice]
    /// Záznam s víc štítky se počítá ke každému z nich, součet tedy může být větší než `totalSeconds`.
    let byTag: [Slice]
    let totalSeconds: Int
    let entryCount: Int
    /// Počet dnů, ve kterých začal aspoň jeden záznam.
    let workedDays: Int

    var averagePerWorkedDay: Int { workedDays > 0 ? totalSeconds / workedDays : 0 }
}

/// Statistiky ze skutečných časů záznamů (bez zaokrouhlení z exportu). Záznam patří do dne a měsíce, ve kterém začal.
enum StatsBuilder {
    static func interval(for period: StatsPeriod, containing anchor: Date, calendar: Calendar = .prague) -> DateInterval {
        calendar.dateInterval(of: period.component, for: anchor)
            ?? DateInterval(start: calendar.startOfDay(for: anchor), duration: 86_400)
    }

    static func shift(_ anchor: Date, period: StatsPeriod, by steps: Int, calendar: Calendar = .prague) -> Date {
        calendar.date(byAdding: period.component, value: steps, to: anchor) ?? anchor
    }

    static func build(
        period: StatsPeriod,
        anchor: Date,
        entries: [StatsEntry],
        now: Date,
        calendar: Calendar = .prague
    ) -> Stats {
        let interval = interval(for: period, containing: anchor, calendar: calendar)

        var buckets: [Date] = []
        var cursor = interval.start
        while cursor < interval.end {
            buckets.append(cursor)
            guard let next = calendar.date(byAdding: period.bucketComponent, value: 1, to: cursor) else { break }
            cursor = next
        }

        var perPoint: [String: Stats.Point] = [:]
        var perProject: [String: Int] = [:]
        var perTag: [String: Int] = [:]
        var days = Set<Date>()
        var total = 0
        var count = 0

        for entry in entries where interval.contains(entry.start) {
            let seconds = max(0, Int(((entry.end ?? now).timeIntervalSince(entry.start)).rounded()))
            let bucket = calendar.dateInterval(of: period.bucketComponent, for: entry.start)?.start ?? entry.start
            var point = perPoint["\(bucket.timeIntervalSinceReferenceDate)|\(entry.projectName)"]
                ?? Stats.Point(bucket: bucket, project: entry.projectName, seconds: 0)
            point.seconds += seconds
            perPoint[point.id] = point

            perProject[entry.projectName, default: 0] += seconds
            let tags = Set(entry.tags)
            for tag in tags.isEmpty ? [Stats.untaggedName] : Array(tags) { perTag[tag, default: 0] += seconds }
            days.insert(calendar.startOfDay(for: entry.start))
            total += seconds
            count += 1
        }

        func slices(_ dictionary: [String: Int]) -> [Stats.Slice] {
            dictionary
                .map { Stats.Slice(name: $0.key, seconds: $0.value) }
                .sorted { ($0.seconds, $1.name) > ($1.seconds, $0.name) }
        }

        return Stats(
            period: period, interval: interval, buckets: buckets,
            points: perPoint.values.sorted { ($0.bucket, $0.project) < ($1.bucket, $1.project) },
            byProject: slices(perProject), byTag: slices(perTag),
            totalSeconds: total, entryCount: count, workedDays: days.count
        )
    }
}
