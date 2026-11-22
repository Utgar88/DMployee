import 'package:sqflite/sqflite.dart';

import 'settings_repository.dart';

/// Stores settings permanently in the app database (see `openAppDatabase`),
/// one row per setting.
class SqliteSettingsRepository implements SettingsRepository {
  SqliteSettingsRepository(this._database);

  final Database _database;

  @override
  Future<String?> read(String key) async {
    final rows = await _database.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.single['value']! as String;
  }

  @override
  Future<void> write(String key, String value) => _database.insert('settings', {
    'key': key,
    'value': value,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}
