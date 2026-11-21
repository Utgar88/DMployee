/// The six abilities of the D&D 5e rules.
enum Ability {
  strength('Stärke', 'ST'),
  dexterity('Geschicklichkeit', 'GE'),
  constitution('Konstitution', 'KO'),
  intelligence('Intelligenz', 'IN'),
  wisdom('Weisheit', 'WE'),
  charisma('Charisma', 'CH');

  const Ability(this.label, this.short);

  /// German name shown in the app.
  final String label;

  /// German abbreviation, e.g. `ST`.
  final String short;
}

/// Modifier of an ability [score]: (score - 10) / 2, rounded down.
int abilityModifier(int score) => ((score - 10) / 2).floor();

/// [value] with its sign, e.g. `+3`, `+0` or `-1`.
String formatModifier(int value) => value < 0 ? '$value' : '+$value';

/// Proficiency bonus at character [level]: +2 at levels 1 to 4, one more
/// every four levels, +6 from level 17.
int proficiencyBonusFor(int level) => 2 + (level - 1) ~/ 4;
