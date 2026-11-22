import '../combat/encounter.dart';
import '../log/log_event.dart';
import '../log/log_repository.dart';
import '../rules/exhaustion_rules.dart';
import '../rules/ruleset.dart';
import '../settings/app_settings.dart';
import 'character.dart';
import 'character_repository.dart';

/// Sets the exhaustion level of stored characters, following the ruleset
/// currently set in [AppSettings] (see `ExhaustionRules`). Long rests lower
/// it (see `RestService`).
///
/// A character on the combat list is changed through its combatant
/// (`Encounter.setExhaustion`), so combat and character stay the same.
class ExhaustionService {
  ExhaustionService({
    required this._characters,
    required this._log,
    required this._settings,
    required this._encounter,
  });

  final CharacterRepository _characters;
  final LogRepository _log;
  final AppSettings _settings;
  final Encounter _encounter;

  Ruleset get _rules => _settings.ruleset;

  /// The ruleset exhaustion follows right now.
  Ruleset get ruleset => _rules;

  /// Sets the exhaustion of [given] to [level] and logs it. At the highest
  /// level the character dies; lowering it again does not bring the
  /// character back. Under the 2014 rules, hit points above the halved
  /// maximum drop to it. Returns the character as stored afterwards.
  ///
  /// Nothing is logged if [level] is the current one. A [level] outside 0
  /// to [maxExhaustion] throws an [ArgumentError] and changes nothing.
  Future<Character> set(Character given, int level) async {
    if (level < 0 || level > maxExhaustion) {
      throw ArgumentError.value(level, 'level', 'must be 0 to $maxExhaustion');
    }
    final id = given.id!;
    if (_encounter.combatantOf(id) case final combatant?) {
      await _encounter.setExhaustion(combatant, level);
      await _encounter.flush();
      return _stored(given);
    }

    // Pending combat changes go first, so this save builds on them.
    await _encounter.flush();
    final character = await _stored(given);
    final before = character.exhaustion;
    if (level == before) return character;

    character.exhaustion = level;
    final maxHp = character.maxHpUnder(_rules);
    if (character.hp > maxHp) character.hp = maxHp;
    final dies = _rules.exhaustionKills(level) && !character.isDead;
    if (dies) {
      character
        ..isDead = true
        ..isStable = false
        ..hp = 0
        ..tempHp = 0
        ..deathSaveSuccesses = 0
        ..deathSaveFailures = 0;
    }
    await _characters.save(character);
    await _log.add(
      ExhaustionEvent(
        name: character.name,
        before: before,
        after: level,
        ruleset: _rules.id,
      ),
    );
    if (dies) {
      await _log.add(CombatantDiedEvent(character.name, exhaustion: true));
    }
    return character;
  }

  Future<Character> _stored(Character given) async {
    final character = await _characters.byId(given.id!);
    if (character == null) {
      throw ArgumentError.value(given, 'character', 'is not stored');
    }
    return character;
  }
}
