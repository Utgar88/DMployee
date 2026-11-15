import 'dart:math';

import '../dice/dice_roller.dart';
import '../dice/modifier.dart';

/// Everything about one finished roll that the log needs to show it again
/// later: which dice, every single face, the roll mode and every modifier
/// with its source.
///
/// Reused by all log events that contain rolls (free rolls now, attack and
/// damage rolls later).
class RollRecord {
  RollRecord({
    required this.count,
    required this.sides,
    required List<int> rolls,
    this.mode = RollMode.normal,
    List<Modifier> modifiers = const [],
  }) : rolls = List.unmodifiable(rolls),
       modifiers = List.unmodifiable(modifiers);

  factory RollRecord.fromRoll(RollResult result) {
    final expression = result.expression;
    return RollRecord(
      count: expression.count,
      sides: expression.sides,
      rolls: result.rolls,
      modifiers: [
        if (expression.modifier != 0) Modifier('Modifier', expression.modifier),
        ...result.modifiers,
      ],
    );
  }

  factory RollRecord.fromD20(D20Result result) {
    return RollRecord(
      count: 1,
      sides: 20,
      rolls: result.rolls,
      mode: result.mode,
      modifiers: result.modifiers,
    );
  }

  factory RollRecord.fromJson(Map<String, Object?> json) {
    return RollRecord(
      count: json['count']! as int,
      sides: json['sides']! as int,
      rolls: (json['rolls']! as List).cast<int>(),
      mode: RollMode.values.byName(json['mode']! as String),
      modifiers: [
        for (final modifier in json['modifiers']! as List)
          Modifier.fromJson((modifier as Map).cast<String, Object?>()),
      ],
    );
  }

  /// Number of dice in the expression (1 for a d20 even with advantage).
  final int count;
  final int sides;

  /// Every rolled face. With advantage or disadvantage this holds both d20.
  final List<int> rolls;
  final RollMode mode;
  final List<Modifier> modifiers;

  /// What the dice contribute: the sum of all faces, or the counting die for
  /// advantage and disadvantage.
  int get kept => switch (mode) {
    RollMode.normal => rolls.fold(0, (sum, face) => sum + face),
    RollMode.advantage => rolls.reduce(max),
    RollMode.disadvantage => rolls.reduce(min),
  };

  int get modifier => Modifier.sum(modifiers);

  int get total => kept + modifier;

  bool get _isSingleD20 => count == 1 && sides == 20;

  bool get isNatural20 => _isSingleD20 && kept == 20;

  bool get isNatural1 => _isSingleD20 && kept == 1;

  /// Dice without modifiers, e.g. `2d6`.
  String get dice => '${count}d$sides';

  /// Dice plus the sum of all modifiers, e.g. `2d6+5`.
  String get notation {
    if (modifier == 0) return dice;
    return '$dice${modifier > 0 ? '+' : ''}$modifier';
  }

  Map<String, Object?> toJson() => {
    'count': count,
    'sides': sides,
    'rolls': rolls,
    'mode': mode.name,
    'modifiers': [for (final modifier in modifiers) modifier.toJson()],
  };
}
