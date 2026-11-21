import 'dart:convert';

import 'character.dart';

/// Storage for the player characters, so they survive closing the app.
abstract class CharacterRepository {
  /// All characters, sorted by name without regard to case.
  Future<List<Character>> all();

  /// The character with [id], or null if there is none.
  Future<Character?> byId(int id);

  /// Stores [character]. A character without id is added and gets one; a
  /// character with id replaces the stored one. Returns [character].
  Future<Character> save(Character character);

  /// Removes the character with [id]; does nothing if there is none.
  Future<void> delete(int id);
}

/// Sorts [characters] by name without regard to case.
List<Character> sortedByName(Iterable<Character> characters) =>
    characters.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

/// Keeps characters in memory only. Used in tests.
///
/// Stores copies, so changing a character object afterwards does not change
/// what is stored, just like with a database.
class InMemoryCharacterRepository implements CharacterRepository {
  final _payloads = <int, String>{};
  int _nextId = 1;

  Character _decode(String payload) =>
      Character.fromJson((jsonDecode(payload) as Map).cast<String, Object?>());

  @override
  Future<List<Character>> all() async =>
      sortedByName(_payloads.values.map(_decode));

  @override
  Future<Character?> byId(int id) async {
    final payload = _payloads[id];
    return payload == null ? null : _decode(payload);
  }

  @override
  Future<Character> save(Character character) async {
    character.id ??= _nextId++;
    _payloads[character.id!] = jsonEncode(character.toJson());
    return character;
  }

  @override
  Future<void> delete(int id) async => _payloads.remove(id);
}
