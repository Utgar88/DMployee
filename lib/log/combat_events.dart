part of 'log_event.dart';

RollRecord _roll(Object? json) =>
    RollRecord.fromJson((json! as Map).cast<String, Object?>());

/// A condition that changed the attack roll of an [AttackEvent].
class ConditionEffect {
  const ConditionEffect({
    required this.onAttacker,
    required this.condition,
    required this.advantage,
  });

  factory ConditionEffect.fromJson(Map<String, Object?> json) {
    return ConditionEffect(
      onAttacker: json['onAttacker']! as bool,
      condition: json['condition']! as String,
      advantage: json['advantage']! as bool,
    );
  }

  /// True if the attacker has the condition, false if the target has it.
  final bool onAttacker;

  /// Name of the `Condition` value, e.g. `poisoned`.
  final String condition;

  /// True for advantage, false for disadvantage.
  final bool advantage;

  Map<String, Object?> toJson() => {
    'onAttacker': onAttacker,
    'condition': condition,
    'advantage': advantage,
  };
}

/// One attack: who attacked whom with what, the attack roll and, on a hit,
/// the damage roll. Names and armor class are stored as they were at that
/// moment.
class AttackEvent extends LogEvent {
  const AttackEvent({
    required this.attackerName,
    required this.targetName,
    required this.attackName,
    required this.targetArmorClass,
    required this.attackRoll,
    required this.hit,
    required this.critical,
    required this.damageType,
    this.damageRoll,
    this.damage = 0,
    this.damageEffect,
    this.conditionEffects = const [],
    this._chosenMode,
  });

  factory AttackEvent.fromJson(Map<String, Object?> json) {
    return AttackEvent(
      attackerName: json['attacker']! as String,
      targetName: json['target']! as String,
      attackName: json['attack']! as String,
      targetArmorClass: json['armorClass']! as int,
      attackRoll: _roll(json['attackRoll']),
      hit: json['hit']! as bool,
      critical: json['critical']! as bool,
      damageType: json['damageType']! as String,
      damageRoll: json['damageRoll'] == null ? null : _roll(json['damageRoll']),
      damage: json['damage']! as int,
      damageEffect: DamageEffect.fromName(json['damageEffect']),
      conditionEffects: [
        for (final effect in json['conditionEffects'] as List? ?? const [])
          ConditionEffect.fromJson((effect as Map).cast<String, Object?>()),
      ],
      chosenMode: RollMode.values.asNameMap()[json['chosenMode']],
    );
  }

  static const typeName = 'attack';

  final String attackerName;
  final String targetName;
  final String attackName;
  final int targetArmorClass;
  final RollRecord attackRoll;
  final bool hit;

  /// Natural 20 on the attack roll: damage dice were doubled.
  final bool critical;
  final String damageType;

  /// Null when the attack missed.
  final RollRecord? damageRoll;

  /// Damage dealt after [damageEffect], never negative.
  final int damage;

  /// Resistance, vulnerability or immunity of the target against
  /// [damageType]; null if the rolled damage counted as it was.
  final DamageEffect? damageEffect;

  /// Conditions of attacker and target that gave advantage or disadvantage.
  final List<ConditionEffect> conditionEffects;

  final RollMode? _chosenMode;

  /// What the game master selected for the attack. Together with
  /// [conditionEffects] it led to the mode the [attackRoll] was made with.
  RollMode get chosenMode => _chosenMode ?? attackRoll.mode;

  /// Damage as rolled, before [damageEffect]. 0 on a miss.
  int get rolledDamage {
    final total = damageRoll?.total ?? 0;
    return total < 0 ? 0 : total;
  }

  @override
  String get type => typeName;

