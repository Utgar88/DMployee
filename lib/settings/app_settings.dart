import 'package:flutter/foundation.dart';

import '../rules/ruleset.dart';
import 'settings_repository.dart';

/// The settings that apply to the whole app. Changes take effect at once,
/// are stored and are announced to listeners.
class AppSettings extends ChangeNotifier {
  /// Settings with default values, kept in memory only.
  AppSettings({SettingsRepository? repository})
    : this._(repository ?? InMemorySettingsRepository(), Ruleset.standard);

  AppSettings._(this._repository, this._ruleset);

  static const _rulesetKey = 'ruleset';

  /// The settings stored in [repository]; missing or unknown values get
  /// their default.
  static Future<AppSettings> load(SettingsRepository repository) async {
    final ruleset = Ruleset.byId(await repository.read(_rulesetKey));
    return AppSettings._(repository, ruleset ?? Ruleset.standard);
  }

  final SettingsRepository _repository;

  Ruleset _ruleset;

  /// The rule book the app follows where the rules differ.
  Ruleset get ruleset => _ruleset;

  Future<void> setRuleset(Ruleset ruleset) async {
    if (ruleset == _ruleset) return;
    _ruleset = ruleset;
    notifyListeners();
    await _repository.write(_rulesetKey, ruleset.id);
  }
}
