import '../combat/attack.dart';
import '../rules/exhaustion_rules.dart';
import '../rules/ruleset.dart';
import 'ability.dart';

/// A player character as the game master keeps it between sessions: fixed
/// values from the character sheet plus the current state (hit points,
/// death saving throws), which combat changes.
///
/// Derived values (modifiers, proficiency bonus, initiative, saving throws)
/// are calculated, never stored.
class Character {
  /// Throws an [ArgumentError] for an empty [name], a [level] outside 1 to
  /// 20, ability scores outside 1 to 30, [maxHp] below 1, [armorClass]
  /// below 0, a [hitDie] not in [hitDieSizes], spell slots outside levels
  /// 1 to 9 or counts outside 0 to 9, or a [pactSlotLevel] outside 1 to 5.
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
    this.hitDie = 8,
    Map<int, int> spellSlots = const {},
    this.pactSlots = 0,
    this.pactSlotLevel = 1,
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
       spellSlots = Map.unmodifiable({
         for (final MapEntry(:key, :value) in spellSlots.entries)
           if (value != 0 || key < 1 || key > 9) key: value,
       }),
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
    if (!hitDieSizes.contains(hitDie)) {
      throw ArgumentError.value(
        hitDie,
        'hitDie',
        'must be one of $hitDieSizes',
      );
    }
    for (final MapEntry(:key, :value) in this.spellSlots.entries) {
      if (key < 1 || key > 9) {
        throw ArgumentError.value(key, 'spellSlots', 'levels are 1 to 9');
      }
      _checkSlotCount(value, 'spellSlots');
    }
    _checkSlotCount(pactSlots, 'pactSlots');
    if (pactSlotLevel < 1 || pactSlotLevel > 5) {
      throw ArgumentError.value(
        pactSlotLevel,
        'pactSlotLevel',
        'must be 1 to 5',
      );
    }
  }

  static void _checkSlotCount(int count, String name) {
    if (count < 0 || count > 9) {
      throw ArgumentError.value(count, name, 'must be 0 to 9');
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
        hitDie: json['hitDie'] as int? ?? 8,
        spellSlots: _levelMap(json['spellSlots']),
        pactSlots: json['pactSlots'] as int? ?? 0,
        pactSlotLevel: json['pactSlotLevel'] as int? ?? 1,
        hp: json['hp']! as int,
      )
      ..hitDiceSpent = json['hitDiceSpent'] as int? ?? 0
      ..slotsUsed.addAll(_levelMap(json['slotsUsed']))
      ..pactSlotsUsed = json['pactSlotsUsed'] as int? ?? 0
      ..tempHp = json['tempHp'] as int? ?? 0
      ..deathSaveSuccesses = json['deathSaveSuccesses'] as int? ?? 0
      ..deathSaveFailures = json['deathSaveFailures'] as int? ?? 0
      ..isStable = json['isStable'] as bool? ?? false
      ..isDead = json['isDead'] as bool? ?? false
      ..exhaustion = (json['exhaustion'] as int? ?? 0).clamp(0, maxExhaustion);
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

  /// The possible hit dice: d6, d8, d10 and d12.
  static const hitDieSizes = [6, 8, 10, 12];

  /// Sides of the hit die, e.g. 10 for a d10. Free choice until classes
  /// come from the compendium.
  final int hitDie;

  /// One hit die per level.
  int get hitDiceTotal => level;

  /// Hit dice spent on short rests and not yet regained, 0 to [level].
  int hitDiceSpent = 0;

  int get hitDiceRemaining => hitDiceTotal - hitDiceSpent;

  /// Spell slots per spell level (1 to 9); levels without slots are left
  /// out. Entered by hand until classes come from the compendium.
  final Map<int, int> spellSlots;

  /// Pact magic (warlock): [pactSlots] slots, all of [pactSlotLevel]. They
  /// come back on a short rest.
  final int pactSlots;
  final int pactSlotLevel;

  /// Used spell slots per level; levels without entry have none used.
  final Map<int, int> slotsUsed = {};

  /// Used pact magic slots.
  int pactSlotsUsed = 0;

  /// Levels that have spell slots, in ascending order.
  List<int> get slotLevels => spellSlots.keys.toList()..sort();

  bool get hasSpellSlots => spellSlots.isNotEmpty || pactSlots > 0;

  int slotsTotal(int level) => spellSlots[level] ?? 0;

  int slotsRemaining(int level) => slotsTotal(level) - (slotsUsed[level] ?? 0);

  int get pactSlotsRemaining => pactSlots - pactSlotsUsed;

  /// Current state, changed by combat.
  int hp;
  int tempHp = 0;
  int deathSaveSuccesses = 0;
  int deathSaveFailures = 0;
  bool isStable = false;
  bool isDead = false;

  /// Exhaustion level, 0 to [maxExhaustion]. Its effects depend on the
  /// ruleset (see `ExhaustionRules`).
  int exhaustion = 0;

  /// The hit point maximum under [ruleset]: [maxHp], halved by exhaustion
  /// under the 2014 rules.
  int maxHpUnder(Ruleset ruleset) =>
      ruleset.maxHpWithExhaustion(maxHp, exhaustion);

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
  /// Spent hit dice and used spell slots never exceed what is left.
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
    int? hitDie,
    Map<int, int>? spellSlots,
    int? pactSlots,
    int? pactSlotLevel,
  }) {
    final newLevel = level ?? this.level;
    final newMaxHp = maxHp ?? this.maxHp;
    final unhurt = hp == this.maxHp;
    return Character(
        id: id,
        name: name ?? this.name,
        player: player ?? this.player,
        characterClass: characterClass ?? this.characterClass,
        level: newLevel,
        abilityScores: abilityScores ?? this.abilityScores,
        maxHp: newMaxHp,
        armorClass: armorClass ?? this.armorClass,
        saveProficiencies: saveProficiencies ?? this.saveProficiencies,
        attacks: attacks ?? this.attacks,
        hitDie: hitDie ?? this.hitDie,
        spellSlots: spellSlots ?? this.spellSlots,
        pactSlots: pactSlots ?? this.pactSlots,
        pactSlotLevel: pactSlotLevel ?? this.pactSlotLevel,
        hp: unhurt || hp > newMaxHp ? newMaxHp : hp,
      )
      ..hitDiceSpent = hitDiceSpent > newLevel ? newLevel : hitDiceSpent
      ..takeUsedSlots(this)
      ..tempHp = tempHp
      ..deathSaveSuccesses = deathSaveSuccesses
      ..deathSaveFailures = deathSaveFailures
      ..isStable = isStable
      ..isDead = isDead
      ..exhaustion = exhaustion;
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
    'hitDie': hitDie,
    'hp': hp,
    'hitDiceSpent': hitDiceSpent,
    if (spellSlots.isNotEmpty)
      'spellSlots': {
        for (final MapEntry(:key, :value) in spellSlots.entries) '$key': value,
      },
    if (slotsUsed.values.any((used) => used > 0))
      'slotsUsed': {
        for (final MapEntry(:key, :value) in slotsUsed.entries)
          if (value > 0) '$key': value,
      },
    if (pactSlots > 0) ...{
      'pactSlots': pactSlots,
      'pactSlotLevel': pactSlotLevel,
    },
    if (pactSlotsUsed > 0) 'pactSlotsUsed': pactSlotsUsed,
    'tempHp': tempHp,
    'deathSaveSuccesses': deathSaveSuccesses,
    'deathSaveFailures': deathSaveFailures,
    'isStable': isStable,
    'isDead': isDead,
    if (exhaustion > 0) 'exhaustion': exhaustion,
  };

  /// Takes over the used slots of [other], but never more than this
  /// character has.
  void takeUsedSlots(Character other) {
    slotsUsed.clear();
    for (final MapEntry(key: level, value: used) in other.slotsUsed.entries) {
      final capped = used > slotsTotal(level) ? slotsTotal(level) : used;
      if (capped > 0) slotsUsed[level] = capped;
    }
    pactSlotsUsed = other.pactSlotsUsed > pactSlots
        ? pactSlots
        : other.pactSlotsUsed;
  }

  /// Reads `{"1": 4, "3": 2}` as level → count.
  static Map<int, int> _levelMap(Object? json) => {
    if (json is Map)
      for (final MapEntry(:key, :value) in json.entries)
        ?int.tryParse('$key'): value as int,
  };
}
