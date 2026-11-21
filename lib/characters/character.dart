import '../combat/attack.dart';
import 'ability.dart';

/// A player character as the game master keeps it between sessions: fixed
/// values from the character sheet plus the current state (hit points,
/// death saving throws), which combat changes.
///
/// Derived values (modifiers, proficiency bonus, initiative, saving throws)
/// are calculated, never stored.
class Character {
  /// Throws an [ArgumentError] for an empty [name], a [level] outside 1 to
  /// 20, ability scores outside 1 to 30, [maxHp] below 1 or [armorClass]
  /// below 0.
  Character({
    this.id,
    required String name,
    String player = '',
    String characterClass = '',
    this.level = 1,
    Map<Ability, int> abilityScores = const {},
    required this.maxHp,
    required this.armorClass,
    Set<Ability> saveProficiencies = const {},
    List<Attack> attacks = const [],
    int? hp,
  }) : name = name.trim(),
       player = player.trim(),
       characterClass = characterClass.trim(),
       abilityScores = Map.unmodifiable({
         for (final ability in Ability.values)
           ability: abilityScores[ability] ?? 10,
       }),
       saveProficiencies = Set.unmodifiable(saveProficiencies),
       attacks = List.unmodifiable(attacks),
       hp = hp ?? maxHp {
    if (this.name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (level < 1 || level > 20) {
      throw ArgumentError.value(level, 'level', 'must be 1 to 20');
    }
    for (final MapEntry(:key, :value) in this.abilityScores.entries) {
      if (value < 1 || value > 30) {
        throw ArgumentError.value(value, key.name, 'must be 1 to 30');
      }
    }
    if (maxHp < 1) {
      throw ArgumentError.value(maxHp, 'maxHp', 'must be at least 1');
    }
    if (armorClass < 0) {
      throw ArgumentError.value(armorClass, 'armorClass', 'must not be < 0');
    }
  }

  factory Character.fromJson(Map<String, Object?> json) {
    final scores = (json['abilityScores']! as Map).cast<String, Object?>();
    return Character(
        id: json['id'] as int?,
        name: json['name']! as String,
        player: json['player'] as String? ?? '',
        characterClass: json['characterClass'] as String? ?? '',
        level: json['level']! as int,
        abilityScores: {
          for (final ability in Ability.values)
            if (scores[ability.name] case final int score) ability: score,
        },
        maxHp: json['maxHp']! as int,
        armorClass: json['armorClass']! as int,
        saveProficiencies: {
          for (final name in json['saveProficiencies'] as List? ?? const [])
            ?Ability.values.asNameMap()[name],
        },
        attacks: [
          for (final attack in json['attacks'] as List? ?? const [])
            Attack.fromJson((attack as Map).cast<String, Object?>()),
        ],
        hp: json['hp']! as int,
      )
      ..tempHp = json['tempHp'] as int? ?? 0
      ..deathSaveSuccesses = json['deathSaveSuccesses'] as int? ?? 0
      ..deathSaveFailures = json['deathSaveFailures'] as int? ?? 0
      ..isStable = json['isStable'] as bool? ?? false
      ..isDead = json['isDead'] as bool? ?? false;
  }

  /// Set by the repository when the character is first saved.
  int? id;

  final String name;

  /// Who plays the character; may be empty.
  final String player;

  /// Free text for now, e.g. `Kämpferin`; may be empty.
  final String characterClass;
  final int level;

  /// One score per ability, 1 to 30.
  final Map<Ability, int> abilityScores;
  final int maxHp;
  final int armorClass;

  /// Abilities whose saving throws add the proficiency bonus.
  final Set<Ability> saveProficiencies;
  final List<Attack> attacks;

  /// Current state, changed by combat.
  int hp;
  int tempHp = 0;
  int deathSaveSuccesses = 0;
  int deathSaveFailures = 0;
  bool isStable = false;
  bool isDead = false;

  int score(Ability ability) => abilityScores[ability]!;

  int modifier(Ability ability) => abilityModifier(score(ability));

  int get proficiencyBonus => proficiencyBonusFor(level);

  /// The dexterity modifier.
  int get initiativeBonus => modifier(Ability.dexterity);

  /// Modifier for a saving throw on [ability], with the proficiency bonus
  /// if the character is proficient.
  int savingThrow(Ability ability) =>
      modifier(ability) +
      (saveProficiencies.contains(ability) ? proficiencyBonus : 0);

  /// `Kämpferin 5`, or `Stufe 5` without a class.
  String get classAndLevel =>
      characterClass.isEmpty ? 'Stufe $level' : '$characterClass $level';

  /// A copy with other sheet values; values left out stay. Id and current
  /// state are kept. An unhurt character has full hit points with a new
  /// [maxHp]; otherwise hit points stay but never exceed the new maximum.
  ///
  /// Invalid values throw an [ArgumentError] like the constructor.
  Character withValues({
    String? name,
    String? player,
    String? characterClass,
    int? level,
    Map<Ability, int>? abilityScores,
    int? maxHp,
    int? armorClass,
    Set<Ability>? saveProficiencies,
    List<Attack>? attacks,
  }) {
    final newMaxHp = maxHp ?? this.maxHp;
    final unhurt = hp == this.maxHp;
    return Character(
        id: id,
        name: name ?? this.name,
        player: player ?? this.player,
        characterClass: characterClass ?? this.characterClass,
        level: level ?? this.level,
        abilityScores: abilityScores ?? this.abilityScores,
        maxHp: newMaxHp,
        armorClass: armorClass ?? this.armorClass,
        saveProficiencies: saveProficiencies ?? this.saveProficiencies,
        attacks: attacks ?? this.attacks,
        hp: unhurt || hp > newMaxHp ? newMaxHp : hp,
      )
      ..tempHp = tempHp
      ..deathSaveSuccesses = deathSaveSuccesses
      ..deathSaveFailures = deathSaveFailures
      ..isStable = isStable
      ..isDead = isDead;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'player': player,
    'characterClass': characterClass,
    'level': level,
    'abilityScores': {
      for (final MapEntry(:key, :value) in abilityScores.entries)
        key.name: value,
    },
    'maxHp': maxHp,
    'armorClass': armorClass,
    'saveProficiencies': [
      for (final ability in saveProficiencies) ability.name,
    ],
    'attacks': [for (final attack in attacks) attack.toJson()],
    'hp': hp,
    'tempHp': tempHp,
    'deathSaveSuccesses': deathSaveSuccesses,
    'deathSaveFailures': deathSaveFailures,
    'isStable': isStable,
    'isDead': isDead,
  };
}