  @override
  Map<String, Object?> toJson() => {
    'attacker': attackerName,
    'target': targetName,
    'attack': attackName,
    'armorClass': targetArmorClass,
    'attackRoll': attackRoll.toJson(),
    'hit': hit,
    'critical': critical,
    'damageType': damageType,
    'damageRoll': ?damageRoll?.toJson(),
    'damage': damage,
    'damageEffect': ?damageEffect?.name,
    if (conditionEffects.isNotEmpty)
      'conditionEffects': [
        for (final effect in conditionEffects) effect.toJson(),
      ],
    'chosenMode': chosenMode.name,
  };
}

/// Initiative result of one combatant.
class InitiativeEntry {
  const InitiativeEntry({required this.name, required this.roll});

  final String name;
  final RollRecord roll;
}

/// Initiative was rolled; [entries] are in turn order.
class InitiativeEvent extends LogEvent {
  const InitiativeEvent(this.entries);

  factory InitiativeEvent.fromJson(Map<String, Object?> json) {
    return InitiativeEvent([
      for (final entry in json['entries']! as List)
        InitiativeEntry(
          name: (entry as Map)['name']! as String,
          roll: _roll(entry['roll']),
        ),
    ]);
  }

  static const typeName = 'initiative';

  final List<InitiativeEntry> entries;

  @override
  String get type => typeName;

  @override
  Map<String, Object?> toJson() => {
    'entries': [
      for (final entry in entries)
        {'name': entry.name, 'roll': entry.roll.toJson()},
    ],
  };
}

/// A new combat round began.
class RoundEvent extends LogEvent {
  const RoundEvent(this.round);

  factory RoundEvent.fromJson(Map<String, Object?> json) =>
      RoundEvent(json['round']! as int);

  static const typeName = 'round';

  final int round;

  @override
  String get type => typeName;

  @override
  Map<String, Object?> toJson() => {'round': round};
}

/// A combatant dropped to 0 hit points.
class CombatantDownEvent extends LogEvent {
  const CombatantDownEvent(this.name);

  factory CombatantDownEvent.fromJson(Map<String, Object?> json) =>
      CombatantDownEvent(json['name']! as String);

  static const typeName = 'combatantDown';

  final String name;

  @override
  String get type => typeName;

  @override
  Map<String, Object?> toJson() => {'name': name};
}

/// Hit points of a combatant were changed directly, without an attack:
/// damage from a spell or a trap, healing from a potion and the like.
class HpChangeEvent extends LogEvent {
  const HpChangeEvent({
    required this.name,
    required this.amount,
    required this.healing,
    required this.hpBefore,
    required this.hpAfter,
    required this.maxHp,
    this.source,
    this.damageType,
    this.damageEffect,
  });

  factory HpChangeEvent.fromJson(Map<String, Object?> json) {
    return HpChangeEvent(
      name: json['name']! as String,
      amount: json['amount']! as int,
      healing: json['healing']! as bool,
      hpBefore: json['hpBefore']! as int,
      hpAfter: json['hpAfter']! as int,
      maxHp: json['maxHp']! as int,
      source: json['source'] as String?,
      damageType: json['damageType'] as String?,
      damageEffect: DamageEffect.fromName(json['damageEffect']),
    );
  }

  static const typeName = 'hpChange';

  final String name;

  /// Amount as entered, always positive. The part that took effect is the
  /// difference between [hpBefore] and [hpAfter].
  final int amount;

  /// Damage type, if one was given; always null for healing.
  final String? damageType;

  /// Resistance, vulnerability or immunity that changed the [amount].
  final DamageEffect? damageEffect;

  /// [amount] after [damageEffect].
  int get adjusted => adjustDamage(amount, damageEffect);

  /// True for healing, false for damage.
  final bool healing;
  final int hpBefore;
  final int hpAfter;
  final int maxHp;

  /// Where the change came from, e.g. "Feuerball"; optional.
  final String? source;

  /// The part of [amount] that actually changed the hit points.
  int get effective => (hpAfter - hpBefore).abs();

