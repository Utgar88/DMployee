import 'dart:async';

import '../dice/dice_expression.dart';
import '../dice/dice_roller.dart';
import '../dice/modifier.dart';
import '../log/log_event.dart';
import '../log/log_repository.dart';
import '../log/roll_record.dart';
import 'attack.dart';
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
class Encounter {
  Encounter({required this._log, DiceRoller? roller, this._store})
    : _roller = roller ?? DiceRoller();

  /// The combat as it was last saved in [store]. Starts empty if nothing
  /// was saved yet or the saved state cannot be read.
  static Future<Encounter> load({
    required LogRepository log,
    required EncounterStore store,
    DiceRoller? roller,
  }) async {
    final encounter = Encounter(log: log, store: store, roller: roller);
    final state = await store.load();
    if (state != null) encounter._restore(state);
    return encounter;
  }

  final LogRepository _log;
  final DiceRoller _roller;
  final EncounterStore? _store;

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
        change: ConditionChange.added,
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
        change: ConditionChange.removed,
      ),
    );
    await _save();
  }

  /// Counts down everything with a duration on [combatant] at the end of
  /// their turn and returns what ran out.
  List<LogEvent> _endTurn(Combatant combatant) {
    final expired = <LogEvent>[];
    combatant.conditions.removeWhere((active) {
      final left = active.roundsLeft;
      if (left == null) return false;
      active.roundsLeft = left - 1;
      if (left > 1) return false;
      expired.add(
        ConditionEvent(
          name: combatant.name,
          condition: active.condition.name,
          change: ConditionChange.expired,
        ),
      );
      return true;
    });
    return expired;
  }

  /// Completes when every change made so far is saved.
  Future<void> flush() => _lastSave;

  /// Saves the current state. Saves run one after the other, so the last
  /// change always wins.
  Future<void> _save() {
    final store = _store;
    if (store == null) return _lastSave;
    final state = _toJson();
    // A failed earlier save must not block this one.
    return _lastSave = _lastSave
        .catchError((Object _) {})
        .then((_) => store.save(state));
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
    bool applyConditions = true,
  }) async {
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

    final attackModifiers = [Modifier('Angriffsbonus', attack.attackBonus)];
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
        critical ||
        (!attackRoll.isNatural1 && attackRoll.total >= target.armorClass);

    RollRecord? damageRoll;
    DamageEffect? damageEffect;
    var damage = 0;
    if (hit) {
      damageRoll = _rollDamage(attack, critical, manualDamage);
      damageEffect = target.damageEffectFor(attack.damageType);
      damage = adjustDamage(
        damageRoll.total < 0 ? 0 : damageRoll.total,
        damageEffect,
      );
    }

    // Everything is rolled and validated; only now change state and log.
    final wasDown = target.isDown;
    final consequences = _applyDamage(target, damage, critical: critical);
    final targetDown = !wasDown && target.isDown;

    final attackEvent = AttackEvent(
      attackerName: attacker.name,
      targetName: target.name,
      attackName: attack.name,
      targetArmorClass: target.armorClass,
      attackRoll: attackRoll,
      hit: hit,
      critical: critical,
      damageType: attack.damageType,
      damageRoll: damageRoll,
      damage: damage,
      damageEffect: damageEffect,
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
  /// Monsters simply go down at 0. For player characters the death rules
  /// apply: damage at 0 hit points is a failed death saving throw (two for
  /// a [critical] hit), and damage left over at 0 that reaches the hit
  /// point maximum kills outright.
  List<LogEvent> _applyDamage(
    Combatant target,
    int damage, {
    bool critical = false,
  }) {
    if (damage <= 0 || target.isDead) return const [];

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
  /// [manualRoll] is the d20 rolled at the table. A value outside 1 to 20
  /// throws an [ArgumentError], a [combatant] who is not dying a
  /// [StateError]; both change nothing.
  Future<DeathSaveEvent> rollDeathSave(
    Combatant combatant, {
    int? manualRoll,
  }) async {
    if (!combatant.isDying) {
      throw StateError('${combatant.name} is not dying');
    }
    final roll = manualRoll != null
        ? RollRecord.manualD20(manualRoll)
        : RollRecord.fromD20(_roller.rollD20());

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
