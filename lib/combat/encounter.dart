import 'dart:async';

import '../characters/character.dart';
import '../characters/character_repository.dart';
import '../dice/dice_expression.dart';
import '../dice/dice_roller.dart';
import '../dice/modifier.dart';
import '../log/log_event.dart';
import '../log/log_repository.dart';
import '../log/roll_record.dart';
import 'attack.dart';
import 'buff.dart';
import 'combatant.dart';
import 'condition.dart';
import 'damage.dart';
import 'encounter_store.dart';

/// Result of one attack.
class AttackOutcome {
  const AttackOutcome({
    required this.attackRoll,
    required this.hit,
    required this.critical,
    required this.damage,
    required this.targetDown,
    required this.event,
    this.damageRoll,
    this.damageEffect,
  });

  /// The attack as it was written to the log.
  final AttackEvent event;

  final RollRecord attackRoll;
  final bool hit;
  final bool critical;

  /// Null when the attack missed.
  final RollRecord? damageRoll;

  /// Damage dealt, after [damageEffect].
  final int damage;

  /// Resistance, vulnerability or immunity of the target that changed the
  /// rolled damage; null if none applied.
  final DamageEffect? damageEffect;

  /// The target dropped to 0 hit points through this attack.
  final bool targetDown;
}

/// A combat: combatants, initiative order, rounds and attacks following the
/// D&D 5e basic rules. Everything that happens is written to the log.
///
/// With a [EncounterStore] every change is saved, so the combat survives
/// closing the app; [Encounter.load] brings it back. Without a store the
/// state lives in memory only.
///
/// Combatants added with [addCharacter] stand for stored characters: with a
/// [CharacterRepository], every change writes their hit points, temporary
/// hit points and death saving throws back to the character.
class Encounter {
  Encounter({
    required this._log,
    DiceRoller? roller,
    this._store,
    this._characters,
  }) : _roller = roller ?? DiceRoller();

  /// The combat as it was last saved in [store]. Starts empty if nothing
  /// was saved yet or the saved state cannot be read.
  static Future<Encounter> load({
    required LogRepository log,
    required EncounterStore store,
    CharacterRepository? characters,
    DiceRoller? roller,
  }) async {
    final encounter = Encounter(
      log: log,
      store: store,
      characters: characters,
      roller: roller,
    );
    final state = await store.load();
    if (state != null) encounter._restore(state);
    return encounter;
  }

  final LogRepository _log;
  final DiceRoller _roller;
  final EncounterStore? _store;
  final CharacterRepository? _characters;

  /// The most recent save; later saves are queued behind it.
  Future<void> _lastSave = Future.value();
  final _combatants = <Combatant>[];

  int _round = 0;
  Combatant? _current;

  /// All combatants: in turn order while a combat runs, otherwise in the
  /// order they were added.
  List<Combatant> get combatants => List.unmodifiable(_combatants);

  bool get isRunning => _round > 0;

  /// Current round, 0 while no combat runs.
  int get round => _round;

  /// Whose turn it is; null while no combat runs.
  Combatant? get current => _current;

  Combatant add({
    required String name,
    required int armorClass,
    required int maxHp,
    int initiativeBonus = 0,
    bool isPlayer = false,
    List<Attack> attacks = const [],
  }) {
    final combatant = Combatant(
      name: name,
      armorClass: armorClass,
      maxHp: maxHp,
      initiativeBonus: initiativeBonus,
      isPlayer: isPlayer,
      attacks: attacks,
    );
    _combatants.add(combatant);
    unawaited(_save());
    return combatant;
  }

  /// Adds the stored [character] as a player character with its values and
  /// current state. What happens to the combatant from now on is written
  /// back to the character.
  ///
  /// A character without id throws an [ArgumentError], one already in the
  /// encounter a [StateError].
  Combatant addCharacter(Character character) {
    final id = character.id;
    if (id == null) {
      throw ArgumentError.value(character, 'character', 'must be saved');
    }
    if (hasCharacter(id)) {
      throw StateError('${character.name} is already in the encounter');
    }
    final combatant =
        Combatant(
            name: character.name,
            armorClass: character.armorClass,
            maxHp: character.maxHp,
            initiativeBonus: character.initiativeBonus,
            isPlayer: true,
            attacks: character.attacks,
          )
          ..characterId = id
          ..hp = character.hp
          ..tempHp = character.tempHp
          ..deathSaveSuccesses = character.deathSaveSuccesses
          ..deathSaveFailures = character.deathSaveFailures
          ..isStable = character.isStable
          ..isDead = character.isDead;
    _combatants.add(combatant);
    unawaited(_save());
    return combatant;
  }

