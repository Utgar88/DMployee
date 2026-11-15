import 'attack.dart';

/// A participant in an encounter. Characters and monsters will later supply
/// exactly these values.
class Combatant {
  Combatant({
    required this.name,
    required this.armorClass,
    required this.maxHp,
    this.initiativeBonus = 0,
    List<Attack> attacks = const [],
  }) : hp = maxHp,
       attacks = List.of(attacks);

  /// Restores a combatant saved with [toJson].
  factory Combatant.fromJson(Map<String, Object?> json) {
    return Combatant(
        name: json['name']! as String,
        armorClass: json['armorClass']! as int,
        maxHp: json['maxHp']! as int,
        initiativeBonus: json['initiativeBonus']! as int,
        attacks: [
          for (final attack in json['attacks']! as List)
            Attack.fromJson((attack as Map).cast<String, Object?>()),
        ],
      )
      ..hp = json['hp']! as int
      ..initiative = json['initiative'] as int?;
  }

  String name;
  int armorClass;
  int maxHp;

  /// Current hit points, between 0 and [maxHp].
  int hp;
  int initiativeBonus;
  final List<Attack> attacks;

  /// Initiative total of the running combat; null while no combat runs.
  int? initiative;

  /// At 0 hit points a combatant no longer takes turns.
  bool get isDown => hp <= 0;

  Map<String, Object?> toJson() => {
    'name': name,
    'armorClass': armorClass,
    'maxHp': maxHp,
    'hp': hp,
    'initiativeBonus': initiativeBonus,
    'initiative': initiative,
    'attacks': [for (final attack in attacks) attack.toJson()],
  };
}
