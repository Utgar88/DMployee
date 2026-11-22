part of 'log_event.dart';

enum RestKind { short, long }

/// Why a character got nothing from a rest.
enum RestBlocker {
  dead,

  /// At 0 hit points and not stable.
  dying,

  /// Fewer hit points than the rule book requires to start the rest.
  tooFewHp,
}

/// A character took a short or long rest. Spent hit dice during a short
/// rest are separate [HitDieEvent]s.
class RestEvent extends LogEvent {
  const RestEvent({
    required this.name,
    required this.kind,
    required this.ruleset,
    required this.hpBefore,
    required this.hpAfter,
    required this.maxHp,
    required this.hitDiceBefore,
    required this.hitDiceAfter,
    required this.hitDiceTotal,
    this.tempHpBefore = 0,
    this.blocker,
  });

  factory RestEvent.fromJson(Map<String, Object?> json) {
    return RestEvent(
      name: json['name']! as String,
      kind: RestKind.values.byName(json['kind']! as String),
      ruleset: json['ruleset']! as String,
      hpBefore: json['hpBefore']! as int,
      hpAfter: json['hpAfter']! as int,
      maxHp: json['maxHp']! as int,
      hitDiceBefore: json['hitDiceBefore']! as int,
      hitDiceAfter: json['hitDiceAfter']! as int,
      hitDiceTotal: json['hitDiceTotal']! as int,
      tempHpBefore: json['tempHpBefore'] as int? ?? 0,
      blocker: switch (json['blocker']) {
        final String name => RestBlocker.values.asNameMap()[name],
        _ => null,
      },
    );
  }

  static const typeName = 'rest';

  final String name;
  final RestKind kind;

  /// Id of the rule book the rest followed (`Ruleset.id`).
  final String ruleset;
  final int hpBefore;
  final int hpAfter;
  final int maxHp;

  /// Remaining hit dice before and after the rest.
  final int hitDiceBefore;
  final int hitDiceAfter;
  final int hitDiceTotal;

  /// Temporary hit points before the rest; a long rest ends them.
  final int tempHpBefore;

  /// Set if the character got nothing from the rest.
  final RestBlocker? blocker;

  @override
  String get type => typeName;

  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'kind': kind.name,
    'ruleset': ruleset,
    'hpBefore': hpBefore,
    'hpAfter': hpAfter,
    'maxHp': maxHp,
    'hitDiceBefore': hitDiceBefore,
    'hitDiceAfter': hitDiceAfter,
    'hitDiceTotal': hitDiceTotal,
    if (tempHpBefore != 0) 'tempHpBefore': tempHpBefore,
    'blocker': ?blocker?.name,
  };
}

/// A character spent a hit die during a short rest and regained hit
/// points.
class HitDieEvent extends LogEvent {
  const HitDieEvent({
    required this.name,
    required this.ruleset,
    required this.roll,
    required this.healing,
    required this.hpBefore,
    required this.hpAfter,
    required this.maxHp,
    required this.hitDiceLeft,
    required this.hitDiceTotal,
  });

  factory HitDieEvent.fromJson(Map<String, Object?> json) {
    return HitDieEvent(
      name: json['name']! as String,
      ruleset: json['ruleset']! as String,
      roll: RollRecord.fromJson((json['roll']! as Map).cast<String, Object?>()),
      healing: json['healing']! as int,
      hpBefore: json['hpBefore']! as int,
      hpAfter: json['hpAfter']! as int,
      maxHp: json['maxHp']! as int,
      hitDiceLeft: json['hitDiceLeft']! as int,
      hitDiceTotal: json['hitDiceTotal']! as int,
    );
  }

  static const typeName = 'hitDie';

  final String name;

  /// Id of the rule book that decided the [healing] (`Ruleset.id`).
  final String ruleset;

  /// The hit die with the constitution modifier.
  final RollRecord roll;

  /// Hit points regained by the rules; may differ from the roll's total
  /// (never below 0 in 2014, at least 1 in 2024). The part that took effect
  /// is the difference between [hpBefore] and [hpAfter].
  final int healing;
  final int hpBefore;
  final int hpAfter;
  final int maxHp;
  final int hitDiceLeft;
  final int hitDiceTotal;

  @override
  String get type => typeName;

  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'ruleset': ruleset,
    'roll': roll.toJson(),
    'healing': healing,
    'hpBefore': hpBefore,
    'hpAfter': hpAfter,
    'maxHp': maxHp,
    'hitDiceLeft': hitDiceLeft,
    'hitDiceTotal': hitDiceTotal,
  };
}