  /// Whether the character with [characterId] is in the encounter.
  bool hasCharacter(int characterId) =>
      _combatants.any((c) => c.characterId == characterId);

  /// Takes over changed sheet values of [character] (name, armor class,
  /// maximum hit points, initiative bonus, attacks) for its combatant. Hit
  /// points stay as they are in the combat (see [edit]). Does nothing if
  /// the character is not in the encounter.
  void applyCharacter(Character character) {
    final combatant = _combatants
        .where((c) => c.characterId != null && c.characterId == character.id)
        .firstOrNull;
    if (combatant == null) return;
    combatant.attacks
      ..clear()
      ..addAll(character.attacks);
    edit(
      combatant,
      name: character.name,
      armorClass: character.armorClass,
      maxHp: character.maxHp,
      initiativeBonus: character.initiativeBonus,
    );
  }

  /// Takes over the current state of [character] (hit points, temporary
  /// hit points, death saving throws, stable, dead) for its combatant, e.g.
  /// after a rest. A correction, not an event: nothing is logged. Does
  /// nothing if the character is not in the encounter.
  void takeCharacterState(Character character) {
    final combatant = _combatants
        .where((c) => c.characterId != null && c.characterId == character.id)
        .firstOrNull;
    if (combatant == null) return;
    combatant
      ..hp = character.hp
      ..tempHp = character.tempHp
      ..deathSaveSuccesses = character.deathSaveSuccesses
      ..deathSaveFailures = character.deathSaveFailures
      ..isStable = character.isStable
      ..isDead = character.isDead;
    unawaited(_save());
  }

  /// Unlinks the combatant of the character with [characterId], e.g. after
  /// the character was deleted. The combatant stays in the encounter.
  void forgetCharacter(int characterId) {
    for (final combatant in _combatants) {
      if (combatant.characterId == characterId) combatant.characterId = null;
    }
    unawaited(_save());
  }

  void remove(Combatant combatant) {
    _combatants.remove(combatant);
    if (_current == combatant) _current = null;
    unawaited(_save());
  }

  /// Stores a further [attack] on [combatant].
  void addAttack(Combatant combatant, Attack attack) {
    combatant.attacks.add(attack);
    unawaited(_save());
  }

  /// Takes [attack] off [combatant].
  void removeAttack(Combatant combatant, Attack attack) {
    combatant.attacks.remove(attack);
    unawaited(_save());
  }

  /// Corrects the values of [combatant]; values left out stay as they are.
  /// This is not something that happens in the game, so nothing is logged.
  ///
  /// A combatant at full hit points keeps full hit points with a new
  /// [maxHp]; otherwise hit points stay but never exceed the new maximum.
  /// A combatant who stops being a player character loses their death
  /// saving throws and the marks stable and dead; at 0 hit points they are
  /// simply down, like a monster.
  ///
  /// An empty [name], [armorClass] below 0 or [maxHp] below 1 throw an
  /// [ArgumentError] and change nothing.
  void edit(
    Combatant combatant, {
    String? name,
    int? armorClass,
    int? maxHp,
    int? initiativeBonus,
    bool? isPlayer,
  }) {
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (armorClass != null && armorClass < 0) {
      throw ArgumentError.value(armorClass, 'armorClass', 'must not be < 0');
    }
    if (maxHp != null && maxHp < 1) {
      throw ArgumentError.value(maxHp, 'maxHp', 'must be at least 1');
    }

    if (trimmed != null) combatant.name = trimmed;
    if (armorClass != null) combatant.armorClass = armorClass;
    if (initiativeBonus != null) combatant.initiativeBonus = initiativeBonus;
    if (maxHp != null) {
      final unhurt = combatant.hp == combatant.maxHp;
      combatant
        ..hp = unhurt || combatant.hp > maxHp ? maxHp : combatant.hp
        ..maxHp = maxHp;
    }
    if (isPlayer != null && isPlayer != combatant.isPlayer) {
      combatant
        ..isPlayer = isPlayer
        ..deathSaveSuccesses = 0
        ..deathSaveFailures = 0
        ..isStable = false
        ..isDead = false;
    }
    unawaited(_save());
  }

  /// Sets how [combatant] reacts to damage of [type]; null for [effect]
  /// removes the entry. There is one entry per damage type.
  void setDamageTrait(Combatant combatant, String type, DamageEffect? effect) {
    final wanted = normalizeDamageType(type);
    combatant.damageTraits.removeWhere(
      (key, _) => normalizeDamageType(key) == wanted,
    );
    if (effect != null) {
      // Standard types keep their usual spelling.
      final name = damageTypes.firstWhere(
        (standard) => normalizeDamageType(standard) == wanted,
        orElse: type.trim,
      );
      combatant.damageTraits[name] = effect;
    }
    unawaited(_save());
  }