  @override
  String get type => typeName;

  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'amount': amount,
    'healing': healing,
    'hpBefore': hpBefore,
    'hpAfter': hpAfter,
    'maxHp': maxHp,
    'source': ?source,
    'damageType': ?damageType,
    'damageEffect': ?damageEffect?.name,
  };
}

/// A death saving throw of a player character at 0 hit points.
class DeathSaveEvent extends LogEvent {
  const DeathSaveEvent({
    required this.name,
    required this.roll,
    required this.successes,
    required this.failures,
  });

  factory DeathSaveEvent.fromJson(Map<String, Object?> json) {
    return DeathSaveEvent(
      name: json['name']! as String,
      roll: _roll(json['roll']),
      successes: json['successes']! as int,
      failures: json['failures']! as int,
    );
  }

  static const typeName = 'deathSave';

  final String name;
  final RollRecord roll;

  /// Successes and failures after this roll, 0 to 3 each.
  final int successes;
  final int failures;

  @override
  String get type => typeName;

  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'roll': roll.toJson(),
    'successes': successes,
    'failures': failures,
  };
}

/// A player character took damage at 0 hit points, which counts as failed
/// death saving throws.
class DyingDamageEvent extends LogEvent {
  const DyingDamageEvent({
    required this.name,
    required this.failuresAdded,
    required this.failures,
  });

  factory DyingDamageEvent.fromJson(Map<String, Object?> json) {
    return DyingDamageEvent(
      name: json['name']! as String,
      failuresAdded: json['failuresAdded']! as int,
      failures: json['failures']! as int,
    );
  }

  static const typeName = 'dyingDamage';

  final String name;

  /// 1, or 2 for a critical hit.
  final int failuresAdded;

  /// Failures after this damage, at most 3.
  final int failures;

  @override
  String get type => typeName;

  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'failuresAdded': failuresAdded,
    'failures': failures,
  };
}

/// A player character reached three successful death saving throws.
class CombatantStableEvent extends LogEvent {
  const CombatantStableEvent(this.name);

  factory CombatantStableEvent.fromJson(Map<String, Object?> json) =>
      CombatantStableEvent(json['name']! as String);

  static const typeName = 'combatantStable';

  final String name;

  @override
  String get type => typeName;

  @override
  Map<String, Object?> toJson() => {'name': name};
}

/// A player character died.
class CombatantDiedEvent extends LogEvent {
  const CombatantDiedEvent(this.name, {this.massiveDamage = false});

  factory CombatantDiedEvent.fromJson(Map<String, Object?> json) {
    return CombatantDiedEvent(
      json['name']! as String,
      massiveDamage: json['massiveDamage'] as bool? ?? false,
    );
  }

  static const typeName = 'combatantDied';

  final String name;

  /// Killed outright because the damage left over at 0 hit points reached
  /// the hit point maximum, instead of by three failed death saving throws.
  final bool massiveDamage;

  @override
  String get type => typeName;

  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'massiveDamage': massiveDamage,
  };
}

/// What happened to a condition in a [ConditionEvent].
enum ConditionChange { added, removed, expired }

/// A combatant got a condition, lost it, or its duration ran out.
class ConditionEvent extends LogEvent {
  const ConditionEvent({
    required this.name,
    required this.condition,
    required this.change,
    this.rounds,
  });

  factory ConditionEvent.fromJson(Map<String, Object?> json) {
    return ConditionEvent(
      name: json['name']! as String,
      condition: json['condition']! as String,
      change:
          ConditionChange.values.asNameMap()[json['change']] ??
          ConditionChange.added,
      rounds: json['rounds'] as int?,
    );
  }

  static const typeName = 'condition';

  final String name;

  /// Name of the `Condition` value, e.g. `poisoned`.
  final String condition;
  final ConditionChange change;

  /// Duration in rounds the condition was given with, if any.
  final int? rounds;

  @override
  String get type => typeName;

  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'condition': condition,
    'change': change.name,
    'rounds': ?rounds,
  };
}
