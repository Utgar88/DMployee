import 'attack.dart';
import 'damage.dart';

/// A participant in an encounter. Characters and monsters will later supply
/// exactly these values.
class Combatant {
  Combatant({
    required this.name,
    required this.armorClass,
    required this.maxHp,
    this.initiativeBonus = 0,
    this.isPlayer = false,
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
        isPlayer: json['isPlayer'] as bool? ?? false,
        attacks: [
          for (final attack in json['attacks']! as List)
            Attack.fromJson((attack as Map).cast<String, Object?>()),
        ],
      )
      ..hp = json['hp']! as int
      ..initiative = json['initiative'] as int?
      // Missing in states saved before death saving throws existed.
      ..deathSaveSuccesses = json['deathSaveSuccesses'] as int? ?? 0
      ..deathSaveFailures = json['deathSaveFailures'] as int? ?? 0
      ..isStable = json['isStable'] as bool? ?? false
      ..isDead = json['isDead'] as bool? ?? false
      ..damageTraits.addAll({
        for (final MapEntry(:key, :value)
            in (json['damageTraits'] as Map? ?? const {}).entries)
          key as String: ?DamageEffect.fromName(value),
      });
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

  /// Player characters make death saving throws at 0 hit points; everyone
  /// else is simply out of the fight.
  bool isPlayer;

  /// Death saving throws so far, 0 to 3 each. Reset when the combatant
  /// regains hit points or becomes stable.
  int deathSaveSuccesses = 0;
  int deathSaveFailures = 0;

  /// At 0 hit points but no longer dying; ends when damage is taken.
  bool isStable = false;
  bool isDead = false;

  /// Resistance, vulnerability or immunity per damage type, e.g.
  /// `{'Feuer': DamageEffect.resistance}`. Change it through
  /// `Encounter.setDamageTrait`.
  final Map<String, DamageEffect> damageTraits = {};

  /// How this combatant reacts to damage of [type]; null if normally.
  DamageEffect? damageEffectFor(String? type) {
    if (type == null) return null;
    final wanted = normalizeDamageType(type);
    for (final MapEntry(:key, :value) in damageTraits.entries) {
      if (normalizeDamageType(key) == wanted) return value;
    }
    return null;
  }

  /// At 0 hit points.
  bool get isDown => hp <= 0;

  /// A player character at 0 hit points who still has to make death saving
  /// throws.
  bool get isDying => isPlayer && isDown && !isStable && !isDead;

  /// Whether the combatant gets a turn: everyone standing, plus dying
  /// player characters so they can roll their death saving throw.
  bool get takesTurns => !isDown || isDying;

  Map<String, Object?> toJson() => {
    'name': name,
    'armorClass': armorClass,
    'maxHp': maxHp,
    'hp': hp,
    'initiativeBonus': initiativeBonus,
    'isPlayer': isPlayer,
    'deathSaveSuccesses': deathSaveSuccesses,
    'deathSaveFailures': deathSaveFailures,
    'isStable': isStable,
    'isDead': isDead,
    'damageTraits': {
      for (final MapEntry(:key, :value) in damageTraits.entries)
        key: value.name,
    },
    'initiative': initiative,
    'attacks': [for (final attack in attacks) attack.toJson()],
  };
}
