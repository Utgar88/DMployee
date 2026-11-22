part of 'log_event.dart';

enum SlotChange { used, restored }

/// A character used a spell slot or got one back outside of a rest (e.g.
/// after a mistake).
class SpellSlotEvent extends LogEvent {
  const SpellSlotEvent({
    required this.name,
    required this.level,
    required this.change,
    required this.remaining,
    required this.total,
    this.pact = false,
  });

  factory SpellSlotEvent.fromJson(Map<String, Object?> json) {
    return SpellSlotEvent(
      name: json['name']! as String,
      level: json['level']! as int,
      change: SlotChange.values.byName(json['change']! as String),
      remaining: json['remaining']! as int,
      total: json['total']! as int,
      pact: json['pact'] as bool? ?? false,
    );
  }

  static const typeName = 'spellSlot';

  final String name;

  /// Spell level of the slot, 1 to 9.
  final int level;

  /// True for a pact magic slot.
  final bool pact;
  final SlotChange change;

  /// Slots of this kind left afterwards, out of [total].
  final int remaining;
  final int total;

  @override
  String get type => typeName;

  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'level': level,
    if (pact) 'pact': true,
    'change': change.name,
    'remaining': remaining,
    'total': total,
  };
}
