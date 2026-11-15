import '../dice/dice_expression.dart';
import '../dice/dice_roller.dart';
import '../dice/modifier.dart';
import '../log/log_event.dart';
import '../log/log_repository.dart';
import '../log/roll_record.dart';
import 'attack.dart';
import 'combatant.dart';

/// Result of one attack.
class AttackOutcome {
  const AttackOutcome({
    required this.attackRoll,
    required this.hit,
    required this.critical,
    required this.damage,
    required this.targetDown,
    this.damageRoll,
  });

  final RollRecord attackRoll;
  final bool hit;
  final bool critical;

  /// Null when the attack missed.
  final RollRecord? damageRoll;
  final int damage;

  /// The target dropped to 0 hit points through this attack.
  final bool targetDown;
}

/// A combat: combatants, initiative order, rounds and attacks following the
/// D&D 5e basic rules. Everything that happens is written to the log.
///
/// The state lives in memory only and is lost when the app closes.
class Encounter {
  Encounter({required this._log, DiceRoller? roller})
    : _roller = roller ?? DiceRoller();

  final LogRepository _log;
  final DiceRoller _roller;
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
    List<Attack> attacks = const [],
  }) {
    final combatant = Combatant(
      name: name,
      armorClass: armorClass,
      maxHp: maxHp,
      initiativeBonus: initiativeBonus,
      attacks: attacks,
    );
    _combatants.add(combatant);
    return combatant;
  }

  void remove(Combatant combatant) {
    _combatants.remove(combatant);
    if (_current == combatant) _current = null;
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
    _current = _combatants.where((c) => !c.isDown).firstOrNull;

    await _log.add(
      InitiativeEvent([
        for (final combatant in _combatants)
          InitiativeEntry(name: combatant.name, roll: rolls[combatant]!),
      ]),
    );
    await _log.add(RoundEvent(_round));
  }

  /// Passes the turn to the next combatant who is still standing. After the
  /// last one a new round begins.
  Future<void> nextTurn() async {
    if (!isRunning || _combatants.every((c) => c.isDown)) return;

    var index = _current == null ? -1 : _combatants.indexOf(_current!);
    var newRound = false;
    do {
      index++;
      if (index >= _combatants.length) {
        index = 0;
        newRound = true;
      }
    } while (_combatants[index].isDown);

    _current = _combatants[index];
    if (newRound) {
      _round++;
      await _log.add(RoundEvent(_round));
    }
  }

  /// Ends the combat: round and initiative are reset, hit points stay.
  void end() {
    _round = 0;
    _current = null;
    for (final combatant in _combatants) {
      combatant.initiative = null;
    }
  }

  /// [attacker] attacks [target] with [attack].
  ///
  /// A natural 20 always hits and doubles the damage dice, a natural 1
  /// always misses; otherwise the total has to reach the target's armor
  /// class. Damage is subtracted from the target's hit points.
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
  }) async {
    final attackModifiers = [Modifier('Angriffsbonus', attack.attackBonus)];
    final attackRoll = manualAttackRoll != null
        ? RollRecord.manualD20(
            manualAttackRoll,
            mode: mode,
            modifiers: attackModifiers,
          )
        : RollRecord.fromD20(
            _roller.rollD20(mode: mode, modifiers: attackModifiers),
          );

    final critical = attackRoll.isNatural20;
    final hit =
        critical ||
        (!attackRoll.isNatural1 && attackRoll.total >= target.armorClass);

    RollRecord? damageRoll;
    var damage = 0;
    if (hit) {
      damageRoll = _rollDamage(attack, critical, manualDamage);
      damage = damageRoll.total < 0 ? 0 : damageRoll.total;
    }

    // Everything is rolled and validated; only now change state and log.
    final wasDown = target.isDown;
    target.hp = damage >= target.hp ? 0 : target.hp - damage;
    final targetDown = !wasDown && target.isDown;

    await _log.add(
      AttackEvent(
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
      ),
    );
    if (targetDown) {
      await _log.add(CombatantDownEvent(target.name));
    }

    return AttackOutcome(
      attackRoll: attackRoll,
      hit: hit,
      critical: critical,
      damageRoll: damageRoll,
      damage: damage,
      targetDown: targetDown,
    );
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
