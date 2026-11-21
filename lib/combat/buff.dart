/// A bonus or penalty of an effect: dice like `+1d4` or a fixed value like
/// `-1`.
class Bonus {
  const Bonus._({
    required this.negative,
    required this.count,
    required this.sides,
    required this.flat,
  });

  /// Reads `1d4`, `-1d4`, `1W4`, `2`, `+2` or `-1`.
  ///
  /// Throws a [FormatException] for anything else, including 0.
  factory Bonus.parse(String input) {
    final normalized = input.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final dice = _dicePattern.firstMatch(normalized);
    if (dice != null) {
      final count = dice.group(2)!.isEmpty ? 1 : int.parse(dice.group(2)!);
      final sides = int.parse(dice.group(3)!);
      if (count > 0 && sides > 0) {
        return Bonus._(
          negative: dice.group(1) == '-',
          count: count,
          sides: sides,
          flat: 0,
        );
      }
    }
    final flat = _flatPattern.firstMatch(normalized);
    if (flat != null && int.parse(flat.group(2)!) != 0) {
      return Bonus._(
        negative: flat.group(1) == '-',
        count: 0,
        sides: 0,
        flat: int.parse(flat.group(2)!),
      );
    }
    throw FormatException('Not a bonus like 1d4, -1d4 or 2', input);
  }

  static final _dicePattern = RegExp(r'^([+-]?)(\d*)[dw](\d+)$');
  static final _flatPattern = RegExp(r'^([+-]?)(\d+)$');

  /// True for a penalty.
  final bool negative;

  /// Number of dice; 0 for a fixed value.
  final int count;
  final int sides;

  /// The fixed value without sign; 0 for dice.
  final int flat;

  bool get isDice => count > 0;

  /// The dice without sign, e.g. `1d4`; only meaningful if [isDice].
  String get dice => '${count}d$sides';

  /// [rolled] (or the fixed value) with the sign of this bonus.
  int signed(int rolled) => negative ? -rolled : rolled;

  @override
  String toString() => '${negative ? '-' : '+'}${isDice ? dice : flat}';
}

/// A named effect on a combatant, e.g. Segen (`+1d4` on attack rolls and
/// saving throws), Verhexen (`+1d6` necrotic damage) or Schild des Glaubens
/// (+2 armor class). Penalties are effects too.
class Buff {
  Buff({
    required this.name,
    this.attackBonus,
    this.armorClassBonus = 0,
    this.damageBonus,
    this.damageType,
    this.saveBonus,
    this.roundsLeft,
  });

  factory Buff.fromJson(Map<String, Object?> json) {
    Bonus? bonus(String key) {
      final text = json[key] as String?;
      return text == null ? null : Bonus.parse(text);
    }

    return Buff(
      name: json['name']! as String,
      attackBonus: bonus('attackBonus'),
      armorClassBonus: json['armorClassBonus'] as int? ?? 0,
      // Missing in states saved before damage and saving throw bonuses.
      damageBonus: bonus('damageBonus'),
      damageType: json['damageType'] as String?,
      saveBonus: bonus('saveBonus'),
      roundsLeft: json['roundsLeft'] as int?,
    );
  }

  final String name;

  /// Added to every attack roll of the combatant.
  final Bonus? attackBonus;

  /// Added to the combatant's armor class; negative for a penalty.
  final int armorClassBonus;

  /// Added to the damage of every hit of the combatant. Bonus dice are
  /// doubled on a critical hit, a fixed value is not.
  final Bonus? damageBonus;

  /// Damage type of [damageBonus], e.g. `Nekrotisch`; null if it has the
  /// type of the attack.
  final String? damageType;

  /// Added to every saving throw of the combatant.
  final Bonus? saveBonus;

  /// Turns of the combatant until the effect ends; null if it lasts until
  /// it is removed.
  int? roundsLeft;

  /// What the effect does, e.g. `[Angriff +1d4, RK +2]`.
  List<String> get effects => describeBuffEffects(
    attackBonus: attackBonus?.toString(),
    armorClassBonus: armorClassBonus,
    damageBonus: damageBonus?.toString(),
    damageType: damageType,
    saveBonus: saveBonus?.toString(),
  );

  /// Short form for the combat screen: `Segen: Angriff +1d4 (10)`.
  String get summary {
    final parts = effects;
    return '$name${parts.isEmpty ? '' : ': ${parts.join(', ')}'}'
        '${roundsLeft == null ? '' : ' ($roundsLeft)'}';
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'attackBonus': attackBonus?.toString(),
    'armorClassBonus': armorClassBonus,
    'damageBonus': ?damageBonus?.toString(),
    'damageType': ?damageType,
    'saveBonus': ?saveBonus?.toString(),
    'roundsLeft': roundsLeft,
  };
}

/// `[Angriff +1d4, RK +2, Schaden +1d6 Nekrotisch, Rettungswurf +1d4]` for
/// the given values; empty without any.
List<String> describeBuffEffects({
  String? attackBonus,
  int armorClassBonus = 0,
  String? damageBonus,
  String? damageType,
  String? saveBonus,
}) => [
  if (attackBonus != null) 'Angriff $attackBonus',
  if (armorClassBonus != 0)
    'RK ${armorClassBonus > 0 ? '+' : ''}$armorClassBonus',
  if (damageBonus != null)
    'Schaden $damageBonus${damageType == null ? '' : ' $damageType'}',
  if (saveBonus != null) 'Rettungswurf $saveBonus',
];
