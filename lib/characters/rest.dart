import 'dart:math';

import '../combat/encounter.dart';
import '../dice/dice_expression.dart';
import '../dice/dice_roller.dart';
import '../dice/modifier.dart';
import '../log/log_event.dart';
import '../log/log_repository.dart';
import '../log/roll_record.dart';
import '../rules/rest_rules.dart';
import '../rules/ruleset.dart';
import '../settings/app_settings.dart';
import 'ability.dart';
import 'character.dart';
import 'character_repository.dart';

/// Short and long rests for stored characters, following the ruleset
/// currently set in [AppSettings] (see `RestRules`).
///
/// Works on the stored state of each character. A character that is still
/// in the encounter gets the new state there too. No rest is possible while
/// a combat runs.
class RestService {
  RestService({
    required this._characters,
    required this._log,
    required this._settings,
    required this._encounter,
    DiceRoller? roller,
  }) : _roller = roller ?? DiceRoller();

  final CharacterRepository _characters;
  final LogRepository _log;
  final AppSettings _settings;
  final Encounter _encounter;
  final DiceRoller _roller;

  Ruleset get _rules => _settings.ruleset;

  /// The ruleset rests follow right now.
  Ruleset get ruleset => _rules;

  /// Why [character] would get nothing from a rest of [kind] under the
  /// current rules; null if it can rest.
  RestBlocker? blockerFor(Character character, RestKind kind) {
    if (character.isDead) return RestBlocker.dead;
    if (character.hp <= 0 && !character.isStable) return RestBlocker.dying;
    final minHp = switch (kind) {
      RestKind.short => _rules.minHpForShortRest,
      RestKind.long => _rules.minHpForLongRest,
    };
    if (character.hp < minHp) return RestBlocker.tooFewHp;
    return null;
  }

  /// Whether [character] can spend a hit die now: may take a short rest,
  /// has a hit die left and is hurt.
  bool canSpendHitDie(Character character) =>
      blockerFor(character, RestKind.short) == null &&
      character.hitDiceRemaining > 0 &&
      character.hp < character.maxHp;

  /// Each of [characters] takes a short rest; logged per character. Pact
  /// magic slots come back; hit dice are spent afterwards with
  /// [spendHitDie].
  ///
  /// Throws a [StateError] while a combat runs.
  Future<void> shortRest(List<Character> characters) async {
    _checkNoCombat();
    for (final given in characters) {
      final character = await _current(given);
      final blocker = blockerFor(character, RestKind.short);
      final pactRegained = blocker == null ? character.pactSlotsUsed : 0;
      if (pactRegained > 0) {
        character.pactSlotsUsed = 0;
        await _characters.save(character);
      }
      await _log.add(
        _restEvent(
          character,
          RestKind.short,
          blocker: blocker,
          pactSlotsRegained: pactRegained,
        ),
      );
    }
  }

  /// Each of [characters] takes a long rest: full hit points, temporary hit
  /// points end, spent hit dice come back by the rules, all spell slots and
  /// pact magic slots come back. Characters the rest
  /// does not help keep their state; the log says why.
  ///
  /// Throws a [StateError] while a combat runs.
  Future<void> longRest(List<Character> characters) async {
    _checkNoCombat();
    for (final given in characters) {
      final character = await _current(given);
      final blocker = blockerFor(character, RestKind.long);
      final before = (
        hp: character.hp,
        tempHp: character.tempHp,
        hitDice: character.hitDiceRemaining,
        slotsUsed: character.slotsUsed.values.fold(0, (a, b) => a + b),
        pactSlotsUsed: character.pactSlotsUsed,
      );
      if (blocker == null) {
        character.slotsUsed.clear();
        character.pactSlotsUsed = 0;
        final regained = _rules.hitDiceRegainedOnLongRest(
          character.hitDiceTotal,
        );
        character
          ..hp = character.maxHp
          ..tempHp = 0
          ..deathSaveSuccesses = 0
          ..deathSaveFailures = 0
          ..isStable = false
          ..hitDiceSpent = max(0, character.hitDiceSpent - regained);
        await _store(character);
      }
      await _log.add(
        _restEvent(
          character,
          RestKind.long,
          blocker: blocker,
          hpBefore: before.hp,
          tempHpBefore: before.tempHp,
          hitDiceBefore: before.hitDice,
          slotsRegained: blocker == null ? before.slotsUsed : 0,
          pactSlotsRegained: blocker == null ? before.pactSlotsUsed : 0,
        ),
      );
    }
  }

