import 'dart:math';

import 'ruleset.dart';

/// Highest exhaustion level; a creature at this level dies.
const maxExhaustion = 6;

/// The rules for exhaustion, which differ between the rule books.
/// Sources: SRD 5.1 appendix "Conditions", Exhaustion (2014) and SRD 5.2
/// rules glossary "Exhaustion" (2024).
///
/// In both books the effects of a level add to those of all lower levels,
/// a long rest lowers the level by 1 and level 6 is death.
extension ExhaustionRules on Ruleset {
  /// Penalty on every d20 test at exhaustion [level]: −2 per level (2024),
  /// none (2014).
  int exhaustionD20Penalty(int level) => switch (this) {
    Ruleset.dnd2014 => 0,
    Ruleset.dnd2024 => -2 * level,
  };

  /// Disadvantage on ability checks, from level 1 (2014 only).
  bool exhaustionDisadvantageOnChecks(int level) => switch (this) {
    Ruleset.dnd2014 => level >= 1,
    Ruleset.dnd2024 => false,
  };

  /// Disadvantage on attack rolls and saving throws, from level 3 (2014
  /// only).
  bool exhaustionDisadvantageOnAttacksAndSaves(int level) => switch (this) {
    Ruleset.dnd2014 => level >= 3,
    Ruleset.dnd2024 => false,
  };

  /// The hit point maximum at exhaustion [level]: halved from level 4,
  /// rounded down but at least 1 (2014), unchanged (2024).
  int maxHpWithExhaustion(int maxHp, int level) => switch (this) {
    Ruleset.dnd2014 when level >= 4 => max(1, maxHp ~/ 2),
    _ => maxHp,
  };

  /// Whether exhaustion [level] kills (both rule books: level 6).
  bool exhaustionKills(int level) => level >= maxExhaustion;

  /// The effects in force at exhaustion [level], in words.
  List<String> exhaustionEffects(int level) {
    if (level <= 0) return const [];
    switch (this) {
      case Ruleset.dnd2014:
        const effects = [
          'Nachteil auf Attributswürfe',
          'Bewegungsrate halbiert',
          'Nachteil auf Angriffs- und Rettungswürfe',
          'Maximale TP halbiert',
          'Bewegungsrate 0',
          'Tod',
        ];
        return effects.take(min(level, maxExhaustion)).toList();
      case Ruleset.dnd2024:
        if (exhaustionKills(level)) return const ['Tod'];
        final speed = (level * 1.5).toString().replaceAll('.0', '');
        return [
          '−${2 * level} auf alle W20-Würfe',
          'Bewegungsrate −${speed.replaceAll('.', ',')} m',
        ];
    }
  }
}
