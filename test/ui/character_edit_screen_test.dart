import 'package:dmployee/characters/ability.dart';
import 'package:dmployee/characters/character.dart';
import 'package:dmployee/characters/character_repository.dart';
import 'package:dmployee/combat/attack.dart';
import 'package:dmployee/combat/encounter.dart';
import 'package:dmployee/dice/dice_expression.dart';
import 'package:dmployee/log/log_repository.dart';
import 'package:dmployee/ui/character_edit_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final longsword = Attack(
  name: 'Langschwert',
  attackBonus: 6,
  damage: DiceExpression.parse('1d8+3'),
  damageType: 'Hieb',
);

class Scene {
  final characters = InMemoryCharacterRepository();
  late final encounter = Encounter(
    log: InMemoryLogRepository(),
    characters: characters,
  );

  /// What the screen returned when it closed.
  Character? result;
  bool closed = false;

  Future<Character> saveAria() => characters.save(
    Character(
      name: 'Aria',
      player: 'Dirk',
      characterClass: 'Kämpferin',
      level: 5,
      abilityScores: {Ability.strength: 16, Ability.dexterity: 14},
      maxHp: 44,
      armorClass: 18,
      saveProficiencies: {Ability.strength},
      attacks: [longsword],
    ),
  );

  /// Opens the sheet for [character], or an empty one, from a start page,
  /// so closing it can be observed.
  Future<void> open(WidgetTester tester, [Character? character]) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            key: const Key('open'),
            onPressed: () async {
              result = await Navigator.push<Character>(
                context,
                MaterialPageRoute(
                  builder: (_) => CharacterEditScreen(
                    characters: characters,
                    encounter: encounter,
                    character: character,
                  ),
                ),
              );
              closed = true;
            },
            child: const Text('öffnen'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> type(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await tester.pumpAndSettle();
}

String textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

String fieldText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

/// Fills in the required fields for Borin.
Future<void> fillBorin(WidgetTester tester) async {
  await type(tester, 'character-name', 'Borin');
  await type(tester, 'character-hp', '12');
  await type(tester, 'character-ac', '16');
}

void main() {
  group('Charakterbogen: neuer Charakter', () {
    testWidgets('Ein neuer Charakter startet mit Stufe 1 und allen '
        'Attributen auf 10', (tester) async {
      await Scene().open(tester);

      expect(find.text('Neuer Charakter'), findsOneWidget);
      expect(fieldText(tester, 'character-level'), '1');
      for (final ability in Ability.values) {
        expect(fieldText(tester, 'ability-${ability.name}'), '10');
      }
    });

    testWidgets('Ein ausgefüllter Charakter wird gespeichert und der Bogen '
        'schließt sich', (tester) async {
      final scene = Scene();
      await scene.open(tester);

      await fillBorin(tester);
      await type(tester, 'character-player', 'Anna');
      await type(tester, 'character-class', 'Kleriker');
      await type(tester, 'character-level', '3');
      await type(tester, 'ability-wisdom', '16');
      await tapKey(tester, 'save-wisdom');
      await tapKey(tester, 'character-save');

      final borin = (await scene.characters.all()).single;
      expect(borin.name, 'Borin');
      expect(borin.player, 'Anna');
      expect(borin.classAndLevel, 'Kleriker 3');
      expect(borin.score(Ability.wisdom), 16);
      expect(borin.maxHp, 12);
      expect(borin.hp, 12);
      expect(borin.armorClass, 16);
      expect(borin.saveProficiencies, {Ability.wisdom});
      expect(scene.closed, isTrue);
      expect(scene.result?.id, borin.id);
    });

    testWidgets('Modifikatoren, Übungsbonus, Initiative und Rettungswürfe '
        'werden beim Tippen berechnet', (tester) async {
      await Scene().open(tester);

      await type(tester, 'character-level', '5');
      await type(tester, 'ability-strength', '16');
      await type(tester, 'ability-dexterity', '8');
      await tapKey(tester, 'save-strength');

      expect(textOf(tester, 'modifier-strength'), '+3');
      expect(textOf(tester, 'modifier-dexterity'), '-1');
      expect(textOf(tester, 'derived'), 'Übungsbonus +3 · Initiative -1');
      expect(textOf(tester, 'save-bonus-strength'), '+6');
      expect(textOf(tester, 'save-bonus-dexterity'), '-1');
    });

    testWidgets('Ohne Name, TP oder RK wird nichts gespeichert und eine '
        'Meldung erscheint', (tester) async {
      final scene = Scene();
      await scene.open(tester);

      await type(tester, 'character-hp', '12');
      await type(tester, 'character-ac', '16');
      await tapKey(tester, 'character-save');

      expect(find.byKey(const Key('form-error')), findsOneWidget);
      expect(await scene.characters.all(), isEmpty);
      expect(scene.closed, isFalse);
    });

    testWidgets('Eine Stufe über 20 oder ein Attribut über 30 wird mit einer '
        'Meldung abgelehnt', (tester) async {
      final scene = Scene();
      await scene.open(tester);
      await fillBorin(tester);

      await type(tester, 'character-level', '21');
      await tapKey(tester, 'character-save');
      expect(find.byKey(const Key('form-error')), findsOneWidget);

      await type(tester, 'character-level', '3');
      await type(tester, 'ability-charisma', '31');
      await tapKey(tester, 'character-save');
      expect(find.byKey(const Key('form-error')), findsOneWidget);
      expect(await scene.characters.all(), isEmpty);
    });

    testWidgets('Angriffe lassen sich hinzufügen und wieder entfernen', (
      tester,
    ) async {
      final scene = Scene();
      await scene.open(tester);
      await fillBorin(tester);

      await tapKey(tester, 'character-add-attack');
      await type(tester, 'attack-name', 'Streitkolben');
      await type(tester, 'attack-bonus', '4');
      await type(tester, 'attack-damage', '1d6+2');
      await type(tester, 'attack-type', 'Wucht');
      await tapKey(tester, 'attack-save');
      await tapKey(tester, 'character-add-attack');
      await type(tester, 'attack-name', 'Armbrust');
      await type(tester, 'attack-damage', '1d8');
      await tapKey(tester, 'attack-save');
      expect(find.text('Streitkolben +4, 1d6+2 Wucht'), findsOneWidget);

      await tapKey(tester, 'character-remove-attack-1');
      await tapKey(tester, 'character-save');

      final borin = (await scene.characters.all()).single;
      expect(borin.attacks.map((a) => a.name), ['Streitkolben']);
    });

    testWidgets('Ein neuer Charakter hat keinen Knopf zum Löschen', (
      tester,
    ) async {
      await Scene().open(tester);

      expect(find.byKey(const Key('character-delete')), findsNothing);
    });
  });

  group('Charakterbogen: vorhandener Charakter', () {
    testWidgets('Der Bogen zeigt die gespeicherten Werte', (tester) async {
      final scene = Scene();
      await scene.open(tester, await scene.saveAria());

      expect(find.text('Aria'), findsWidgets);
      expect(fieldText(tester, 'character-name'), 'Aria');
      expect(fieldText(tester, 'character-player'), 'Dirk');
      expect(fieldText(tester, 'character-class'), 'Kämpferin');
      expect(fieldText(tester, 'character-level'), '5');
      expect(fieldText(tester, 'ability-strength'), '16');
      expect(fieldText(tester, 'character-hp'), '44');
      expect(fieldText(tester, 'character-ac'), '18');
      expect(textOf(tester, 'save-bonus-strength'), '+6');
      expect(find.text(longsword.summary), findsOneWidget);
    });

    testWidgets('Änderungen ersetzen den gespeicherten Charakter und '
        'behalten seinen Zustand', (tester) async {
      final scene = Scene();
      final aria = await scene.saveAria();
      await scene.characters.save(aria..hp = 30);
      await scene.open(tester, aria);

      await type(tester, 'character-ac', '19');
      await tapKey(tester, 'character-save');

      final stored = (await scene.characters.all()).single;
      expect(stored.id, aria.id);
      expect(stored.armorClass, 19);
      expect(stored.hp, 30);
    });

    testWidgets('Ist der Charakter im Kampf, gelten die Änderungen dort '
        'sofort', (tester) async {
      final scene = Scene();
      final aria = await scene.saveAria();
      final combatant = scene.encounter.addCharacter(aria);
      await scene.open(tester, aria);

      await type(tester, 'character-ac', '19');
      await tapKey(tester, 'character-save');

      expect(combatant.armorClass, 19);
    });

    testWidgets('Löschen fragt nach und entfernt den Charakter; im Kampf '
        'bleibt der Kämpfer ohne Verknüpfung', (tester) async {
      final scene = Scene();
      final aria = await scene.saveAria();
      final combatant = scene.encounter.addCharacter(aria);
      await scene.open(tester, aria);

      await tapKey(tester, 'character-delete');
      expect(find.byKey(const Key('confirm-delete')), findsOneWidget);
      await tapKey(tester, 'confirm-delete');

      expect(await scene.characters.all(), isEmpty);
      expect(combatant.characterId, isNull);
      expect(scene.closed, isTrue);
    });

    testWidgets('Löschen lässt sich abbrechen', (tester) async {
      final scene = Scene();
      await scene.open(tester, await scene.saveAria());

      await tapKey(tester, 'character-delete');
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      expect(await scene.characters.all(), hasLength(1));
      expect(scene.closed, isFalse);
    });
  });

  group('Charakterbogen: Trefferwürfel', () {
    testWidgets('Ein neuer Charakter hat W8 als Trefferwürfel; die Auswahl '
        'bietet W6 bis W12', (tester) async {
      await Scene().open(tester);

      final picker = find.byKey(const Key('character-hit-die'));
      await tester.ensureVisible(picker);
      expect(tester.widget<SegmentedButton<int>>(picker).selected, {8});
      for (final label in ['W6', 'W8', 'W10', 'W12']) {
        expect(
          find.descendant(of: picker, matching: find.text(label)),
          findsOneWidget,
        );
      }
    });

    testWidgets('Der gewählte Trefferwürfel wird gespeichert', (tester) async {
      final scene = Scene();
      await scene.open(tester);

      await fillBorin(tester);
      await tester.ensureVisible(find.text('W10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('W10'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'character-save');

      expect((await scene.characters.all()).single.hitDie, 10);
    });

    testWidgets('Ein vorhandener Charakter zeigt seinen Trefferwürfel und '
        'wie viele Trefferwürfel übrig sind; Ändern behält die ausgegebenen', (
      tester,
    ) async {
      final scene = Scene();
      final aria = await scene.characters.save(
        (await scene.saveAria()).withValues(hitDie: 10)..hitDiceSpent = 2,
      );
      await scene.open(tester, aria);

      await tester.ensureVisible(find.byKey(const Key('hit-dice-left')));
      expect(
        tester
            .widget<SegmentedButton<int>>(
              find.byKey(const Key('character-hit-die')),
            )
            .selected,
        {10},
      );
      expect(textOf(tester, 'hit-dice-left'), 'Trefferwürfel übrig: 3 von 5');

      await tester.ensureVisible(find.text('W12'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('W12'));
      await tester.pumpAndSettle();
      await tapKey(tester, 'character-save');

      final saved = (await scene.characters.byId(aria.id!))!;
      expect(saved.hitDie, 12);
      expect(saved.hitDiceSpent, 2);
    });

    testWidgets('Ein neuer Charakter zeigt keine übrigen Trefferwürfel', (
      tester,
    ) async {
      await Scene().open(tester);

      expect(find.byKey(const Key('hit-dice-left')), findsNothing);
    });
  });

  group('Charakterbogen: Zauberplätze', () {
    testWidgets('Ein neuer Charakter hat leere Felder für die Grade 1 bis 9 '
        'und die Paktmagie', (tester) async {
      await Scene().open(tester);

      for (var level = 1; level <= 9; level++) {
        expect(fieldText(tester, 'slots-$level'), '');
      }
      expect(fieldText(tester, 'pact-slots'), '');
      expect(fieldText(tester, 'pact-level'), '');
    });

    testWidgets('Eingetragene Zauberplätze und Paktmagie werden gespeichert; '
        'leere Felder bedeuten keine Plätze', (tester) async {
      final scene = Scene();
      await scene.open(tester);

      await fillBorin(tester);
      await type(tester, 'slots-1', '4');
      await type(tester, 'slots-2', '3');
      await type(tester, 'pact-slots', '2');
      await type(tester, 'pact-level', '3');
      await tapKey(tester, 'character-save');

      final borin = (await scene.characters.all()).single;
      expect(borin.spellSlots, {1: 4, 2: 3});
      expect(borin.pactSlots, 2);
      expect(borin.pactSlotLevel, 3);
    });

    testWidgets('Ein vorhandener Charakter zeigt seine Zauberplätze; Ändern '
        'behält die verbrauchten', (tester) async {
      final scene = Scene();
      final aria = await scene.characters.save(
        (await scene.saveAria()).withValues(
          spellSlots: {1: 4, 3: 2},
          pactSlots: 1,
          pactSlotLevel: 2,
        )..slotsUsed[1] = 2,
      );
      await scene.open(tester, aria);

      expect(fieldText(tester, 'slots-1'), '4');
      expect(fieldText(tester, 'slots-2'), '');
      expect(fieldText(tester, 'slots-3'), '2');
      expect(fieldText(tester, 'pact-slots'), '1');
      expect(fieldText(tester, 'pact-level'), '2');

      await type(tester, 'slots-2', '3');
      await tapKey(tester, 'character-save');

      final saved = (await scene.characters.byId(aria.id!))!;
      expect(saved.spellSlots, {1: 4, 2: 3, 3: 2});
      expect(saved.slotsRemaining(1), 2);
    });

    testWidgets('Mehr als 9 Plätze je Grad werden mit einer Meldung '
        'abgelehnt', (tester) async {
      final scene = Scene();
      await scene.open(tester);

      await fillBorin(tester);
      await type(tester, 'slots-1', '10');
      await tapKey(tester, 'character-save');

      expect(
        find.text('Zauberplätze liegen zwischen 0 und 9 je Grad.'),
        findsOneWidget,
      );
      expect(await scene.characters.all(), isEmpty);
    });

    testWidgets('Paktmagie ohne Grad oder mit einem Grad über 5 wird mit '
        'einer Meldung abgelehnt', (tester) async {
      final scene = Scene();
      await scene.open(tester);

      await fillBorin(tester);
      await type(tester, 'pact-slots', '2');
      await tapKey(tester, 'character-save');
      expect(
        find.text('Paktmagie braucht einen Grad zwischen 1 und 5.'),
        findsOneWidget,
      );

      await type(tester, 'pact-level', '6');
      await tapKey(tester, 'character-save');
      expect(
        find.text('Paktmagie braucht einen Grad zwischen 1 und 5.'),
        findsOneWidget,
      );
      expect(await scene.characters.all(), isEmpty);
    });
  });
}
