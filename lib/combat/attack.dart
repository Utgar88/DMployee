import '../dice/dice_expression.dart';

/// An attack stored on a combatant, e.g. `Langschwert +5, 1d8+3 Hieb`.
class Attack {
  const Attack({
    required this.name,
    required this.attackBonus,
    required this.damage,
    required this.damageType,
  });

  factory Attack.fromJson(Map<String, Object?> json) {
    return Attack(
      name: json['name']! as String,
      attackBonus: json['attackBonus']! as int,
      damage: DiceExpression.parse(json['damage']! as String),
      damageType: json['damageType']! as String,
    );
  }

  final String name;

  /// Added to the d20 of the attack roll.
  final int attackBonus;

  /// Damage dice plus damage bonus, e.g. `1d8+3`.
  final DiceExpression damage;
  final String damageType;

  Map<String, Object?> toJson() => {
    'name': name,
    'attackBonus': attackBonus,
    'damage': '$damage',
    'damageType': damageType,
  };

  /// Short form for buttons and lists: `Langschwert +5, 1d8+3 Hieb`.
  String get summary {
    final sign = attackBonus >= 0 ? '+' : '';
    return '$name $sign$attackBonus, $damage $damageType';
  }
}
