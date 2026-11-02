import Foundation

/// Jeden řádek v seznamu záznamů: samostatný záznam, nebo řetěz navázaných (Pokračovat) záznamů.
/// Úpravy, mazání i další navázání se vztahují k poslednímu záznamu řetězu.
struct EntryRowGroup: Identifiable {
    let entries: [TimeEntry]

    var id: UUID { last.id }
    var first: TimeEntry { entries[0] }
    var last: TimeEntry { entries[entries.count - 1] }
    var project: Project? { last.project }
    var start: Date { first.start }
    var end: Date? { last.end }
    var isRunning: Bool { last.isRunning }
    var tags: [Tag] { last.tags }

    /// Poslední neprázdná poznámka (v navázaném záznamu bývá zahrnutá i ta předchozí).
    var note: String? { entries.last(where: { !($0.note ?? "").isEmpty })?.note }

    func duration(at now: Date) -> TimeInterval { entries.reduce(0) { $0 + $1.duration(at: now) } }

    /// Řetězy podle `EntryChains`, nejnovější první.
    static func make(_ entries: [TimeEntry]) -> [EntryRowGroup] {
        EntryChains.group(
            entries, project: { $0.project?.id }, start: \.start, end: { $0.end }, continues: { $0.carriedSeconds > 0 }
        )
        .map(EntryRowGroup.init)
        .sorted { $0.start > $1.start }
    }
}
