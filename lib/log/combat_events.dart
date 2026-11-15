part of 'log_event.dart';

RollRecord _roll(Object? json) =>
    RollRecord.fromJson((json! as Map).cast<String, Object?>());

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

  /// Damage dealt, never negative.
  final int damage;

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
