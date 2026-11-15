import 'dart:math';

import 'dice_expression.dart';

/// How a d20 is rolled.
enum RollMode {
  /// One d20.
  normal,

  /// Two d20, the higher one counts.
  advantage,

  /// Two d20, the lower one counts.
  disadvantage,
}

/// Outcome of rolling a [DiceExpression].
class RollResult {
  RollResult({required this.expression, required List<int> rolls})
    : rolls = List.unmodifiable(rolls);

  final DiceExpression expression;

  /// Face shown by each die, in roll order.
  final List<int> rolls;

  int get modifier => expression.modifier;

  /// Sum of all dice plus the modifier.
  int get total => rolls.fold(0, (sum, face) => sum + face) + modifier;
}

/// Outcome of a d20 roll (attack roll, ability check, saving throw).
class D20Result {
  D20Result({
    required List<int> rolls,
    required this.mode,
    required this.modifier,
  }) : rolls = List.unmodifiable(rolls);

  /// Faces of all rolled d20: one for [RollMode.normal], otherwise two.
  final List<int> rolls;
  final RollMode mode;
  final int modifier;

  /// The die that counts after applying advantage or disadvantage.
  int get kept => switch (mode) {
    RollMode.normal => rolls.first,
    RollMode.advantage => rolls.reduce(max),
    RollMode.disadvantage => rolls.reduce(min),
  };

  int get total => kept + modifier;

  /// The counting die shows a 20.
  bool get isNatural20 => kept == 20;

  /// The counting die shows a 1.
  bool get isNatural1 => kept == 1;
}

/// A d20 roll compared against a difficulty class (saving throw or ability
/// check). Per 5e rules only the total counts: a natural 20 or 1 has no
/// special effect here.
class CheckResult {
  CheckResult({required this.roll, required this.dc});

  final D20Result roll;

  /// Difficulty class the total has to meet or beat.
  final int dc;

  bool get isSuccess => roll.total >= dc;

  /// Distance to the [dc]: positive or zero on success, negative on failure.
  int get margin => roll.total - dc;
}

/// Rolls dice. Pass a [Random] to make rolls reproducible (tests, replays).
class DiceRoller {
  DiceRoller([Random? random]) : _random = random ?? Random.secure();

  final Random _random;

  RollResult roll(DiceExpression expression) {
    return RollResult(
      expression: expression,
      rolls: [
        for (var i = 0; i < expression.count; i++) _die(expression.sides),
      ],
    );
  }

  D20Result rollD20({RollMode mode = RollMode.normal, int modifier = 0}) {
    final diceCount = mode == RollMode.normal ? 1 : 2;
    return D20Result(
      rolls: [for (var i = 0; i < diceCount; i++) _die(20)],
      mode: mode,
      modifier: modifier,
    );
  }

  /// Rolls a saving throw or ability check against [dc].
  CheckResult rollCheck({
    required int dc,
    RollMode mode = RollMode.normal,
    int modifier = 0,
  }) {
    return CheckResult(
      roll: rollD20(mode: mode, modifier: modifier),
      dc: dc,
    );
  }

  int _die(int sides) => _random.nextInt(sides) + 1;
}
