/// Storage for the app settings as named text values, so they survive
/// closing the app.
abstract class SettingsRepository {
  /// The value stored under [key], or null if there is none.
  Future<String?> read(String key);

  /// Stores [value] under [key], replacing an earlier value.
  Future<void> write(String key, String value);
}

/// Keeps settings in memory only. Used in tests and when no database is
/// given.
class InMemorySettingsRepository implements SettingsRepository {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}
