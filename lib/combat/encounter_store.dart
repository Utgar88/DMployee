import 'dart:convert';

/// Storage for the current combat, so it survives closing the app.
///
/// The state is one JSON-compatible map produced by `Encounter`; the store
/// does not need to know what is in it.
abstract class EncounterStore {
  /// The saved combat, or null if nothing was saved yet.
  Future<Map<String, Object?>?> load();

  /// Replaces the saved combat with [state].
  Future<void> save(Map<String, Object?> state);
}

/// Keeps the combat in memory only. Used in tests.
class InMemoryEncounterStore implements EncounterStore {
  String? _payload;

  @override
  Future<Map<String, Object?>?> load() async {
    final payload = _payload;
    if (payload == null) return null;
    return (jsonDecode(payload) as Map).cast<String, Object?>();
  }

  @override
  Future<void> save(Map<String, Object?> state) async {
    _payload = jsonEncode(state);
  }
}
