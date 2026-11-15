import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'encounter_store.dart';

/// Stores the current combat permanently, as a single row in the app
/// database (see `openAppDatabase`).
class SqliteEncounterStore implements EncounterStore {
  SqliteEncounterStore(this._database);

  final Database _database;

  @override
  Future<Map<String, Object?>?> load() async {
    final rows = await _database.query('encounter_state', limit: 1);
    if (rows.isEmpty) return null;
    return (jsonDecode(rows.single['payload']! as String) as Map)
        .cast<String, Object?>();
  }

  @override
  Future<void> save(Map<String, Object?> state) async {
    await _database.insert('encounter_state', {
      'id': 1,
      'payload': jsonEncode(state),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
