import '../combat/damage.dart';
import '../dice/dice_roller.dart';
import '../dice/modifier.dart';
import 'roll_record.dart';

part 'combat_events.dart';
part 'exhaustion_events.dart';
part 'rest_events.dart';
part 'spell_slot_events.dart';

/// Something that happened and is kept in the log.
///
/// Events store facts, never finished sentences. The text shown in the log
/// is produced from these facts by the LogFormatter, so the wording can
/// change later without touching stored entries.
///
/// To add a new kind of event: add a subclass in this library (this file or
/// one of its parts), give it a unique [type] and register it in
/// [LogEvent.fromJson].
sealed class LogEvent {
  const LogEvent();

  /// Restores an event from its stored [type] and JSON payload. Types this
  /// app version does not know are kept as [UnknownEvent] instead of failing.
  factory LogEvent.fromJson(String type, Map<String, Object?> json) {
    return switch (type) {
      FreeRollEvent.typeName => FreeRollEvent.fromJson(json),
      AttackEvent.typeName => AttackEvent.fromJson(json),
      InitiativeEvent.typeName => InitiativeEvent.fromJson(json),
      RoundEvent.typeName => RoundEvent.fromJson(json),
      CombatantDownEvent.typeName => CombatantDownEvent.fromJson(json),
      HpChangeEvent.typeName => HpChangeEvent.fromJson(json),
      DeathSaveEvent.typeName => DeathSaveEvent.fromJson(json),
      DyingDamageEvent.typeName => DyingDamageEvent.fromJson(json),
      CombatantStableEvent.typeName => CombatantStableEvent.fromJson(json),
      CombatantDiedEvent.typeName => CombatantDiedEvent.fromJson(json),
      ConditionEvent.typeName => ConditionEvent.fromJson(json),
      BuffEvent.typeName => BuffEvent.fromJson(json),
      TempHpEvent.typeName => TempHpEvent.fromJson(json),
      CombatantRevivedEvent.typeName => CombatantRevivedEvent.fromJson(json),
      RestEvent.typeName => RestEvent.fromJson(json),
      HitDieEvent.typeName => HitDieEvent.fromJson(json),
      SpellSlotEvent.typeName => SpellSlotEvent.fromJson(json),
      ExhaustionEvent.typeName => ExhaustionEvent.fromJson(json),
      _ => UnknownEvent(type, json),
    };
  }

  /// Stable identifier stored next to the payload.
  String get type;

  Map<String, Object?> toJson();
}

/// A roll made directly in the dice roller, without any character involved.
class FreeRollEvent extends LogEvent {
  const FreeRollEvent({required this.roll, this.dc});

  factory FreeRollEvent.fromJson(Map<String, Object?> json) {
    return FreeRollEvent(
      roll: RollRecord.fromJson((json['roll']! as Map).cast<String, Object?>()),
      dc: json['dc'] as int?,
    );
  }

  static const typeName = 'freeRoll';

  final RollRecord roll;

  /// Difficulty class the roll was made against, if any.
  final int? dc;

  /// Whether the roll met the [dc]; null when no [dc] was set.
  bool? get isSuccess => dc == null ? null : roll.total >= dc!;

  @override
  String get type => typeName;

  @override
  Map<String, Object?> toJson() => {'roll': roll.toJson(), 'dc': ?dc};
}

/// An event written by a newer app version. Its payload is kept untouched.
class UnknownEvent extends LogEvent {
  const UnknownEvent(this.type, this.payload);

  @override
  final String type;

  final Map<String, Object?> payload;

  @override
  Map<String, Object?> toJson() => payload;
}
