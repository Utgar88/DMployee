/// The damage types of the D&D 5e rules, in German.
const damageTypes = [
  'Blitz',
  'Energie',
  'Feuer',
  'Gift',
  'Gleißend',
  'Hieb',
  'Kälte',
  'Nekrotisch',
  'Psychisch',
  'Säure',
  'Schall',
  'Stich',
  'Wucht',
];

/// How a combatant reacts to one damage type.
enum DamageEffect {
  /// Half damage, rounded down.
  resistance('Resistenz'),

  /// Double damage.
  vulnerability('Anfälligkeit'),

  /// No damage.
  immunity('Immunität');

  const DamageEffect(this.label);

  /// German name shown in the app.
  final String label;

  /// The effect stored under [name], or null for an unknown name.
  static DamageEffect? fromName(Object? name) => values.asNameMap()[name];
}

/// Damage types are compared without regard to case and surrounding spaces.
String normalizeDamageType(String type) => type.trim().toLowerCase();

/// [raw] damage after [effect] was applied.
int adjustDamage(int raw, DamageEffect? effect) {
  return switch (effect) {
    null => raw,
    DamageEffect.resistance => raw ~/ 2,
    DamageEffect.vulnerability => raw * 2,
    DamageEffect.immunity => 0,
  };
}
