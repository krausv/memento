import SQLite3
import XCTest
@testable import Memento

final class StoreLocationTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("memento-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeDatabase(at url: URL, tables: [String]) {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        for table in tables { sqlite3_exec(db, "CREATE TABLE \(table) (id INTEGER)", nil, nil, nil) }
        sqlite3_close(db)
    }

    func testMigratesLegacyMementoStoreAndKeepsOriginal() throws {
        let legacy = dir.appendingPathComponent("default.store")
        makeDatabase(at: legacy, tables: ["ZTIMEENTRY", "ZPROJECT"])
        let target = try StoreLocation.prepare(appSupport: dir)
        XCTAssertEqual(target, StoreLocation.storeURL(in: dir))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path), "původní soubor se nemaže")
        XCTAssertTrue(StoreLocation.isMementoStore(target))
    }

    func testIgnoresForeignDefaultStore() throws {
        makeDatabase(at: dir.appendingPathComponent("default.store"), tables: ["ZSOMETHING"])
        let target = try StoreLocation.prepare(appSupport: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    func testDoesNotOverwriteExistingStore() throws {
        let target = StoreLocation.storeURL(in: dir)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("novy".utf8).write(to: target)
        makeDatabase(at: dir.appendingPathComponent("default.store"), tables: ["ZTIMEENTRY", "ZPROJECT"])
        try StoreLocation.prepare(appSupport: dir)
        XCTAssertEqual(try Data(contentsOf: target), Data("novy".utf8))
    }
}
