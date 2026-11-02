import Foundation

enum EntryValidationError: LocalizedError, Equatable {
    case endNotAfterStart
    case overlap
    case startInFuture

    var errorDescription: String? {
        switch self {
        case .endNotAfterStart: "Konec musí být po začátku."
        case .overlap: "Záznam se překrývá s jiným záznamem."
        case .startInFuture: "Začátek nemůže být v budoucnu."
        }
    }
}

struct EntryInterval: Equatable {
    var id: UUID
    var start: Date
    /// `nil` = běží, počítá se do `now`.
    var end: Date?
}

enum EntryValidator {
    /// `existing` jsou všechny ostatní záznamy; upravovaný záznam se musí vyloučit přes `editing`.
    static func validate(
        start: Date,
        end: Date,
        editing: UUID? = nil,
        existing: [EntryInterval],
        now: Date = Date()
    ) throws {
        guard end > start else { throw EntryValidationError.endNotAfterStart }
        for other in existing where other.id != editing {
            let otherEnd = other.end ?? now
            if start < otherEnd && other.start < end {
                throw EntryValidationError.overlap
            }
        }
    }
}
