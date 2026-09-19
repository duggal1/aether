import Foundation
import SQLite3
import Synchronization

public enum SQLiteValue: Hashable, Sendable {
  case null
  case integer(Int64)
  case real(Double)
  case text(String)
  case blob(Data)
}

public enum SQLiteError: Error, Sendable, CustomStringConvertible {
  case open(String)
  case prepare(String)
  case step(String)
  case bind(String)
  case transaction(String)

  public var description: String {
    switch self {
    case .open(let value): return "SQLite open failed: \(value)"
    case .prepare(let value): return "SQLite prepare failed: \(value)"
    case .step(let value): return "SQLite step failed: \(value)"
    case .bind(let value): return "SQLite bind failed: \(value)"
    case .transaction(let value): return "SQLite transaction failed: \(value)"
    }
  }
}

public struct SQLiteConnection {
  let handle: OpaquePointer

  public func exec(_ sql: String) throws {
    var message: UnsafeMutablePointer<CChar>?
    let code = sqlite3_exec(handle, sql, nil, nil, &message)
    if code != SQLITE_OK {
      let detail = message.map { String(cString: $0) } ?? "code \(code)"
      sqlite3_free(message)
      throw SQLiteError.prepare(detail)
    }
  }

  @discardableResult
  public func execute(_ sql: String, _ args: [SQLiteValue] = []) throws -> Int {
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(args, to: statement)
    let code = sqlite3_step(statement)
    guard code == SQLITE_DONE else {
      throw SQLiteError.step(String(cString: sqlite3_errmsg(handle)))
    }
    return Int(sqlite3_changes(handle))
  }

  public func query(_ sql: String, _ args: [SQLiteValue] = []) throws -> [[SQLiteValue]] {
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(args, to: statement)
    var rows: [[SQLiteValue]] = []
    while true {
      let code = sqlite3_step(statement)
      if code == SQLITE_DONE { break }
      guard code == SQLITE_ROW else {
        throw SQLiteError.step(String(cString: sqlite3_errmsg(handle)))
      }
      let count = Int(sqlite3_column_count(statement))
      var row: [SQLiteValue] = []
      row.reserveCapacity(count)
      for index in 0..<count {
        row.append(value(at: Int32(index), in: statement))
      }
      rows.append(row)
    }
    return rows
  }

  private func prepare(_ sql: String) throws -> OpaquePointer {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
      let statement
    else {
      throw SQLiteError.prepare(String(cString: sqlite3_errmsg(handle)))
    }
    return statement
  }

  private func bind(_ args: [SQLiteValue], to statement: OpaquePointer) throws {
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (offset, arg) in args.enumerated() {
      let index = Int32(offset + 1)
      let code: Int32
      switch arg {
      case .null:
        code = sqlite3_bind_null(statement, index)
      case .integer(let value):
        code = sqlite3_bind_int64(statement, index, value)
      case .real(let value):
        code = sqlite3_bind_double(statement, index, value)
      case .text(let value):
        code = value.withCString { pointer in
          sqlite3_bind_text(statement, index, pointer, -1, transient)
        }
      case .blob(let value):
        code = value.withUnsafeBytes { bytes in
          sqlite3_bind_blob(
            statement, index, bytes.baseAddress, Int32(value.count), transient)
        }
      }
      guard code == SQLITE_OK else {
        throw SQLiteError.bind(String(cString: sqlite3_errmsg(handle)))
      }
    }
  }

  private func value(at index: Int32, in statement: OpaquePointer) -> SQLiteValue {
    switch sqlite3_column_type(statement, index) {
    case SQLITE_INTEGER:
      return .integer(sqlite3_column_int64(statement, index))
    case SQLITE_FLOAT:
      return .real(sqlite3_column_double(statement, index))
    case SQLITE_TEXT:
      guard let pointer = sqlite3_column_text(statement, index) else { return .null }
      let count = Int(sqlite3_column_bytes(statement, index))
      let data = Data(bytes: pointer, count: count)
      return .text(String(data: data, encoding: .utf8) ?? "")
    case SQLITE_BLOB:
      let count = Int(sqlite3_column_bytes(statement, index))
      guard count > 0, let pointer = sqlite3_column_blob(statement, index) else {
        return .blob(Data())
      }
      return .blob(Data(bytes: pointer, count: count))
    default:
      return .null
    }
  }
}

public final class SQLiteStore: Sendable {
  private struct State: @unchecked Sendable {
    var handle: OpaquePointer?
  }

  private let state: Mutex<State>
  public let path: String

  public init(path: String, pageCacheKB: Int = 4096) throws {
    var handle: OpaquePointer?
    let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
    guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
      throw SQLiteError.open(path)
    }
    self.path = path
    self.state = Mutex(State(handle: handle))
    sqlite3_busy_timeout(handle, 5000)
    let connection = SQLiteConnection(handle: handle)
    try connection.exec("PRAGMA journal_mode=WAL;")
    try connection.exec("PRAGMA synchronous=NORMAL;")
    try connection.exec("PRAGMA foreign_keys=ON;")
    try connection.exec("PRAGMA temp_store=MEMORY;")
    try connection.exec("PRAGMA cache_size=-\(max(512, pageCacheKB));")
  }

  deinit {
    state.withLock { state in
      if let handle = state.handle {
        sqlite3_close(handle)
        state.handle = nil
      }
    }
  }

  public func close() {
    state.withLock { state in
      if let handle = state.handle {
        sqlite3_close(handle)
        state.handle = nil
      }
    }
  }

  public func exec(_ sql: String) throws {
    try state.withLock { state in
      guard let handle = state.handle else { throw SQLiteError.open(path) }
      try SQLiteConnection(handle: handle).exec(sql)
    }
  }

  @discardableResult
  public func execute(_ sql: String, _ args: [SQLiteValue] = []) throws -> Int {
    try state.withLock { state in
      guard let handle = state.handle else { throw SQLiteError.open(path) }
      return try SQLiteConnection(handle: handle).execute(sql, args)
    }
  }

  public func query(_ sql: String, _ args: [SQLiteValue] = []) throws -> [[SQLiteValue]] {
    try state.withLock { state in
      guard let handle = state.handle else { throw SQLiteError.open(path) }
      return try SQLiteConnection(handle: handle).query(sql, args)
    }
  }

  public func withTransaction<T>(_ body: (SQLiteConnection) throws -> T) throws -> T {
    try state.withLock { state in
      guard let handle = state.handle else { throw SQLiteError.open(path) }
      let connection = SQLiteConnection(handle: handle)
      try connection.exec("BEGIN IMMEDIATE;")
      do {
        let value = try body(connection)
        try connection.exec("COMMIT;")
        return value
      } catch {
        try? connection.exec("ROLLBACK;")
        throw error
      }
    }
  }
}
