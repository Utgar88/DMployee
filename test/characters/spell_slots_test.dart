import 'package:dmployee/characters/character.dart';
import 'package:dmployee/characters/character_repository.dart';
import 'package:dmployee/characters/spell_slots.dart';
import 'package:dmployee/combat/encounter.dart';
import 'package:dmployee/dice/dice_roller.dart';
import 'package:dmployee/log/log_event.dart';
import 'package:dmployee/log/log_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixed_random.dart';

/// Mira: 4 slots of level 1, 2 of level 3, pact magic 2 slots of level 3.
class Scene {
  Scene({List<int> faces = const []}) {
    encounter = Encounter(
      log: log,
      characters: characters,
      roller: DiceRoller(FixedRandom(faces)),
    );
    slots = SpellSlotService(
      characters: characters,
      log: log,
      encounter: encounter,
    );
  }

  final log = InMemoryLogRepository();
  final characters = InMemoryCharacterRepository();
  late final Encounter encounter;
  late final SpellSlotService slots;

  Future<Character> mira() => characters.save(
    Character(
      name: 'Mira',
      level: 5,
      maxHp: 28,
      armorClass: 12,
      spellSlots: {1: 4, 3: 2},
      pactSlots: 2,
      pactSlotLevel: 3,
    ),
  );

  Future<Character> stored(Character character) async =>
      (await characters.byId(character.id!))!;

  Future<List<LogEvent>> events() async => [
    for (final entry in (await log.entries()).reversed) entry.event,
  ];
}

void main() {
  group('Zauberplätze verbrauchen', () {
    test('Ein verbrauchter Platz fehlt danach bei diesem Grad', () async {
      final scene = Scene();
      final mira = await scene.mira();

      final after = await scene.slots.use(mira, 3);

      expect(after.slotsRemaining(3), 1);
      expect(after.slotsRemaining(1), 4);
      expect((await scene.stored(mira)).slotsRemaining(3), 1);
    });

    test('Der Verbrauch landet mit Grad und übrigen Plätzen im Log', () async {
      final scene = Scene();
      final mira = await scene.mira();

      await scene.slots.use(mira, 3);

      final event = (await scene.events()).single as SpellSlotEvent;
      expect(event.name, 'Mira');
      expect(event.level, 3);
      expect(event.pact, isFalse);
      expect(event.change, SlotChange.used);
      expect(event.remaining, 1);
      expect(event.total, 2);
    });

    test('Ohne übrigen Platz bei diesem Grad wird nichts verbraucht', () async {
      final scene = Scene();
      final mira = await scene.mira();
      await scene.slots.use(mira, 3);
      await scene.slots.use(mira, 3);

      expect(() => scene.slots.use(mira, 3), throwsStateError);
      expect(() => scene.slots.use(mira, 2), throwsStateError);
      expect(await scene.events(), hasLength(2));
    });

    test('Ein verbrauchter Platz lässt sich zurückgeben, z.B. nach einem '
        'Versehen; das steht im Log', () async {
      final scene = Scene();
      final mira = await scene.mira();
      await scene.slots.use(mira, 1);

      final after = await scene.slots.restore(mira, 1);

      expect(after.slotsRemaining(1), 4);
      final event = (await scene.events()).last as SpellSlotEvent;
      expect(event.change, SlotChange.restored);
      expect(event.remaining, 4);
    });

    test('Zurückgeben geht nur, wenn bei diesem Grad etwas verbraucht '
        'ist', () async {
      final scene = Scene();
      final mira = await scene.mira();

      expect(() => scene.slots.restore(mira, 1), throwsStateError);
    });

    test('Paktmagie wird getrennt verbraucht und zurückgegeben', () async {
      final scene = Scene();
      final mira = await scene.mira();

      var after = await scene.slots.usePact(mira);
      expect(after.pactSlotsRemaining, 1);
      expect(after.slotsRemaining(3), 2);

      after = await scene.slots.restorePact(mira);
      expect(after.pactSlotsRemaining, 2);

      final events = (await scene.events()).cast<SpellSlotEvent>();
      expect(events.map((e) => (e.pact, e.level, e.change, e.remaining)), [
        (true, 3, SlotChange.used, 1),
        (true, 3, SlotChange.restored, 2),
      ]);
      expect(() => scene.slots.restorePact(mira), throwsStateError);
    });

    test('Ohne übrige Paktmagie wird nichts verbraucht', () async {
      final scene = Scene();
      final mira = await scene.mira();
      await scene.slots.usePact(mira);
      await scene.slots.usePact(mira);

      expect(() => scene.slots.usePact(mira), throwsStateError);
    });

    test('Auch im laufenden Kampf lassen sich Plätze verbrauchen; Schaden '
        'aus dem Kampf geht dabei nicht verloren', () async {
      final scene = Scene(faces: [12]);
      final mira = await scene.mira();
      final combatant = scene.encounter.addCharacter(mira);
      await scene.encounter.rollInitiative();
      await scene.encounter.damage(combatant, 10);

      await scene.slots.use(mira, 1);
      await scene.encounter.flush();

      final stored = await scene.stored(mira);
      expect(stored.slotsRemaining(1), 3);
      expect(stored.hp, 18);
    });

    test('Spätere Änderungen im Kampf überschreiben den Verbrauch '
        'nicht', () async {
      final scene = Scene();
      final mira = await scene.mira();
      final combatant = scene.encounter.addCharacter(mira);

      await scene.slots.use(mira, 1);
      await scene.encounter.damage(combatant, 5);
      await scene.encounter.flush();

      final stored = await scene.stored(mira);
      expect(stored.slotsRemaining(1), 3);
      expect(stored.hp, 23);
    });
  });
}
