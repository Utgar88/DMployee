import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'character.dart';
import 'character_repository.dart';

/// Stores characters permanently in the app database (see
/// `openAppDatabase`), one row per character with its values as JSON.
class SqliteCharacterRepository implements CharacterRepository {
  SqliteCharacterRepository(this._database);

  final Database _database;

  Character _fromRow(Map<String, Object?> row) => Character.fromJson(
    (jsonDecode(row['payload']! as String) as Map).cast<String, Object?>(),
  )..id = row['id']! as int;

  @override
  Future<List<Character>> all() async =>
      sortedByName((await _database.query('characters')).map(_fromRow));

  @override
  Future<Character?> byId(int id) async {
    final rows = await _database.query(
      'characters',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  @override
  Future<Character> save(Character character) async {
    final id = character.id;
    if (id == null) {
      character.id = await _database.insert('characters', {
        'payload': jsonEncode(character.toJson()),
      });
    } else {
      await _database.insert('characters', {
        'id': id,
        'payload': jsonEncode(character.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    return character;
  }

  @override
  Future<void> delete(int id) =>
      _database.delete('characters', where: 'id = ?', whereArgs: [id]);
}
