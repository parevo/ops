import Foundation
import SQLite3

public final class MemoryEngine: MemoryServiceProtocol, @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()
    private let dbPath: String
    
    public init() {
        // App support directory for database storage
        let fileManager = FileManager.default
        let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbFolder = appSupportDir.appendingPathComponent("ParevoOps", isDirectory: true)
        
        try? fileManager.createDirectory(at: dbFolder, withIntermediateDirectories: true, attributes: nil)
        self.dbPath = dbFolder.appendingPathComponent("memory_engine.sqlite").path
        
        openDatabase()
        createTables()
    }
    
    private func openDatabase() {
        lock.lock()
        defer { lock.unlock() }
        
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("Failed to open SQLite database at path: \(dbPath)")
        }
    }
    
    private func createTables() {
        let sql = """
        CREATE TABLE IF NOT EXISTS command_history (
            id TEXT PRIMARY KEY,
            command TEXT NOT NULL,
            directory TEXT NOT NULL,
            exit_code INTEGER NOT NULL,
            is_success INTEGER NOT NULL,
            server_id TEXT,
            project_id TEXT,
            timestamp REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_cmd_history_timestamp ON command_history(timestamp);
        CREATE INDEX IF NOT EXISTS idx_cmd_history_command ON command_history(command);
        """
        
        lock.lock()
        defer { lock.unlock() }
        
        var errMsg: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let err = errMsg {
                print("Error creating tables: \(String(cString: err))")
                sqlite3_free(errMsg)
            }
        }
    }
    
    private func recordCommandSync(
        command: String,
        directory: String,
        exitCode: Int,
        isSuccess: Bool,
        serverId: UUID?,
        projectId: UUID?
    ) {
        let sql = """
        INSERT INTO command_history (id, command, directory, exit_code, is_success, server_id, project_id, timestamp)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        lock.lock()
        defer { lock.unlock() }
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        
        let id = UUID().uuidString
        let timestamp = Date().timeIntervalSince1970
        let successVal = isSuccess ? 1 : 0
        
        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (command as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (directory as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 4, Int32(exitCode))
        sqlite3_bind_int(stmt, 5, Int32(successVal))
        
        if let sId = serverId {
            sqlite3_bind_text(stmt, 6, (sId.uuidString as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        
        if let pId = projectId {
            sqlite3_bind_text(stmt, 7, (pId.uuidString as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 7)
        }
        
        sqlite3_bind_double(stmt, 8, timestamp)
        
        if sqlite3_step(stmt) != SQLITE_DONE {
            print("Failed to insert command log into SQLite.")
        }
        sqlite3_finalize(stmt)
    }
    
    public func recordCommand(
        command: String,
        directory: String,
        exitCode: Int,
        isSuccess: Bool,
        serverId: UUID?,
        projectId: UUID?
    ) async throws {
        recordCommandSync(
            command: command,
            directory: directory,
            exitCode: exitCode,
            isSuccess: isSuccess,
            serverId: serverId,
            projectId: projectId
        )
    }
    
    private func getSmartSuggestionsSync(input: String, serverId: UUID?, projectId: UUID?) -> [String] {
        var sql = """
        SELECT command, COUNT(*) as count
        FROM command_history
        """
        var conditions: [String] = []
        
        if !input.isEmpty {
            conditions.append("command LIKE ?")
        }
        if let sId = serverId {
            conditions.append("server_id = '\(sId.uuidString)'")
        }
        if let pId = projectId {
            conditions.append("project_id = '\(pId.uuidString)'")
        }
        
        if !conditions.isEmpty {
            sql += " WHERE " + conditions.joined(separator: " AND ")
        }
        
        sql += " GROUP BY command ORDER BY count DESC LIMIT 8;"
        
        lock.lock()
        defer { lock.unlock() }
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        
        if !input.isEmpty {
            let wild = "%\(input)%"
            sqlite3_bind_text(stmt, 1, (wild as NSString).utf8String, -1, nil)
        }
        
        var results: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let val = sqlite3_column_text(stmt, 0) {
                results.append(String(cString: val))
            }
        }
        sqlite3_finalize(stmt)
        return results
    }
    
    public func getSmartSuggestions(input: String, serverId: UUID?, projectId: UUID?) async throws -> [String] {
        return getSmartSuggestionsSync(input: input, serverId: serverId, projectId: projectId)
    }
    
    private func getPatternNextStepSync(currentCommand: String, serverId: UUID?, projectId: UUID?) -> String? {
        let sql = """
        SELECT next_cmd, COUNT(*) as sequence_count
        FROM (
            SELECT command, LEAD(command) OVER (ORDER BY timestamp) as next_cmd
            FROM command_history
            WHERE 1=1
        )
        WHERE command = ? AND next_cmd IS NOT NULL
        GROUP BY next_cmd
        ORDER BY sequence_count DESC
        LIMIT 1;
        """
        
        lock.lock()
        defer { lock.unlock() }
        
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        
        sqlite3_bind_text(stmt, 1, (currentCommand as NSString).utf8String, -1, nil)
        
        var nextStep: String?
        if sqlite3_step(stmt) == SQLITE_ROW {
            if let val = sqlite3_column_text(stmt, 0) {
                nextStep = String(cString: val)
            }
        }
        sqlite3_finalize(stmt)
        return nextStep
    }
    
    public func getPatternNextStep(currentCommand: String, serverId: UUID?, projectId: UUID?) async throws -> String? {
        return getPatternNextStepSync(currentCommand: currentCommand, serverId: serverId, projectId: projectId)
    }
    
    deinit {
        if let d = db {
            sqlite3_close(d)
        }
    }
}
