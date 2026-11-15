import '../dice/dice_expression.dart';

/// An attack stored on a combatant, e.g. `Langschwert +5, 1d8+3 Hieb`.
class Attack {
  const Attack({
    required this.name,
    required this.attackBonus,
    required this.damage,
    required this.damageType,
  });

  final String name;

  /// Added to the d20 of the attack roll.
  final int attackBonus;

  /// Damage dice plus damage bonus, e.g. `1d8+3`.
  final DiceExpression damage;
  final String damageType;

  /// Short form for buttons and lists: `Langschwert +5, 1d8+3 Hieb`.
  String get summary {
    final sign = attackBonus >= 0 ? '+' : '';
    return '$name $sign$attackBonus, $damage $damageType';
  }
}
