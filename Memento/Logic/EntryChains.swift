import Foundation

/// Navázané záznamy (akce Pokračovat) se ve výkazu, v částkách i v seznamech chovají jako jeden záznam.
/// Pravidlo je na jednom místě: záznam, který navazuje (`continues`), se připojí k poslednímu záznamu
/// téhož projektu, pokud ten už skončil a nepřesahuje do něj. Bez takového předchůdce zůstane samostatný.
enum EntryChains {
    /// Skupiny seřazené podle začátku prvního záznamu; uvnitř skupiny podle času.
    static func group<T>(
        _ items: [T],
        project: (T) -> UUID?,
        start: (T) -> Date,
        end: (T) -> Date?,
        continues: (T) -> Bool
    ) -> [[T]] {
        var groups: [[T]] = []
        var lastGroup: [UUID?: Int] = [:]
        for item in items.sorted(by: { start($0) < start($1) }) {
            let key = project(item)
            if continues(item), let index = lastGroup[key],
               let previous = groups[index].last, let previousEnd = end(previous), previousEnd <= start(item) {
                groups[index].append(item)
            } else {
                groups.append([item])
                lastGroup[key] = groups.count - 1
            }
        }
        return groups
    }
}
