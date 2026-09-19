import Foundation
import SQLite3

enum SQLBind: Sendable {
    case text(String)
    case int(Int64)
    case null
}

struct SQLRow: Sendable {
    var values: [String: String]

    func string(_ column: String) -> String? {
        values[column]
    }

    func int(_ column: String) -> Int {
        Int(values[column] ?? "") ?? 0
    }
}

final class SQLDatabase: @unchecked Sendable {
    private var db: OpaquePointer?

    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(path, &handle, flags, nil)
        if openResult != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed (\(openResult))"
            sqlite3_close(handle)
            throw LibraryError.database(message)
        }
        db = handle
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA busy_timeout = 5000;")
        // Prefer WAL, but do not fail launch if an older connection left the file busy.
        _ = try? execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA synchronous = NORMAL;")
    }

    deinit {
        sqlite3_close(db)
    }

    var userVersion: Int {
        get throws {
            let rows = try query("PRAGMA user_version;")
            return rows.first?.int("user_version") ?? 0
        }
    }

    func setUserVersion(_ version: Int) throws {
        try execute("PRAGMA user_version = \(version);")
    }

    func execute(_ sql: String, _ bindings: [SQLBind] = []) throws {
        if bindings.isEmpty, sql.contains(";") {
            try executeScript(sql)
            return
        }
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(statement, bindings)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw LibraryError.database(errorMessage())
        }
    }

    private func executeScript(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? errorMessage()
            sqlite3_free(error)
            throw LibraryError.database(message)
        }
    }

    func checkpoint() throws {
        try execute("PRAGMA wal_checkpoint(FULL);")
    }

    func backup(to path: String) throws {
        try checkpoint()
        var dest: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(path, &dest, flags, nil)
        if openResult != SQLITE_OK {
            sqlite3_close(dest)
            throw LibraryError.database("Could not create a consistent library snapshot.")
        }
        defer { sqlite3_close(dest) }
        guard let backup = sqlite3_backup_init(dest, "main", db, "main") else {
            throw LibraryError.database(errorMessage())
        }
        defer { _ = sqlite3_backup_finish(backup) }
        var step = sqlite3_backup_step(backup, 256)
        while step == SQLITE_OK {
            step = sqlite3_backup_step(backup, 256)
        }
        guard step == SQLITE_DONE else {
            throw LibraryError.database("The library snapshot did not finish.")
        }
        try? SQLDatabase(path: path).checkpoint()
    }

    func query(_ sql: String, _ bindings: [SQLBind] = []) throws -> [SQLRow] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(statement, bindings)
        var rows: [SQLRow] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_ROW {
                rows.append(readRow(statement))
            } else if result == SQLITE_DONE {
                break
            } else {
                throw LibraryError.database(errorMessage())
            }
        }
        return rows
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            throw LibraryError.database(errorMessage())
        }
        return statement
    }

    private func bind(_ statement: OpaquePointer?, _ bindings: [SQLBind]) {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            switch binding {
            case .text(let value):
                _ = value.withCString { pointer in
                    sqlite3_bind_text(statement, index, pointer, -1, Self.transient)
                }
            case .int(let value):
                sqlite3_bind_int64(statement, index, value)
            case .null:
                sqlite3_bind_null(statement, index)
            }
        }
    }

    private func readRow(_ statement: OpaquePointer?) -> SQLRow {
        var values: [String: String] = [:]
        let count = sqlite3_column_count(statement)
        for index in 0..<count {
            guard let namePointer = sqlite3_column_name(statement, index) else { continue }
            let name = String(cString: namePointer)
            if sqlite3_column_type(statement, index) == SQLITE_NULL {
                continue
            }
            if let text = sqlite3_column_text(statement, index) {
                values[name] = String(cString: text)
            }
        }
        return SQLRow(values: values)
    }

    private func errorMessage() -> String {
        String(cString: sqlite3_errmsg(db))
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
