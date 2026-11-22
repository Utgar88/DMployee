/// The rule books the app can follow. Rules that differ between them ask
/// the current ruleset (see `AppSettings.ruleset`) instead of hard-coding
/// one version.
///
/// A new rule book is a new value here; [id] must never change once
/// stored.
enum Ruleset {
  dnd2014(
    id: '5e-2014',
    label: 'D&D 5e (2014)',
    description: 'Regeln von 2014 (SRD 5.1)',
  ),
  dnd2024(
    id: '5e-2024',
    label: 'D&D 5e (2024)',
    description: 'Überarbeitete Regeln von 2024 (SRD 5.2)',
  );

  const Ruleset({
    required this.id,
    required this.label,
    required this.description,
  });

  /// Stable key for storing the choice.
  final String id;
  final String label;
  final String description;

  /// The ruleset used as long as none was chosen.
  static const standard = Ruleset.dnd2014;

  /// The ruleset stored as [id], or null if there is none with this id.
  static Ruleset? byId(String? id) {
    for (final ruleset in values) {
      if (ruleset.id == id) return ruleset;
    }
    return null;
  }
}
