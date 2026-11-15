import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'log_event.dart';
import 'log_repository.dart';

/// Stores the log permanently in a SQLite database.
///
/// Each entry keeps its event as a type name plus a JSON payload, so new
/// event types need no change to the database structure.
class SqliteLogRepository implements LogRepository {
  SqliteLogRepository._(this._database, this._now);

  /// Opens (and if needed creates) the log database at [path].
  ///
  /// [factory] defaults to the device database; tests pass an FFI factory.
  static Future<SqliteLogRepository> open({
    required String path,
    DatabaseFactory? factory,
    DateTime Function()? now,
  }) async {
    final database = await (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        // Always a fresh connection: tests rely on separate in-memory
        // databases.
        singleInstance: false,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _create,
      ),
    );
    return SqliteLogRepository._(database, now ?? DateTime.now);
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        started_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE log_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL REFERENCES sessions (id),
        timestamp INTEGER NOT NULL,
        type TEXT NOT NULL,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX log_entries_session ON log_entries (session_id, id)',
    );
  }

  final Database _database;
  final DateTime Function() _now;

  @override
  Future<Session> startSession(String name) async {
    final startedAt = _now();
    final id = await _database.insert('sessions', {
      'name': name,
      'started_at': startedAt.millisecondsSinceEpoch,
    });
    return Session(id: id, name: name, startedAt: startedAt);
  }

  @override
  Future<List<Session>> sessions() async {
    final rows = await _database.query('sessions', orderBy: 'id DESC');
    return rows.map(_sessionFromRow).toList();
  }

  @override
  Future<Session> activeSession() async {
    final rows = await _database.query(
      'sessions',
      orderBy: 'id DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return startSession(defaultSessionName(_now()));
    }
    return _sessionFromRow(rows.single);
  }

  @override
  Future<LogEntry> add(LogEvent event) async {
    final session = await activeSession();
    final timestamp = _now();
    final id = await _database.insert('log_entries', {
      'session_id': session.id,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'type': event.type,
      'payload': jsonEncode(event.toJson()),
    });
    return LogEntry(
      id: id,
      sessionId: session.id,
      timestamp: timestamp,
      event: event,
    );
  }

  @override
  Future<List<LogEntry>> entries({int? sessionId}) async {
    final rows = await _database.query(
      'log_entries',
      where: sessionId == null ? null : 'session_id = ?',
      whereArgs: sessionId == null ? null : [sessionId],
      orderBy: 'id DESC',
    );
    return [
      for (final row in rows)
        LogEntry(
          id: row['id']! as int,
          sessionId: row['session_id']! as int,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            row['timestamp']! as int,
          ),
          event: LogEvent.fromJson(
            row['type']! as String,
            (jsonDecode(row['payload']! as String) as Map)
                .cast<String, Object?>(),
          ),
        ),
    ];
  }

  @override
  Future<void> close() => _database.close();

  static Session _sessionFromRow(Map<String, Object?> row) {
    return Session(
      id: row['id']! as int,
      name: row['name']! as String,
      startedAt: DateTime.fromMillisecondsSinceEpoch(row['started_at']! as int),
    );
  }
}
