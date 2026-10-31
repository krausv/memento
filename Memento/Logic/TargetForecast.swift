import Foundation

/// Kolik hodin zbývá k měsíčnímu cíli fakturace a jestli je to do konce měsíce reálné.
/// Kapacita vychází z pracovních dnů a doby z Nastavení › Připomínky (výchozí Po–Pá 9–17).
struct TargetForecast: Equatable {
    enum Verdict: Equatable {
        /// Cíl je splněn (v pásmu cíle nebo nad ním).
        case reached
        /// Zbývající práce zabere nejvýš 80 % zbývající kapacity.
        case realistic
        /// Vyjde to jen na hraně kapacity.
        case tight
        /// Zbývající kapacita nestačí.
        case unrealistic
    }

    /// Hodiny (v sekundách) potřebné k dosažení cíle při sazbě projektu.
    let remainingSeconds: Int
    /// Pracovní doba zbývající do konce měsíce včetně zbytku dneška.
    let capacitySeconds: Int
    /// Dny, ve kterých ještě zbývá nějaká pracovní doba (dnešek se počítá, pokud ještě neskončil).
    let workDaysLeft: Int
    /// Zbývající pracovní doba dnešního dne (0, když dnes není pracovní den nebo už skončila pracovní doba).
    let todayCapacitySeconds: Int
    let verdict: Verdict

    /// Potřebný denní průměr; `nil`, když už není kdy pracovat.
    var requiredPerDaySeconds: Int? { workDaysLeft > 0 ? remainingSeconds / workDaysLeft : nil }

    /// Kolik ještě zbývá odpracovat dnes, aby se zbytek měsíce rozložil rovnoměrně mezi zbývající pracovní dny.
    /// 0, když dnes už nebo ještě není co plánovat (víkend, po pracovní době) nebo je cíl splněn.
    var requiredTodaySeconds: Int {
        guard todayCapacitySeconds > 0, workDaysLeft > 0, remainingSeconds > 0 else { return 0 }
        return (remainingSeconds + workDaysLeft - 1) / workDaysLeft
    }

    static let realisticShare = 0.8

    static func compute(
        status: TargetStatus,
        hourlyRate: Decimal,
        now: Date,
        schedule: ReminderSettings,
        calendar: Calendar = .prague
    ) -> TargetForecast? {
        guard hourlyRate > 0 else { return nil }

        let missing = max(0, -status.difference)
        let remaining = NSDecimalNumber(decimal: (missing / hourlyRate * 3600).rounded(scale: 0, mode: .up)).intValue
        let (capacity, days) = capacityLeft(now: now, schedule: schedule, calendar: calendar)

        let verdict: Verdict
        if status.position != .under {
            verdict = .reached
        } else if capacity == 0 || remaining > capacity {
            verdict = .unrealistic
        } else if Double(remaining) <= Double(capacity) * realisticShare {
            verdict = .realistic
        } else {
            verdict = .tight
        }
        return TargetForecast(
            remainingSeconds: status.position == .under ? remaining : 0,
            capacitySeconds: capacity, workDaysLeft: days,
            todayCapacitySeconds: todayCapacity(now: now, schedule: schedule, calendar: calendar), verdict: verdict
        )
    }

    /// Zbývající pracovní doba dnešního dne od `now`.
    static func todayCapacity(now: Date, schedule: ReminderSettings, calendar: Calendar = .prague) -> Int {
        guard schedule.workDays.contains(calendar.component(.weekday, from: now)) else { return 0 }
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return max(0, schedule.workEndMinutes - max(nowMinutes, schedule.workStartMinutes)) * 60
    }

    /// Zbývající pracovní doba od `now` do konce měsíce.
    static func capacityLeft(now: Date, schedule: ReminderSettings, calendar: Calendar = .prague) -> (seconds: Int, days: Int) {
        let dailyMinutes = max(0, schedule.workEndMinutes - schedule.workStartMinutes)
        guard dailyMinutes > 0,
              let monthDays = calendar.range(of: .day, in: .month, for: now) else { return (0, 0) }
        let today = calendar.component(.day, from: now)
        let nowParts = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (nowParts.hour ?? 0) * 60 + (nowParts.minute ?? 0)
        let startOfToday = calendar.startOfDay(for: now)

        var seconds = 0
        var days = 0
        for day in today...monthDays.upperBound - 1 {
            guard let date = calendar.date(byAdding: .day, value: day - today, to: startOfToday),
                  schedule.workDays.contains(calendar.component(.weekday, from: date)) else { continue }
            var minutes = dailyMinutes
            if day == today {
                minutes = max(0, schedule.workEndMinutes - max(nowMinutes, schedule.workStartMinutes))
            }
            guard minutes > 0 else { continue }
            seconds += minutes * 60
            days += 1
        }
        return (seconds, days)
    }
}
