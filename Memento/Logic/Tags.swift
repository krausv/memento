import Foundation

enum TagColor: String, CaseIterable, Identifiable {
    case blue, green, orange, red, purple, pink, teal, gray

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: "Modrá"
        case .green: "Zelená"
        case .orange: "Oranžová"
        case .red: "Červená"
        case .purple: "Fialová"
        case .pink: "Růžová"
        case .teal: "Tyrkysová"
        case .gray: "Šedá"
        }
    }
}

enum TagRules {
    /// Název bez okrajových mezer; prázdný název štítek nevytvoří.
    static func normalized(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Názvy se porovnávají bez ohledu na velikost písmen a diakritiku, aby „Schůzka“ a „schuzka“ nebyly dva štítky.
    static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
