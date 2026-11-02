import Foundation

/// Rozdělení času na pracovní dobu a mimo ni podle Nastavení › Připomínky (pracovní dny a od–do).
enum WorkHours {
    struct Split: Equatable {
        var inside: Int
        var outside: Int
        var total: Int { inside + outside }
    }

    /// Sekundy intervalu uvnitř pracovní doby a mimo ni. Interval může přesahovat přes půlnoc i přes víc dnů;
    /// víkend a nepracovní dny jsou celé „mimo“.
    static func split(start: Date, end: Date, schedule: ReminderSettings, calendar: Calendar = .prague) -> Split {
        guard end > start else { return Split(inside: 0, outside: 0) }
        var inside = 0.0
        var day = calendar.startOfDay(for: start)
        while day < end {
            defer { day = calendar.date(byAdding: .day, value: 1, to: day) ?? end }
            guard schedule.workDays.contains(calendar.component(.weekday, from: day)),
                  schedule.workEndMinutes > schedule.workStartMinutes,
                  let from = calendar.date(byAdding: .minute, value: schedule.workStartMinutes, to: day),
                  let to = calendar.date(byAdding: .minute, value: schedule.workEndMinutes, to: day)
            else { continue }
            let overlap = min(end, to).timeIntervalSince(max(start, from))
            if overlap > 0 { inside += overlap }
        }
        let total = max(0, Int(end.timeIntervalSince(start).rounded()))
        let insideSeconds = min(total, Int(inside.rounded()))
        return Split(inside: insideSeconds, outside: total - insideSeconds)
    }
}
