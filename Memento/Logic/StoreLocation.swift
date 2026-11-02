import Foundation
import SQLite3

/// Umístění databáze SwiftData. Výchozí `default.store` v Application Support sdílí každá nesandboxovaná
/// aplikace bez vlastního názvu úložiště, proto má Memento vlastní složku a soubor.
enum StoreLocation {
    static let folderName = "Memento"
    static let fileName = "Memento.store"
    static let legacyFileName = "default.store"

    static func appSupport() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static func storeURL(in appSupport: URL = appSupport()) -> URL {
        appSupport.appendingPathComponent(folderName, isDirectory: true).appendingPathComponent(fileName)
    }

    /// Vytvoří složku a při prvním spuštění zkopíruje starou `default.store` (jen když je to databáze Mementa).
    /// Původní soubory zůstávají nedotčené, aby šlo data v případě potřeby získat zpět.
    @discardableResult
    static func prepare(appSupport: URL = appSupport()) throws -> URL {
        let fm = FileManager.default
        let target = storeURL(in: appSupport)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: target.path) else { return target }

        let legacy = appSupport.appendingPathComponent(legacyFileName)
        guard fm.fileExists(atPath: legacy.path), isMementoStore(legacy) else { return target }
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: legacy.path + suffix)
            guard fm.fileExists(atPath: source.path) else { continue }
            try fm.copyItem(at: source, to: URL(fileURLWithPath: target.path + suffix))
        }
        return target
    }

    /// Databáze Mementa má tabulky `ZTIMEENTRY` a `ZPROJECT`; cizí `default.store` se nepřevezme.
    static func isMementoStore(_ url: URL) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return false
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        let sql = "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ('ZTIMEENTRY','ZPROJECT')"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW && sqlite3_column_int(statement, 0) == 2
    }
}
