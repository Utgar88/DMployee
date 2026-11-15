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
}
