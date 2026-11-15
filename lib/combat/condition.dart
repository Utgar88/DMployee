import '../dice/dice_roller.dart';

const _cannotAct = 'kann keine Aktionen ausführen';
const _criticalUpClose =
    'Treffer aus höchstens 1,5 m sind kritisch (nicht automatisch)';

/// The conditions of the D&D 5e rules.
///
/// Only effects that hold in every situation are applied by the app:
/// advantage or disadvantage on attack rolls, and the damage resistance of
/// petrified creatures. Everything that depends on distance or line of
/// sight is given as a hint, and the game master sets it by hand.
enum Condition {
  blinded(
    'Blind',
    attackerEffect: RollMode.disadvantage,
    targetEffect: RollMode.advantage,
  ),
  charmed('Bezaubert', attackerHint: 'kann den Bezaubernden nicht angreifen'),
  deafened('Taub'),
  frightened(
    'Verängstigt',
    attackerHint:
        'Nachteil, solange die Quelle der Furcht in Sicht ist '
        '(selbst einstellen)',
  ),
  grappled('Gepackt'),
  incapacitated('Kampfunfähig', attackerHint: _cannotAct),
  invisible(
    'Unsichtbar',
    attackerEffect: RollMode.advantage,
    targetEffect: RollMode.disadvantage,
  ),
  paralyzed(
    'Gelähmt',
    targetEffect: RollMode.advantage,
    attackerHint: _cannotAct,
    targetHint: _criticalUpClose,
  ),
  petrified(
    'Versteinert',
    targetEffect: RollMode.advantage,
    attackerHint: _cannotAct,
  ),
  poisoned('Vergiftet', attackerEffect: RollMode.disadvantage),
  prone(
    'Liegend',
    attackerEffect: RollMode.disadvantage,
    targetHint:
        'Vorteil aus höchstens 1,5 m, sonst Nachteil (selbst einstellen)',
  ),
  restrained(
    'Festgesetzt',
    attackerEffect: RollMode.disadvantage,
    targetEffect: RollMode.advantage,
  ),
  stunned(
    'Betäubt',
    targetEffect: RollMode.advantage,
    attackerHint: _cannotAct,
  ),
  unconscious(
    'Bewusstlos',
    targetEffect: RollMode.advantage,
    attackerHint: _cannotAct,
    targetHint: _criticalUpClose,
  );

  const Condition(
    this.label, {
    this.attackerEffect,
    this.targetEffect,
    this.attackerHint,
    this.targetHint,
  });

  /// German name shown in the app.
  final String label;

  /// Advantage or disadvantage on attack rolls made by a creature with
  /// this condition; null if there is none.
  final RollMode? attackerEffect;

  /// Advantage or disadvantage on attack rolls made against a creature
  /// with this condition; null if there is none.
  final RollMode? targetEffect;

  /// Rule for attacking with this condition that the app does not apply.
  final String? attackerHint;

  /// Rule for attacks against this condition that the app does not apply.
  final String? targetHint;

  /// The condition stored under [name], or null for an unknown name.
  static Condition? fromName(Object? name) => values.asNameMap()[name];
}

/// A condition a combatant currently has.
class ActiveCondition {
  ActiveCondition(this.condition, {this.roundsLeft});

  /// Restores a condition saved with [toJson]; null for an unknown one.
  static ActiveCondition? fromJson(Map<String, Object?> json) {
    final condition = Condition.fromName(json['condition']);
    if (condition == null) return null;
    return ActiveCondition(condition, roundsLeft: json['roundsLeft'] as int?);
  }

  final Condition condition;

  /// Turns of the combatant until the condition ends; null if it lasts
  /// until it is removed.
  int? roundsLeft;

  Map<String, Object?> toJson() => {
    'condition': condition.name,
    'roundsLeft': roundsLeft,
  };
}
