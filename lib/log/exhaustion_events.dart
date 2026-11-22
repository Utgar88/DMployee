part of 'log_event.dart';

/// Stored as [ConditionEffect.condition] when exhaustion gave an attacker
/// disadvantage; it is not one of the `Condition` values.
const exhaustionCondition = 'exhaustion';

/// The exhaustion level of a creature changed, in or outside of a combat.
/// Long rests lower it as part of their [RestEvent] instead.
class ExhaustionEvent extends LogEvent {
  const ExhaustionEvent({
    required this.name,
    required this.before,
    required this.after,
    required this.ruleset,
  });

  factory ExhaustionEvent.fromJson(Map<String, Object?> json) {
    return ExhaustionEvent(
      name: json['name']! as String,
      before: json['before']! as int,
      after: json['after']! as int,
      ruleset: json['ruleset']! as String,
    );
  }

  static const typeName = 'exhaustion';

  final String name;

  /// Exhaustion level before and after the change, 0 to 6.
  final int before;
  final int after;

  /// Id of the ruleset in force (see `Ruleset.id`), so the details show the
  /// effects that applied then.
  final String ruleset;

  @override
  String get type => typeName;

  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'before': before,
    'after': after,
    'ruleset': ruleset,
  };
}
