import '../combat/encounter.dart';
import '../log/log_event.dart';
import '../log/log_repository.dart';
import 'character.dart';
import 'character_repository.dart';

/// Uses spell slots of stored characters and gives them back, also during
/// a combat. Rests refill them (see `RestService`).
class SpellSlotService {
  SpellSlotService({
    required this._characters,
    required this._log,
    required this._encounter,
  });

  final CharacterRepository _characters;
  final LogRepository _log;
  final Encounter _encounter;

  /// [character] uses a slot of [level]. Returns the character as stored
  /// afterwards. Throws a [StateError] if no slot of [level] is left.
  Future<Character> use(Character character, int level) => _change(
    character,
    allowed: (c) => c.slotsRemaining(level) > 0,
    apply: (c) => c.slotsUsed[level] = (c.slotsUsed[level] ?? 0) + 1,
    event: (c) => _event(c, level, SlotChange.used),
  );

  /// [character] gets a used slot of [level] back. Throws a [StateError]
  /// if none of [level] is used.
  Future<Character> restore(Character character, int level) => _change(
    character,
    allowed: (c) => (c.slotsUsed[level] ?? 0) > 0,
    apply: (c) => c.slotsUsed[level] = c.slotsUsed[level]! - 1,
    event: (c) => _event(c, level, SlotChange.restored),
  );

  /// [character] uses a pact magic slot. Throws a [StateError] if none is
  /// left.
  Future<Character> usePact(Character character) => _change(
    character,
    allowed: (c) => c.pactSlotsRemaining > 0,
    apply: (c) => c.pactSlotsUsed++,
    event: (c) => _pactEvent(c, SlotChange.used),
  );

  /// [character] gets a used pact magic slot back. Throws a [StateError]
  /// if none is used.
  Future<Character> restorePact(Character character) => _change(
    character,
    allowed: (c) => c.pactSlotsUsed > 0,
    apply: (c) => c.pactSlotsUsed--,
    event: (c) => _pactEvent(c, SlotChange.restored),
  );

  Future<Character> _change(
    Character given, {
    required bool Function(Character) allowed,
    required void Function(Character) apply,
    required LogEvent Function(Character) event,
  }) async {
    // Pending combat changes go first, so this save builds on them.
    await _encounter.flush();
    final character = await _characters.byId(given.id!);
    if (character == null) {
      throw ArgumentError.value(given, 'character', 'is not stored');
    }
    if (!allowed(character)) {
      throw StateError('Slot change not possible for ${character.name}');
    }
    apply(character);
    await _characters.save(character);
    await _log.add(event(character));
    return character;
  }

  SpellSlotEvent _event(Character c, int level, SlotChange change) =>
      SpellSlotEvent(
        name: c.name,
        level: level,
        change: change,
        remaining: c.slotsRemaining(level),
        total: c.slotsTotal(level),
      );

  SpellSlotEvent _pactEvent(Character c, SlotChange change) => SpellSlotEvent(
    name: c.name,
    level: c.pactSlotLevel,
    pact: true,
    change: change,
    remaining: c.pactSlotsRemaining,
    total: c.pactSlots,
  );
}
