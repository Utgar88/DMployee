import 'dart:math';

import 'ruleset.dart';

/// The rules for short and long rests, which differ between the rule
/// books. Sources: SRD 5.1 "Resting" (2014) and SRD 5.2 rules glossary
/// "Short Rest" and "Long Rest" (2024).
extension RestRules on Ruleset {
  /// Hit points a creature needs to start a short rest.
  int get minHpForShortRest => switch (this) {
    Ruleset.dnd2014 => 0,
    Ruleset.dnd2024 => 1,
  };

  /// Hit points a creature needs to start a long rest (both rule books).
  int get minHpForLongRest => 1;

  /// Hit points regained from one hit die whose roll plus constitution
  /// modifier is [total]: never below 0 (2014), at least 1 (2024).
  int hitDieHealing(int total) => switch (this) {
    Ruleset.dnd2014 => max(0, total),
    Ruleset.dnd2024 => max(1, total),
  };

  /// Spent hit dice regained by a long rest for a character with [total]
  /// hit dice: half of them, at least one (2014), or all (2024).
  int hitDiceRegainedOnLongRest(int total) => switch (this) {
    Ruleset.dnd2014 => max(1, total ~/ 2),
    Ruleset.dnd2024 => total,
  };

  /// [hitDiceRegainedOnLongRest] in words, for the log details.
  String get longRestHitDiceRule => switch (this) {
    Ruleset.dnd2014 => 'die Hälfte aller Trefferwürfel, mindestens 1',
    Ruleset.dnd2024 => 'alle Trefferwürfel',
  };
}