  /// Gives [combatant] [amount] temporary hit points. They do not stack: the
  /// combatant keeps whichever is higher, the new or the current amount.
  /// Temporary hit points take damage first; healing does not restore them
  /// and they do not bring a combatant at 0 hit points back.
  ///
  /// An [amount] below 1 throws an [ArgumentError] and changes nothing.
  Future<TempHpEvent> grantTempHp(
    Combatant combatant,
    int amount, {
    String? source,
  }) async {
    if (amount < 1) {
      throw ArgumentError.value(amount, 'amount', 'must be at least 1');
    }
    final before = combatant.tempHp;
    if (amount > before) combatant.tempHp = amount;
    final trimmed = source?.trim();
    final event = TempHpEvent(
      name: combatant.name,
      amount: amount,
      tempHpBefore: before,
      tempHpAfter: combatant.tempHp,
      source: trimmed == null || trimmed.isEmpty ? null : trimmed,
    );
    await _log.add(event);
    await _save();
    return event;
  }

  /// Takes all temporary hit points from [combatant]; does nothing and
  /// returns null if they have none.
  Future<TempHpEvent?> removeTempHp(Combatant combatant) async {
    final before = combatant.tempHp;
    if (before == 0) return null;
    combatant.tempHp = 0;
    final event = TempHpEvent(
      name: combatant.name,
      amount: 0,
      tempHpBefore: before,
      tempHpAfter: 0,
    );
    await _log.add(event);
    await _save();
    return event;
  }

  /// Gives [combatant] a [condition], optionally for a number of [rounds]
  /// (see [nextTurn]). A condition the combatant already has only gets its
  /// duration replaced.
  ///
  /// [rounds] below 1 throws an [ArgumentError] and changes nothing.
  Future<void> addCondition(
    Combatant combatant,
    Condition condition, {
    int? rounds,
  }) async {
    if (rounds != null && rounds < 1) {
      throw ArgumentError.value(rounds, 'rounds', 'must be at least 1');
    }
    combatant.conditions.removeWhere((c) => c.condition == condition);
    combatant.conditions.add(ActiveCondition(condition, roundsLeft: rounds));
    await _log.add(
      ConditionEvent(
        name: combatant.name,
        condition: condition.name,
        change: EffectChange.added,
        rounds: rounds,
      ),
    );
    await _save();
  }

  /// Takes [condition] from [combatant]; does nothing if they do not have
  /// it.
  Future<void> removeCondition(Combatant combatant, Condition condition) async {
    if (!combatant.hasCondition(condition)) return;
    combatant.conditions.removeWhere((c) => c.condition == condition);
    await _log.add(
      ConditionEvent(
        name: combatant.name,
        condition: condition.name,
        change: EffectChange.removed,
      ),
    );
    await _save();
  }

