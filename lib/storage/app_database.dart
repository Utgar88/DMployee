import 'package:sqflite/sqflite.dart';

/// Opens (and if needed creates or upgrades) the app's single database at
/// [path]. Log, combat state and characters all live in it.
///
/// [factory] defaults to the device database; tests pass an FFI factory.
///
/// Changing the structure: raise the version, add the new step to
/// [_upgrade] and make [_create] produce the same end result.
Future<Database> openAppDatabase({
  required String path,
  DatabaseFactory? factory,
}) {
  return (factory ?? databaseFactory).openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 3,
      // Always a fresh connection: tests rely on separate in-memory
      // databases.
      singleInstance: false,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _create,
      onUpgrade: _upgrade,
    ),
  );
}

Future<void> _create(Database db, int version) async {
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
  await _createEncounterState(db);
  await _createCharacters(db);
}

Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) await _createEncounterState(db);
  if (oldVersion < 3) await _createCharacters(db);
}

/// Version 2: one row holding the current combat as JSON.
Future<void> _createEncounterState(Database db) {
  return db.execute('''
    CREATE TABLE encounter_state (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      payload TEXT NOT NULL
    )
  ''');
}

/// Version 3: the player characters, one row each with their values as
/// JSON.
Future<void> _createCharacters(Database db) {
  return db.execute('''
    CREATE TABLE characters (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      payload TEXT NOT NULL
    )
  ''');
}
