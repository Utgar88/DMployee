import 'package:dmployee/characters/character.dart';
import 'package:dmployee/characters/character_repository.dart';
import 'package:dmployee/characters/spell_slots.dart';
import 'package:dmployee/combat/encounter.dart';
import 'package:dmployee/dice/dice_roller.dart';
import 'package:dmployee/log/log_event.dart';
import 'package:dmployee/log/log_repository.dart';
import 'package:dmployee/ui/characters_screen.dart';
import 'package:dmployee/ui/combat_screen.dart';
import 'package:dmployee/ui/spell_slots_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fixed_random.dart';

/// Mira: 4 slots of level 1, 2 of level 3, pact magic 2 slots of level 3.
/// Borin: no slots.
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

  Future<Character> borin() =>
      characters.save(Character(name: 'Borin', maxHp: 24, armorClass: 16));

  Future<void> pumpList(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CharactersScreen(
          characters: characters,
          encounter: encounter,
          spellSlots: slots,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpCombat(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CombatScreen(
          encounter: encounter,
          characters: characters,
          spellSlots: slots,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<Character> stored(Character character) async =>
      (await characters.byId(character.id!))!;
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

bool enabled(WidgetTester tester, String key) =>
    tester.widget<IconButton>(find.byKey(Key(key))).onPressed != null;

void main() {
  group('Zauberplätze in der Charakterliste', () {
    testWidgets('Ein Charakter mit Zauberplätzen zeigt eine Übersicht und '
        'einen Knopf; einer ohne nicht', (tester) async {
      final scene = Scene();
      await scene.borin();
      await scene.mira();
      await scene.pumpList(tester);

      expect(find.byKey(const Key('character-slots-0')), findsNothing);
      expect(find.byKey(const Key('slots-0')), findsNothing);
      expect(
        textOf(tester, 'character-slots-1'),
        'Zauberplätze: 1. Grad 4/4 · 3. Grad 2/2 · Pakt 2/2 (3. Grad)',
      );
      expect(find.byKey(const Key('slots-1')), findsOneWidget);
    });

    testWidgets('Das Fenster zeigt jeden Grad und die Paktmagie mit übrigen '
        'Plätzen', (tester) async {
      final scene = Scene();
      await scene.mira();
      await scene.pumpList(tester);

      await tapKey(tester, 'slots-0');

      expect(find.byType(SpellSlotsDialog), findsOneWidget);
      expect(find.text('Zauberplätze: Mira'), findsOneWidget);
      expect(textOf(tester, 'slot-count-1'), '4 von 4');
      expect(textOf(tester, 'slot-count-3'), '2 von 2');
      expect(find.byKey(const Key('slot-count-2')), findsNothing);
      expect(textOf(tester, 'pact-count'), '2 von 2 (3. Grad)');
    });

    testWidgets('Verbrauchen und Zurückgeben ändern die Anzeige, den '
        'gespeicherten Charakter und den Log', (tester) async {
      final scene = Scene();
      final mira = await scene.mira();
      await scene.pumpList(tester);
      await tapKey(tester, 'slots-0');

      await tapKey(tester, 'slot-use-1');
      await tapKey(tester, 'slot-use-1');
      expect(textOf(tester, 'slot-count-1'), '2 von 4');
      await tapKey(tester, 'slot-restore-1');
      expect(textOf(tester, 'slot-count-1'), '3 von 4');
      await tapKey(tester, 'pact-use');
      expect(textOf(tester, 'pact-count'), '1 von 2 (3. Grad)');

      final stored = await scene.stored(mira);
      expect(stored.slotsRemaining(1), 3);
      expect(stored.pactSlotsRemaining, 1);
      expect(
        (await scene.log.entries()).map((e) => e.event),
        everyElement(isA<SpellSlotEvent>()),
      );
      expect(await scene.log.entries(), hasLength(4));
    });

    testWidgets('Ohne übrige Plätze ist "verbrauchen" gesperrt, ohne '
        'verbrauchte "zurückgeben"', (tester) async {
      final scene = Scene();
      await scene.mira();
      await scene.pumpList(tester);
      await tapKey(tester, 'slots-0');

      expect(enabled(tester, 'slot-restore-3'), isFalse);
      await tapKey(tester, 'slot-use-3');
      await tapKey(tester, 'slot-use-3');
      expect(enabled(tester, 'slot-use-3'), isFalse);
      expect(enabled(tester, 'slot-restore-3'), isTrue);
      expect(enabled(tester, 'pact-restore'), isFalse);
    });

    testWidgets('Nach dem Schließen zeigt die Liste den neuen Stand', (
      tester,
    ) async {
      final scene = Scene();
      await scene.mira();
      await scene.pumpList(tester);
      await tapKey(tester, 'slots-0');
      await tapKey(tester, 'slot-use-3');

      await tapKey(tester, 'slots-close');

      expect(
        textOf(tester, 'character-slots-0'),
        'Zauberplätze: 1. Grad 4/4 · 3. Grad 1/2 · Pakt 2/2 (3. Grad)',
      );
    });
  });

  group('Zauberplätze im Kampf', () {
    testWidgets('Charaktere haben im Kampf einen Knopf "Zauberplätze", '
        'Monster nicht', (tester) async {
      final scene = Scene();
      scene.encounter.addCharacter(await scene.mira());
      scene.encounter.add(name: 'Goblin', armorClass: 13, maxHp: 7);
      await scene.pumpCombat(tester);

      expect(find.byKey(const Key('slots-0')), findsOneWidget);
      expect(find.byKey(const Key('slots-1')), findsNothing);
    });

    testWidgets('Im laufenden Kampf lässt sich ein Platz verbrauchen', (
      tester,
    ) async {
      final scene = Scene(faces: [15, 3]);
      final mira = await scene.mira();
      scene.encounter.addCharacter(mira);
      scene.encounter.add(name: 'Goblin', armorClass: 13, maxHp: 7);
      await scene.encounter.rollInitiative();
      await scene.pumpCombat(tester);

      await tapKey(tester, 'slots-0');
      await tapKey(tester, 'slot-use-3');
      await tapKey(tester, 'slots-close');

      expect((await scene.stored(mira)).slotsRemaining(3), 1);
      expect(scene.encounter.isRunning, isTrue);
    });

    testWidgets('Ein Charakter ohne Zauberplätze bekommt einen Hinweis', (
      tester,
    ) async {
      final scene = Scene();
      scene.encounter.addCharacter(await scene.borin());
      await scene.pumpCombat(tester);

      await tapKey(tester, 'slots-0');

      expect(
        find.text(
          'Keine Zauberplätze eingetragen. Sie stehen im Charakterbogen.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Ohne Zauberplatz-Logik gibt es keinen Knopf', (tester) async {
      final scene = Scene();
      scene.encounter.addCharacter(await scene.mira());
      await tester.pumpWidget(
        MaterialApp(
          home: CombatScreen(
            encounter: scene.encounter,
            characters: scene.characters,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('slots-0')), findsNothing);
    });
  });
}
