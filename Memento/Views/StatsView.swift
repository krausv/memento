import Charts
import SwiftData
import SwiftUI

struct StatsView: View {
    @Environment(TimerController.self) private var timer
    @Environment(\.theme) private var theme
    @Query(sort: \TimeEntry.start) private var entries: [TimeEntry]
    @Query(sort: \Project.name) private var projects: [Project]

    @AppStorage("statsPeriod") private var periodRaw = StatsPeriod.week.rawValue
    @State private var anchor = Date()

    private var period: StatsPeriod { StatsPeriod(rawValue: periodRaw) ?? .week }

    private var statsEntries: [StatsEntry] {
        entries.compactMap { entry in
            guard let project = entry.project else { return nil }
            return StatsEntry(projectName: project.name, tags: entry.tags.map(\.name), start: entry.start, end: entry.end)
        }
    }

    var body: some View {
        // Jedno sestavení pro celé view; průběžný čas se bere jen z běžícího časovače.
        let all = statsEntries
        let stats = StatsBuilder.build(period: period, anchor: anchor, entries: all, now: timer.now)
        let previous = StatsBuilder.build(
            period: period, anchor: StatsBuilder.shift(anchor, period: period, by: -1), entries: all, now: timer.now
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(rangeTitle(stats)).font(.title2.bold())
                if stats.totalSeconds == 0 {
                    ContentUnavailableView("Žádné záznamy", systemImage: "chart.bar",
                                           description: Text("V tomto období nejsou žádné záznamy."))
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    tiles(stats, previous: previous)
                    card("Hodiny v čase") { timeChart(stats) }
                    targetCard(stats)
                    HStack(alignment: .top, spacing: 16) {
                        card("Podle projektů") { sliceChart(stats.byProject, tint: .accentColor) }
                        card("Podle štítků") {
                            sliceChart(stats.byTag, tint: theme.secondaryAccent)
                            Text("Záznam s víc štítky se počítá ke každému z nich.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(20)
        }
        .environment(\.locale, CzFormat.locale)
        .environment(\.calendar, .prague)
        .environment(\.timeZone, Calendar.prague.timeZone)
        .navigationTitle("Přehled")
        .toolbar {
            ToolbarItem {
                Picker("Období", selection: $periodRaw) {
                    ForEach(StatsPeriod.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .onChange(of: periodRaw) { anchor = Date() }
            }
            ToolbarItemGroup {
                Button("Předchozí", systemImage: "chevron.left") {
                    anchor = StatsBuilder.shift(anchor, period: period, by: -1)
                }
                Button("Dnes") { anchor = Date() }
                Button("Další", systemImage: "chevron.right") {
                    anchor = StatsBuilder.shift(anchor, period: period, by: 1)
                }
                .disabled(stats.interval.end > timer.now)
            }
        }
    }

    // MARK: Součásti

    private func tiles(_ stats: Stats, previous: Stats) -> some View {
        let difference = stats.totalSeconds - previous.totalSeconds
        let comparison = previous.totalSeconds == 0
            ? "—"
            : (difference >= 0 ? "+" : "−") + CzFormat.hours(seconds: abs(difference))
        return HStack(spacing: 12) {
            tile("Celkem", CzFormat.hours(seconds: stats.totalSeconds))
            tile("Průměr za den s prací", CzFormat.hours(seconds: stats.averagePerWorkedDay), caption: "\(stats.workedDays) dnů")
            tile("Záznamů", "\(stats.entryCount)")
            tile("Oproti předchozímu", comparison, caption: previousLabel)
        }
    }

    private func tile(_ title: String, _ value: String, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(caption ?? " ").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(theme.surface, in: .rect(cornerRadius: 14))
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(theme.surface, in: .rect(cornerRadius: 14))
    }

    private func timeChart(_ stats: Stats) -> some View {
        let unit: Calendar.Component = period == .year ? .month : .day
        return Chart(stats.points) { point in
            BarMark(
                x: .value("Období", point.bucket, unit: unit),
                y: .value("Hodiny", Double(point.seconds) / 3600)
            )
            .foregroundStyle(by: .value("Projekt", point.project))
        }
        .chartForegroundStyleScale(range: theme.chart)
        .chartXScale(domain: stats.interval.start...stats.interval.end)
        .chartXAxis {
            switch period {
            case .week:
                AxisMarks(values: stats.buckets) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated).day(), centered: true)
                }
            case .month:
                AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day(), centered: true)
                }
            case .year:
                AxisMarks(values: stats.buckets) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel { if let hours = value.as(Double.self) { Text("\(Int(hours)) h") } }
            }
        }
        .frame(height: 240)
    }

    private func sliceChart(_ slices: [Stats.Slice], tint: Color) -> some View {
        Chart(slices) { slice in
            BarMark(
                x: .value("Hodiny", Double(slice.seconds) / 3600),
                y: .value("Název", slice.name)
            )
            .foregroundStyle(tint)
            .annotation(position: .trailing) {
                Text(CzFormat.hours(seconds: slice.seconds)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .chartYScale(domain: slices.map(\.name))
        .chartXAxis(.hidden)
        .frame(height: max(80, CGFloat(slices.count) * 32))
    }

    // MARK: Cíl fakturace

    private var targetProjects: [Project] {
        projects.filter { !$0.isArchived && ($0.targetAmount ?? 0) > 0 }
    }

    private func color(for position: TargetStatus.Position) -> Color {
        switch position {
        case .under: .accentColor
        case .on: .green
        case .over: .orange
        }
    }

    private func title(for position: TargetStatus.Position) -> String {
        switch position {
        case .under: "pod hranicí"
        case .on: "na hranici"
        case .over: "nad hranicí"
        }
    }

    @ViewBuilder
    private func targetCard(_ stats: Stats) -> some View {
        let withTarget = targetProjects
        if !withTarget.isEmpty {
            let rounding = AppSettings.rounding
            if period == .year {
                let year = Calendar.prague.component(.year, from: stats.interval.start)
                let currentMonth = ReportMonth(containing: timer.now)
                card("Cíl fakturace po měsících") {
                    ForEach(withTarget) { project in
                        yearTargetChart(project, year: year, until: currentMonth, rounding: rounding)
                        if year == currentMonth.year,
                           let status = project.targetStatus(now: timer.now, rounding: rounding, month: currentMonth) {
                            forecastView(project, status)
                        }
                    }
                    Text("Částka se počítá se zaokrouhlením z exportu.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                let month = ReportMonth(containing: anchor)
                card("Cíl fakturace · \(CzFormat.month(month))") {
                    ForEach(withTarget) { project in
                        if let status = project.targetStatus(now: timer.now, rounding: rounding, month: month) {
                            targetRow(project, status)
                            if month == ReportMonth(containing: timer.now) { forecastView(project, status) }
                        }
                    }
                    Text("Cíl je měsíční, proto se u týdne hodnotí měsíc zvoleného týdne. Částka se počítá se zaokrouhlením z exportu. Odhad reálnosti vychází z pracovních dnů a doby v Nastavení › Připomínky.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func targetRow(_ project: Project, _ status: TargetStatus) -> some View {
        let tint = color(for: status.position)
        let difference = status.difference
        let detail = difference < 0
            ? "chybí \(CzFormat.money(-difference, currency: project.currency))"
            : "+\(CzFormat.money(difference, currency: project.currency))"
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(project.name).font(.subheadline.bold())
                Spacer()
                Text("\(title(for: status.position)) (\(detail))").font(.caption).foregroundStyle(tint)
            }
            ProgressView(value: min(status.fraction, 1)).tint(tint)
            Text("\(CzFormat.money(status.amount, currency: project.currency)) z \(CzFormat.money(status.target, currency: project.currency))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Zbývající hodiny a odhad, jestli je cíl v aktuálním měsíci reálný.
    @ViewBuilder
    private func forecastView(_ project: Project, _ status: TargetStatus) -> some View {
        if let forecast = TargetForecast.compute(status: status, hourlyRate: project.hourlyRate,
                                                 now: timer.now, schedule: AppSettings.reminders) {
            let (label, tint): (String, Color) = switch forecast.verdict {
            case .reached: ("cíl splněn", .green)
            case .realistic: ("reálné", .green)
            case .tight: ("napjaté", .orange)
            case .unrealistic: ("nereálné", .red)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if forecast.verdict != .reached {
                        Text("Zbývá \(CzFormat.hours(seconds: forecast.remainingSeconds)) do cíle")
                    }
                    Text(label).fontWeight(.semibold).foregroundStyle(tint)
                }
                .font(.caption)
                if forecast.verdict != .reached {
                    Text(capacityText(forecast)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func capacityText(_ forecast: TargetForecast) -> String {
        guard let perDay = forecast.requiredPerDaySeconds else {
            return "Do konce měsíce už nezbývá žádná pracovní doba."
        }
        let days = forecast.workDaysLeft
        let noun = days == 1 ? "pracovní den" : (2...4).contains(days) ? "pracovní dny" : "pracovních dnů"
        return "Do konce měsíce \(days) \(noun) (kapacita \(CzFormat.hours(seconds: forecast.capacitySeconds))), potřeba průměrně \(CzFormat.hours(seconds: perDay)) denně."
    }

    private struct MonthAmount: Identifiable {
        let month: Date
        let amount: Double
        let position: TargetStatus.Position
        var id: Date { month }
    }

    private func yearTargetChart(_ project: Project, year: Int, until current: ReportMonth, rounding: RoundingOption) -> some View {
        let target = project.targetAmount ?? 0
        let points: [MonthAmount] = (1...12).compactMap { number in
            let month = ReportMonth(year: year, month: number)
            guard month <= current,
                  let status = project.targetStatus(now: timer.now, rounding: rounding, month: month) else { return nil }
            return MonthAmount(month: month.firstDay, amount: NSDecimalNumber(decimal: status.amount).doubleValue,
                               position: status.position)
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(project.name) · cíl \(CzFormat.money(target, currency: project.currency)) měsíčně")
                .font(.subheadline.bold())
            Chart {
                ForEach(points) { point in
                    BarMark(x: .value("Měsíc", point.month, unit: .month), y: .value("Částka", point.amount))
                        .foregroundStyle(color(for: point.position))
                }
                RuleMark(y: .value("Cíl", NSDecimalNumber(decimal: target).doubleValue))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
            }
            .chartXScale(domain: ReportMonth(year: year, month: 1).firstDay...ReportMonth(year: year + 1, month: 1).firstDay)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel { if let amount = value.as(Double.self) { Text("\(Int(amount / 1000)) tis.") } }
                }
            }
            .frame(height: 130)
        }
    }

    // MARK: Popisky

    private var previousLabel: String {
        switch period {
        case .week: "minulý týden"
        case .month: "minulý měsíc"
        case .year: "minulý rok"
        }
    }

    private func rangeTitle(_ stats: Stats) -> String {
        let calendar = Calendar.prague
        let first = stats.interval.start
        let last = stats.interval.end.addingTimeInterval(-1)
        switch period {
        case .week:
            let sameMonth = calendar.component(.month, from: first) == calendar.component(.month, from: last)
            let day = calendar.component(.day, from: first), month = calendar.component(.month, from: first)
            let startText = sameMonth ? "\(day)." : "\(day). \(month)."
            return "\(startText)–\(CzFormat.date(last))"
        case .month:
            return CzFormat.month(ReportMonth(containing: first))
        case .year:
            return "\(calendar.component(.year, from: first))"
        }
    }
}