  /// [character] spends one hit die and regains hit points: the die (rolled,
  /// or [manualFace] if rolled at the table) plus the constitution
  /// modifier, adjusted by the rules. Returns the character as stored
  /// afterwards.
  ///
  /// Throws a [StateError] while a combat runs or if [canSpendHitDie] is
  /// false, an [ArgumentError] if [manualFace] does not fit the hit die.
  Future<Character> spendHitDie(Character given, {int? manualFace}) async {
    _checkNoCombat();
    final character = await _current(given);
    if (!canSpendHitDie(character)) {
      throw StateError('${character.name} cannot spend a hit die now');
    }
    final constitution = Modifier(
      Ability.constitution.label,
      character.modifier(Ability.constitution),
    );
    final roll = manualFace == null
        ? RollRecord.fromRoll(
            _roller.roll(
              DiceExpression(count: 1, sides: character.hitDie),
              modifiers: [constitution],
            ),
          )
        : RollRecord.manualDice(
            count: 1,
            sides: character.hitDie,
            sum: manualFace,
            modifiers: [constitution],
          );
    final healing = _rules.hitDieHealing(roll.total);
    final hpBefore = character.hp;
    character
      ..hp = min(character.maxHp, character.hp + healing)
      ..hitDiceSpent = character.hitDiceSpent + 1;
    if (character.hp > 0) {
      character
        ..deathSaveSuccesses = 0
        ..deathSaveFailures = 0
        ..isStable = false;
    }
    await _store(character);
    await _log.add(
      HitDieEvent(
        name: character.name,
        ruleset: _rules.id,
        roll: roll,
        healing: healing,
        hpBefore: hpBefore,
        hpAfter: character.hp,
        maxHp: character.maxHp,
        hitDiceLeft: character.hitDiceRemaining,
        hitDiceTotal: character.hitDiceTotal,
      ),
    );
    return character;
  }

  void _checkNoCombat() {
    if (_encounter.isRunning) {
      throw StateError('No rest while a combat runs');
    }
  }

  /// The stored state of [character], after pending combat changes.
  Future<Character> _current(Character character) async {
    await _encounter.flush();
    final stored = await _characters.byId(character.id!);
    if (stored == null) {
      throw ArgumentError.value(character, 'character', 'is not stored');
    }
    return stored;
  }

  Future<void> _store(Character character) async {
    await _characters.save(character);
    _encounter.takeCharacterState(character);
  }

  RestEvent _restEvent(
    Character character,
    RestKind kind, {
    RestBlocker? blocker,
    int? hpBefore,
    int tempHpBefore = 0,
    int? hitDiceBefore,
    int slotsRegained = 0,
    int pactSlotsRegained = 0,
  }) => RestEvent(
    name: character.name,
    kind: kind,
    ruleset: _rules.id,
    blocker: blocker,
    hpBefore: hpBefore ?? character.hp,
    hpAfter: character.hp,
    maxHp: character.maxHp,
    tempHpBefore: tempHpBefore,
    hitDiceBefore: hitDiceBefore ?? character.hitDiceRemaining,
    hitDiceAfter: character.hitDiceRemaining,
    hitDiceTotal: character.hitDiceTotal,
    slotsRegained: slotsRegained,
    pactSlotsRegained: pactSlotsRegained,
  );
}
