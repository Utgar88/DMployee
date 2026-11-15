import 'dart:math';

import 'dice_expression.dart';
import 'modifier.dart';

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
  RollResult({
    required this.expression,
    required List<int> rolls,
    List<Modifier> modifiers = const [],
  }) : rolls = List.unmodifiable(rolls),
       modifiers = List.unmodifiable(modifiers);

  final DiceExpression expression;

  /// Face shown by each die, in roll order.
  final List<int> rolls;

  /// Named modifiers on top of the flat modifier of the [expression].
  final List<Modifier> modifiers;

  /// Everything added to the dice: the expression's flat modifier plus all
  /// named [modifiers].
  int get modifier => expression.modifier + Modifier.sum(modifiers);

  /// Sum of all dice plus the [modifier].
  int get total => rolls.fold(0, (sum, face) => sum + face) + modifier;
}

/// Outcome of a d20 roll (attack roll, ability check, saving throw).
class D20Result {
  D20Result({
    required List<int> rolls,
    required this.mode,
    List<Modifier> modifiers = const [],
  }) : rolls = List.unmodifiable(rolls),
       modifiers = List.unmodifiable(modifiers);

  /// Faces of all rolled d20: one for [RollMode.normal], otherwise two.
  final List<int> rolls;
  final RollMode mode;

  /// Named modifiers added to the counting die.
  final List<Modifier> modifiers;

  /// Sum of all [modifiers].
  int get modifier => Modifier.sum(modifiers);

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

  RollResult roll(
    DiceExpression expression, {
    List<Modifier> modifiers = const [],
  }) {
    return RollResult(
      expression: expression,
      modifiers: modifiers,
      rolls: [
        for (var i = 0; i < expression.count; i++) _die(expression.sides),
      ],
    );
  }

  D20Result rollD20({
    RollMode mode = RollMode.normal,
    List<Modifier> modifiers = const [],
  }) {
    final diceCount = mode == RollMode.normal ? 1 : 2;
    return D20Result(
      rolls: [for (var i = 0; i < diceCount; i++) _die(20)],
      mode: mode,
      modifiers: modifiers,
    );
  }

  /// Rolls a saving throw or ability check against [dc].
  CheckResult rollCheck({
    required int dc,
    RollMode mode = RollMode.normal,
    List<Modifier> modifiers = const [],
  }) {
    return CheckResult(
      roll: rollD20(mode: mode, modifiers: modifiers),
      dc: dc,
    );
  }

  int _die(int sides) => _random.nextInt(sides) + 1;
}