  /// Gives [combatant] an effect called [name]: a bonus or penalty on
  /// attack rolls, armor class, damage and/or saving throws, optionally for
  /// a number of [rounds] (see [nextTurn]). Effects of the same name do not
  /// stack; the new one replaces the old one.
  ///
  /// The [damageBonus] has the type of the attack unless a [damageType] is
  /// given.
  ///
  /// An empty [name] or [rounds] below 1 throws an [ArgumentError] and
  /// changes nothing.
  Future<Buff> addBuff(
    Combatant combatant, {
    required String name,
    Bonus? attackBonus,
    int armorClassBonus = 0,
    Bonus? damageBonus,
    String? damageType,
    Bonus? saveBonus,
    int? rounds,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (rounds != null && rounds < 1) {
      throw ArgumentError.value(rounds, 'rounds', 'must be at least 1');
    }
    final type = damageType?.trim();
    final buff = Buff(
      name: trimmed,
      attackBonus: attackBonus,
      armorClassBonus: armorClassBonus,
      damageBonus: damageBonus,
      damageType: type == null || type.isEmpty ? null : type,
      saveBonus: saveBonus,
      roundsLeft: rounds,
    );
    combatant.buffs
      ..removeWhere((b) => b.name.toLowerCase() == trimmed.toLowerCase())
      ..add(buff);
    await _log.add(_buffEvent(combatant, buff, EffectChange.added));
    await _save();
    return buff;
  }

  /// Takes [buff] from [combatant]; does nothing if they do not have it.
  Future<void> removeBuff(Combatant combatant, Buff buff) async {
    if (!combatant.buffs.remove(buff)) return;
    await _log.add(_buffEvent(combatant, buff, EffectChange.removed));
    await _save();
  }

  BuffEvent _buffEvent(Combatant combatant, Buff buff, EffectChange change) {
    return BuffEvent(
      name: combatant.name,
      buff: buff.name,
      change: change,
      attackBonus: buff.attackBonus?.toString(),
      armorClassBonus: buff.armorClassBonus,
      damageBonus: buff.damageBonus?.toString(),
      damageType: buff.damageType,
      saveBonus: buff.saveBonus?.toString(),
      rounds: change == EffectChange.added ? buff.roundsLeft : null,
    );
  }

  /// Counts down everything with a duration on [combatant] at the end of
  /// their turn and returns what ran out.
  List<LogEvent> _endTurn(Combatant combatant) {
    final expired = <LogEvent>[];
    combatant.buffs.removeWhere((buff) {
      final left = buff.roundsLeft;
      if (left == null) return false;
      buff.roundsLeft = left - 1;
      if (left > 1) return false;
      expired.add(_buffEvent(combatant, buff, EffectChange.expired));
      return true;
    });
    combatant.conditions.removeWhere((active) {
      final left = active.roundsLeft;
      if (left == null) return false;
      active.roundsLeft = left - 1;
      if (left > 1) return false;
      expired.add(
        ConditionEvent(
          name: combatant.name,
          condition: active.condition.name,
          change: EffectChange.expired,
        ),
      );
      return true;
    });
    return expired;
  }

  /// Completes when every change made so far is saved.
  Future<void> flush() => _lastSave;

  /// Saves the current state and writes the state of linked combatants back
  /// to their characters. Saves run one after the other, so the last change
  /// always wins.
  Future<void> _save() {
    final store = _store;
    final characters = _characters;
    if (store == null && characters == null) return _lastSave;
    final state = _toJson();
    // Taken now, so a later change cannot sneak into this save.
    final linked = [
      for (final combatant in _combatants)
        if (combatant.characterId case final id?) (id, combatant.toJson()),
    ];
    // A failed earlier save must not block this one.
    return _lastSave = _lastSave.catchError((Object _) {}).then((_) async {
      if (store != null) await store.save(state);
      if (characters == null) return;
      for (final (id, combatant) in linked) {
        final character = await characters.byId(id);
        if (character == null) continue;
        character
          ..hp = combatant['hp']! as int
          ..tempHp = combatant['tempHp']! as int
          ..deathSaveSuccesses = combatant['deathSaveSuccesses']! as int
          ..deathSaveFailures = combatant['deathSaveFailures']! as int
          ..isStable = combatant['isStable']! as bool
          ..isDead = combatant['isDead']! as bool;
        await characters.save(character);
      }
    });
  }

  Map<String, Object?> _toJson() => {
    'round': _round,
    'current': _current == null ? null : _combatants.indexOf(_current!),
    'combatants': [for (final combatant in _combatants) combatant.toJson()],
  };

  /// Takes over a state written by [_toJson]. A state that cannot be read
  /// is ignored as a whole, so the app still starts.
  void _restore(Map<String, Object?> state) {
    final List<Combatant> combatants;
    final int round;
    final int? current;
    try {
      combatants = [
        for (final combatant in state['combatants']! as List)
          Combatant.fromJson((combatant as Map).cast<String, Object?>()),
      ];
      round = state['round']! as int;
      current = state['current'] as int?;
      // ignore: avoid_catching_errors, wrong types in a damaged state.
    } on Error {
      return;
    } on FormatException {
      return;
    }

    _combatants
      ..clear()
      ..addAll(combatants);
    _round = round;
    _current = current != null && current >= 0 && current < combatants.length
        ? combatants[current]
        : null;
  }

  /// Rolls initiative for everyone and starts round 1.
  ///
  /// [manual] holds d20 values rolled at the table; the app rolls for all
  /// other combatants. Ties go to the higher initiative bonus.
  Future<void> rollInitiative({Map<Combatant, int> manual = const {}}) async {
    final rolls = <Combatant, RollRecord>{};
    for (final combatant in _combatants) {
      final modifiers = [
        if (combatant.initiativeBonus != 0)
          Modifier('Initiative', combatant.initiativeBonus),
      ];
      final typedIn = manual[combatant];
      rolls[combatant] = typedIn != null
          ? RollRecord.manualD20(typedIn, modifiers: modifiers)
          : RollRecord.fromD20(_roller.rollD20(modifiers: modifiers));
    }

    for (final combatant in _combatants) {
      combatant.initiative = rolls[combatant]!.total;
    }
    // List.sort is not stable, so the original position breaks remaining
    // ties explicitly.
    final position = {
      for (final (index, combatant) in _combatants.indexed) combatant: index,
    };
    _combatants.sort((a, b) {
      final byTotal = b.initiative!.compareTo(a.initiative!);
      if (byTotal != 0) return byTotal;
      final byBonus = b.initiativeBonus.compareTo(a.initiativeBonus);
      if (byBonus != 0) return byBonus;
      return position[a]!.compareTo(position[b]!);
    });

    _round = 1;
    _current = _combatants.where((c) => c.takesTurns).firstOrNull;

    await _log.add(
      InitiativeEvent([
        for (final combatant in _combatants)
          InitiativeEntry(name: combatant.name, roll: rolls[combatant]!),
      ]),
    );
    await _log.add(RoundEvent(_round));
    await _save();
  }

  /// Passes the turn to the next combatant who still takes turns: everyone
  /// standing and dying player characters. After the last one a new round
  /// begins.
  ///
  /// Durations count down at the end of the turn of the combatant who
  /// carries them, also when that combatant is skipped.
  Future<void> nextTurn() async {
    if (!isRunning || _combatants.every((c) => !c.takesTurns)) return;

    var index = _current == null ? -1 : _combatants.indexOf(_current!);
    var newRound = false;
    final expired = <LogEvent>[if (_current != null) ..._endTurn(_current!)];
    while (true) {
      index++;
      if (index >= _combatants.length) {
        index = 0;
        newRound = true;
      }
      if (_combatants[index].takesTurns) break;
      expired.addAll(_endTurn(_combatants[index]));
    }

    _current = _combatants[index];
    for (final event in expired) {
      await _log.add(event);
    }
    if (newRound) {
      _round++;
      await _log.add(RoundEvent(_round));
    }
    await _save();
  }

  /// Ends the combat: round and initiative are reset, hit points stay.
  void end() {
    _round = 0;
    _current = null;
    for (final combatant in _combatants) {
      combatant.initiative = null;
    }
    unawaited(_save());
  }

  /// [attacker] attacks [target] with [attack].
  ///
  /// A natural 20 always hits and doubles the damage dice, a natural 1
  /// always misses; otherwise the total has to reach the target's armor
  /// class. Damage is subtracted from the target's hit points, after the
  /// target's resistance, vulnerability or immunity against the attack's
  /// damage type.
  ///
  /// Conditions of attacker and target give advantage or disadvantage on
  /// top of the [mode] the game master chose, unless [applyConditions] is
  /// false. Any advantage together with any disadvantage cancels out.
  ///
  /// Effects on the attacker add their bonus to the attack roll (bonus dice
  /// are rolled before the d20) and to the damage of a hit (bonus dice are
  /// rolled after the damage dice and doubled on a critical hit). Damage
  /// bonuses with their own damage type are kept apart as
  /// [AttackEvent.extraDamage]; resistances apply to each damage type
  /// separately. Effects on the attacker in [ignoredBuffs] do not count for
  /// this attack, e.g. Mal des Jägers against a creature that is not
  /// marked. Effects on the target change the armor class the attack has to
  /// reach.
  ///
  /// [manualBuffRolls] holds bonus dice for the attack roll rolled at the
  /// table, [manualBuffDamage] those for the damage, per effect.
  /// [manualAttackRoll] is the counting d20 rolled at the table,
  /// [manualDamage] the sum of the damage dice without the damage bonus.
  /// Impossible values throw an [ArgumentError] and change nothing.
  Future<AttackOutcome> attack({
    required Combatant attacker,
    required Combatant target,
    required Attack attack,
    RollMode mode = RollMode.normal,
    int? manualAttackRoll,
    int? manualDamage,
    Map<Buff, int> manualBuffRolls = const {},
    Map<Buff, int> manualBuffDamage = const {},
    Set<Buff> ignoredBuffs = const {},
    bool applyConditions = true,
  }) async {
    final buffs = [
      for (final buff in attacker.buffs)
        if (!ignoredBuffs.contains(buff)) buff,
    ];
    final conditionEffects = applyConditions
        ? _conditionEffects(attacker, target)
        : const <ConditionEffect>[];
    final hasAdvantage =
        mode == RollMode.advantage || conditionEffects.any((e) => e.advantage);
    final hasDisadvantage =
        mode == RollMode.disadvantage ||
        conditionEffects.any((e) => !e.advantage);
    final effectiveMode = hasAdvantage == hasDisadvantage
        ? RollMode.normal
        : (hasAdvantage ? RollMode.advantage : RollMode.disadvantage);

    final attackModifiers = [
      Modifier('Angriffsbonus', attack.attackBonus),
      for (final buff in buffs)
        if (buff.attackBonus case final bonus?)
          _buffModifier(buff.name, bonus, manualBuffRolls[buff]),
    ];
    final armorClassModifiers = [
      for (final buff in target.buffs)
        if (buff.armorClassBonus != 0)
          Modifier(buff.name, buff.armorClassBonus),
    ];
    final armorClass = target.effectiveArmorClass;
    final attackRoll = manualAttackRoll != null
        ? RollRecord.manualD20(
            manualAttackRoll,
            mode: effectiveMode,
            modifiers: attackModifiers,
          )
        : RollRecord.fromD20(
            _roller.rollD20(mode: effectiveMode, modifiers: attackModifiers),
          );

    final critical = attackRoll.isNatural20;
    final hit =
        critical || (!attackRoll.isNatural1 && attackRoll.total >= armorClass);

    RollRecord? damageRoll;
    DamageEffect? damageEffect;
    var extraDamage = const <ExtraDamage>[];
    var damage = 0;
    if (hit) {
      final weaponRoll = _rollDamage(attack, critical, manualDamage);
      // Bonus damage per damage type; null stands for the attack's type.
      final bonusByType = <String?, List<Modifier>>{};
      final typeNames = <String, String>{};
      for (final buff in buffs) {
        final bonus = buff.damageBonus;
        if (bonus == null) continue;
        final modifier = _buffModifier(
          buff.name,
          bonus,
          manualBuffDamage[buff],
          diceFactor: critical ? 2 : 1,
          parameter: 'manualBuffDamage',
        );
        final type = buff.damageType;
        final key =
            type == null ||
                normalizeDamageType(type) ==
                    normalizeDamageType(attack.damageType)
            ? null
            : normalizeDamageType(type);
        if (key != null) typeNames.putIfAbsent(key, () => type!);
        bonusByType.putIfAbsent(key, () => []).add(modifier);
      }

      damageRoll = RollRecord(
        count: weaponRoll.count,
        sides: weaponRoll.sides,
        rolls: weaponRoll.rolls,
        manual: weaponRoll.manual,
        modifiers: [...weaponRoll.modifiers, ...?bonusByType[null]],
      );
      damageEffect = target.damageEffectFor(attack.damageType);
      extraDamage = [
        for (final MapEntry(:key, :value) in bonusByType.entries)
          if (key != null)
            ExtraDamage(
              damageType: typeNames[key]!,
              modifiers: value,
              damageEffect: target.damageEffectFor(key),
            ),
      ];
      damage =
          adjustDamage(
            damageRoll.total < 0 ? 0 : damageRoll.total,
            damageEffect,
          ) +
          extraDamage.fold(0, (sum, extra) => sum + extra.damage);
    }

    // Everything is rolled and validated; only now change state and log.
    final wasDown = target.isDown;
    final tempHpBefore = target.tempHp;
    final consequences = _applyDamage(target, damage, critical: critical);
    final targetDown = !wasDown && target.isDown;

    final attackEvent = AttackEvent(
      attackerName: attacker.name,
      targetName: target.name,
      attackName: attack.name,
      targetArmorClass: armorClass,
      armorClassModifiers: armorClassModifiers,
      attackRoll: attackRoll,
      hit: hit,
      critical: critical,
      damageType: attack.damageType,
      damageRoll: damageRoll,
      damage: damage,
      damageEffect: damageEffect,
      extraDamage: extraDamage,
      tempHpAbsorbed: tempHpBefore - target.tempHp,
      conditionEffects: conditionEffects,
      chosenMode: mode,
    );
    await _log.add(attackEvent);
    for (final event in consequences) {
      await _log.add(event);
    }
    await _save();

    return AttackOutcome(
      event: attackEvent,
      attackRoll: attackRoll,
      hit: hit,
      critical: critical,
      damageRoll: damageRoll,
      damage: damage,
      damageEffect: damageEffect,
      targetDown: targetDown,
    );
  }

  /// Deals [amount] damage to [target] without an attack, e.g. from a spell
  /// or a trap. Hit points never drop below 0. With a [damageType] the
  /// target's resistance, vulnerability or immunity against it applies.
  ///
  /// An [amount] below 1 throws an [ArgumentError] and changes nothing.
  Future<HpChangeEvent> damage(
    Combatant target,
    int amount, {
    String? source,
    String? damageType,
  }) => _changeHp(
    target,
    amount,
    healing: false,
    source: source,
    damageType: damageType,
  );

  /// Heals [target] by [amount]. Hit points never rise above the maximum; a
  /// combatant at 0 hit points is back on their feet and their death saving
  /// throws are reset.
  ///
  /// An [amount] below 1 throws an [ArgumentError], a dead [target] a
  /// [StateError]; both change nothing.
  Future<HpChangeEvent> heal(Combatant target, int amount, {String? source}) =>
      _changeHp(target, amount, healing: true, source: source);

  Future<HpChangeEvent> _changeHp(
    Combatant target,
    int amount, {
    required bool healing,
    String? source,
    String? damageType,
  }) async {
    if (amount < 1) {
      throw ArgumentError.value(amount, 'amount', 'must be at least 1');
    }

    if (healing && target.isDead) {
      throw StateError('${target.name} is dead and cannot be healed');
    }

    final type = damageType?.trim();
    final knownType = type == null || type.isEmpty ? null : type;
    final damageEffect = healing ? null : target.damageEffectFor(knownType);

    final hpBefore = target.hp;
    final tempHpBefore = target.tempHp;
    var consequences = const <LogEvent>[];
    if (healing) {
      target
        ..hp = hpBefore + amount > target.maxHp
            ? target.maxHp
            : hpBefore + amount
        ..isStable = false
        ..deathSaveSuccesses = 0
        ..deathSaveFailures = 0;
    } else {
      consequences = _applyDamage(target, adjustDamage(amount, damageEffect));
    }

    final trimmed = source?.trim();
    final event = HpChangeEvent(
      name: target.name,
      amount: amount,
      healing: healing,
      hpBefore: hpBefore,
      hpAfter: target.hp,
      maxHp: target.maxHp,
      source: trimmed == null || trimmed.isEmpty ? null : trimmed,
      damageType: healing ? null : knownType,
      damageEffect: damageEffect,
      tempHpBefore: tempHpBefore,
      tempHpAfter: target.tempHp,
    );
    await _log.add(event);
    for (final consequence in consequences) {
      await _log.add(consequence);
    }
    await _save();
    return event;
  }

  /// Subtracts [damage] from [target]'s hit points and returns what follows
  /// from it, to be logged after the damage itself.
  ///
  /// Temporary hit points take the damage first; only what is left reaches
  /// the hit points.
  ///
  /// Monsters simply go down at 0. For player characters the death rules
  /// apply: damage at 0 hit points is a failed death saving throw (two for
  /// a [critical] hit), and damage left over at 0 that reaches the hit
  /// point maximum kills outright.
  List<LogEvent> _applyDamage(
    Combatant target,
    int incoming, {
    bool critical = false,
  }) {
    if (incoming <= 0 || target.isDead) return const [];

    final absorbed = incoming < target.tempHp ? incoming : target.tempHp;
    target.tempHp -= absorbed;
    final damage = incoming - absorbed;
    if (damage == 0) return const [];

    final hpBefore = target.hp;
    target.hp = damage >= hpBefore ? 0 : hpBefore - damage;
    if (target.hp > 0) return const [];

    if (!target.isPlayer) {
      return [if (hpBefore > 0) CombatantDownEvent(target.name)];
    }

    if (damage - hpBefore >= target.maxHp) {
      target
        ..isDead = true
        ..isStable = false;
      return [CombatantDiedEvent(target.name, massiveDamage: true)];
    }
    if (hpBefore > 0) return [CombatantDownEvent(target.name)];

    final added = critical ? 2 : 1;
    final failures = target.deathSaveFailures + added;
    target
      ..isStable = false
      ..deathSaveFailures = failures > 3 ? 3 : failures;
    return [
      DyingDamageEvent(
        name: target.name,
        failuresAdded: added,
        failures: target.deathSaveFailures,
      ),
      if (_diesFromFailures(target)) CombatantDiedEvent(target.name),
    ];
  }

  /// Brings a dead [combatant] back to life with [hp] hit points: 1 for
  /// spells like Wiederbeleben or Tote erwecken, the maximum for
  /// Auferstehung. Death saving throws start over.
  ///
  /// A [combatant] who is not dead throws a [StateError], [hp] below 1 or
  /// above the maximum an [ArgumentError]; both change nothing.
  Future<CombatantRevivedEvent> revive(
    Combatant combatant, {
    int hp = 1,
    String? source,
  }) async {
    if (!combatant.isDead) {
      throw StateError('${combatant.name} is not dead');
    }
    if (hp < 1 || hp > combatant.maxHp) {
      throw ArgumentError.value(hp, 'hp', 'must be 1 to ${combatant.maxHp}');
    }
    combatant
      ..isDead = false
      ..isStable = false
      ..deathSaveSuccesses = 0
      ..deathSaveFailures = 0
      ..hp = hp;
    final trimmed = source?.trim();
    final event = CombatantRevivedEvent(
      name: combatant.name,
      hp: hp,
      source: trimmed == null || trimmed.isEmpty ? null : trimmed,
    );
    await _log.add(event);
    await _save();
    return event;
  }

  /// Marks [combatant] as dead once the third death saving throw failed.
  bool _diesFromFailures(Combatant combatant) {
    if (combatant.deathSaveFailures < 3) return false;
    combatant.isDead = true;
    return true;
  }

  /// Death saving throw of a dying player character: a d20 without
  /// modifiers. 10 or more is a success, less a failure; a natural 1 counts
  /// as two failures, a natural 20 brings the character back with 1 hit
  /// point. Three successes make the character stable, three failures kill.
  ///
  /// Effects with a bonus on saving throws add it to the total (bonus dice
  /// are rolled before the d20); natural 1 and 20 still count as such.
  ///
  /// [manualRoll] is the d20 rolled at the table, [manualBuffRolls] holds
  /// bonus dice rolled at the table, per effect. Impossible values throw an
  /// [ArgumentError], a [combatant] who is not dying a [StateError]; both
  /// change nothing.
  Future<DeathSaveEvent> rollDeathSave(
    Combatant combatant, {
    int? manualRoll,
    Map<Buff, int> manualBuffRolls = const {},
  }) async {
    if (!combatant.isDying) {
      throw StateError('${combatant.name} is not dying');
    }
    final modifiers = [
      for (final buff in combatant.buffs)
        if (buff.saveBonus case final bonus?)
          _buffModifier(buff.name, bonus, manualBuffRolls[buff]),
    ];
    final roll = manualRoll != null
        ? RollRecord.manualD20(manualRoll, modifiers: modifiers)
        : RollRecord.fromD20(_roller.rollD20(modifiers: modifiers));

    LogEvent? consequence;
    if (roll.isNatural20) {
      combatant
        ..hp = 1
        ..deathSaveSuccesses = 0
        ..deathSaveFailures = 0;
    } else if (roll.total >= 10) {
      combatant.deathSaveSuccesses++;
    } else {
      final failures = combatant.deathSaveFailures + (roll.isNatural1 ? 2 : 1);
      combatant.deathSaveFailures = failures > 3 ? 3 : failures;
    }
    final event = DeathSaveEvent(
      name: combatant.name,
      roll: roll,
      successes: combatant.deathSaveSuccesses,
      failures: combatant.deathSaveFailures,
    );

    if (_diesFromFailures(combatant)) {
      consequence = CombatantDiedEvent(combatant.name);
    } else if (combatant.deathSaveSuccesses >= 3) {
      combatant
        ..isStable = true
        ..deathSaveSuccesses = 0
        ..deathSaveFailures = 0;
      consequence = CombatantStableEvent(combatant.name);
    }

    await _log.add(event);
    if (consequence != null) await _log.add(consequence);
    await _save();
    return event;
  }

  /// The modifier from an effect called [name]: a fixed value, or bonus
  /// dice rolled by the app or typed in as [manual]. [diceFactor] 2 doubles
  /// the number of dice for a critical hit.
  Modifier _buffModifier(
    String name,
    Bonus bonus,
    int? manual, {
    int diceFactor = 1,
    String parameter = 'manualBuffRolls',
  }) {
    if (!bonus.isDice) return Modifier(name, bonus.signed(bonus.flat));
    final count = bonus.count * diceFactor;
    final dice = '${count}d${bonus.sides}';
    if (manual == null) {
      final rolled = _roller.roll(
        DiceExpression(count: count, sides: bonus.sides),
      );
      return Modifier('$name ($dice)', bonus.signed(rolled.total));
    }
    if (manual < count || manual > count * bonus.sides) {
      throw ArgumentError.value(
        manual,
        parameter,
        '$dice shows $count to ${count * bonus.sides}',
      );
    }
    return Modifier('$name ($dice von Hand)', bonus.signed(manual));
  }

  /// Conditions that give advantage or disadvantage when [attacker]
  /// attacks [target]: the attacker's first, then the target's.
  List<ConditionEffect> _conditionEffects(
    Combatant attacker,
    Combatant target,
  ) {
    return [
      for (final active in attacker.conditions)
        if (active.condition.attackerEffect case final effect?)
          ConditionEffect(
            onAttacker: true,
            condition: active.condition.name,
            advantage: effect == RollMode.advantage,
          ),
      for (final active in target.conditions)
        if (active.condition.targetEffect case final effect?)
          ConditionEffect(
            onAttacker: false,
            condition: active.condition.name,
            advantage: effect == RollMode.advantage,
          ),
    ];
  }

  RollRecord _rollDamage(Attack attack, bool critical, int? manualSum) {
    final count = attack.damage.count * (critical ? 2 : 1);
    final sides = attack.damage.sides;
    final modifiers = [
      if (attack.damage.modifier != 0)
        Modifier('Schadensbonus', attack.damage.modifier),
    ];

    if (manualSum != null) {
      return RollRecord.manualDice(
        count: count,
        sides: sides,
        sum: manualSum,
        modifiers: modifiers,
      );
    }
    return RollRecord.fromRoll(
      _roller.roll(
        DiceExpression(count: count, sides: sides),
        modifiers: modifiers,
      ),
    );
  }
}
