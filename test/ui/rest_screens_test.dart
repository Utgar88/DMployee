import 'package:dmployee/characters/ability.dart';
import 'package:dmployee/characters/character.dart';
import 'package:dmployee/characters/character_repository.dart';
import 'package:dmployee/characters/rest.dart';
import 'package:dmployee/combat/encounter.dart';
import 'package:dmployee/dice/dice_roller.dart';
import 'package:dmployee/log/log_event.dart';
import 'package:dmployee/log/log_repository.dart';
import 'package:dmployee/rules/ruleset.dart';
import 'package:dmployee/settings/app_settings.dart';
import 'package:dmployee/ui/characters_screen.dart';
import 'package:dmployee/ui/rest_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fixed_random.dart';

/// The character list with rests; dice show [faces]. Aria: Stufe 5,
/// KON 14 (+2), 44 TP, W10. Borin: Stufe 4, KON 10, 24 TP, W8.
class Scene {
  Scene({List<int> faces = const [], Ruleset ruleset = Ruleset.dnd2014}) {
    settings.setRuleset(ruleset);
    rests = RestService(
      characters: characters,
      log: log,
      settings: settings,
      encounter: encounter,
      roller: DiceRoller(FixedRandom(faces)),
    );
  }

  final log = InMemoryLogRepository();
  final characters = InMemoryCharacterRepository();
  final settings = AppSettings();
  late final encounter = Encounter(log: log, characters: characters);
  late final RestService rests;

  Future<Character> aria({
    int hp = 44,
    int hitDiceSpent = 0,
    int exhaustion = 0,
  }) => characters.save(
    Character(
        name: 'Aria',
        level: 5,
        abilityScores: {Ability.constitution: 14},
        maxHp: 44,
        armorClass: 18,
        hitDie: 10,
        hp: hp,
      )
      ..hitDiceSpent = hitDiceSpent
      ..exhaustion = exhaustion,
  );

  Future<Character> borin({int hp = 24, bool dead = false}) => characters.save(
    Character(name: 'Borin', level: 4, maxHp: 24, armorClass: 16, hp: hp)
      ..isDead = dead,
  );

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CharactersScreen(
          characters: characters,
          encounter: encounter,
          rests: rests,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<List<LogEvent>> events() async => [
    for (final entry in (await log.entries()).reversed) entry.event,
  ];

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

bool checked(WidgetTester tester, String key) =>
    tester.widget<CheckboxListTile>(find.byKey(Key(key))).value!;

bool enabled(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(find.byKey(Key(key))).onPressed != null;

Future<void> chooseLongRest(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('rest-kind')),
      matching: find.text('Lange Rast'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Rasten: Auswahl', () {
    testWidgets('Ohne Rast-Logik gibt es keinen Knopf "Rasten"', (
      tester,
    ) async {
      final scene = Scene();
      await scene.aria();
      await tester.pumpWidget(
        MaterialApp(
          home: CharactersScreen(
            characters: scene.characters,
            encounter: scene.encounter,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rest')), findsNothing);
    });

    testWidgets('Der Knopf "Rasten" öffnet die Auswahl: kurze Rast, alle '
        'Charaktere ausgewählt, das Regelwerk steht dabei', (tester) async {
      final scene = Scene();
      await scene.aria();
      await scene.borin();
      await scene.pump(tester);

      await tapKey(tester, 'rest');

      expect(find.byType(RestDialog), findsOneWidget);
      expect(
        tester
            .widget<SegmentedButton<RestKind>>(
              find.byKey(const Key('rest-kind')),
            )
            .selected,
        {RestKind.short},
      );
      expect(checked(tester, 'rest-character-0'), isTrue);
      expect(checked(tester, 'rest-character-1'), isTrue);
      expect(find.text('Regeln: D&D 5e (2014)'), findsOneWidget);
    });

    testWidgets('Charaktere ohne Nutzen von der Rast zeigen den Grund', (
      tester,
    ) async {
      final scene = Scene();
      await scene.aria(hp: 0);
      await scene.borin(dead: true, hp: 0);
      await scene.pump(tester);

      await tapKey(tester, 'rest');
      expect(textOf(tester, 'rest-blocker-0'), 'kein Nutzen: liegt im Sterben');
      expect(textOf(tester, 'rest-blocker-1'), 'kein Nutzen: tot');
    });

    testWidgets('Abbrechen ändert nichts und schreibt nichts in den Log', (
      tester,
    ) async {
      final scene = Scene();
      await scene.aria(hp: 12);
      await scene.pump(tester);

      await tapKey(tester, 'rest');
      await tapKey(tester, 'rest-cancel');

      expect(find.byType(RestDialog), findsNothing);
      expect(await scene.events(), isEmpty);
    });

    testWidgets('Ohne ausgewählte Charaktere lässt sich nicht rasten', (
      tester,
    ) async {
      final scene = Scene();
      await scene.aria(hp: 12);
      await scene.pump(tester);

      await tapKey(tester, 'rest');
      await tapKey(tester, 'rest-character-0');

      expect(enabled(tester, 'rest-confirm'), isFalse);
    });

    testWidgets('Während eines laufenden Kampfs erscheint eine Meldung statt '
        'der Auswahl', (tester) async {
      final scene = Scene(faces: [10]);
      final aria = await scene.aria(hp: 12);
      scene.encounter.addCharacter(aria);
      await scene.encounter.rollInitiative();
      await scene.pump(tester);

      await tapKey(tester, 'rest');

      expect(find.byType(RestDialog), findsNothing);
      expect(
        find.text('Während eines Kampfs ist keine Rast möglich.'),
        findsOneWidget,
      );
    });
  });

  group('Rasten: lange Rast', () {
    testWidgets('Die lange Rast gibt den ausgewählten Charakteren volle TP; '
        'die Liste zeigt es sofort', (tester) async {
      final scene = Scene();
      await scene.aria(hp: 12);
      await scene.borin(hp: 3);
      await scene.pump(tester);

      await tapKey(tester, 'rest');
      await chooseLongRest(tester);
      await tapKey(tester, 'rest-confirm');

      expect(textOf(tester, 'character-stats-0'), 'TP 44/44 · RK 18');
      expect(textOf(tester, 'character-stats-1'), 'TP 24/24 · RK 16');
      expect(find.text('Lange Rast beendet.'), findsOneWidget);
      expect(await scene.events(), hasLength(2));
    });

    testWidgets('Nicht ausgewählte Charaktere rasten nicht', (tester) async {
      final scene = Scene();
      final aria = await scene.aria(hp: 12);
      final borin = await scene.borin(hp: 3);
      await scene.pump(tester);

      await tapKey(tester, 'rest');
      await chooseLongRest(tester);
      await tapKey(tester, 'rest-character-1');
      await tapKey(tester, 'rest-confirm');

      expect((await scene.stored(aria)).hp, 44);
      expect((await scene.stored(borin)).hp, 3);
    });
  });

  group('Rasten: kurze Rast', () {
    Future<void> startShortRest(WidgetTester tester) async {
      await tapKey(tester, 'rest');
      await tapKey(tester, 'rest-confirm');
    }

    testWidgets('Die kurze Rast öffnet die Seite für Trefferwürfel mit TP und '
        'übrigen Trefferwürfeln je Charakter', (tester) async {
      final scene = Scene();
      await scene.aria(hp: 12, hitDiceSpent: 1);
      await scene.pump(tester);

      await startShortRest(tester);

      expect(find.byType(ShortRestScreen), findsOneWidget);
      expect(
        textOf(tester, 'short-rest-stats-0'),
        'TP 12/44 · Trefferwürfel 4/5 (W10)',
      );
      expect(((await scene.events()).single as RestEvent).kind, RestKind.short);
    });

    testWidgets('Ein Tipp auf "Trefferwürfel" würfelt und heilt; Ergebnis, '
        'TP und Trefferwürfel werden angezeigt', (tester) async {
      final scene = Scene(faces: [5]);
      final aria = await scene.aria(hp: 12);
      await scene.pump(tester);
      await startShortRest(tester);

      await tapKey(tester, 'hit-die-0');

      expect(textOf(tester, 'hit-die-result-0'), '+7 TP');
      expect(
        textOf(tester, 'short-rest-stats-0'),
        'TP 19/44 · Trefferwürfel 4/5 (W10)',
      );
      expect((await scene.stored(aria)).hp, 19);
    });

    testWidgets('Ein am Tisch gewürfelter Wert wird übernommen', (
      tester,
    ) async {
      final scene = Scene();
      await scene.aria(hp: 12);
      await scene.pump(tester);
      await startShortRest(tester);

      await tester.enterText(find.byKey(const Key('hit-die-face-0')), '8');
      await tapKey(tester, 'hit-die-0');

      expect(textOf(tester, 'hit-die-result-0'), '+10 TP');
      final event = (await scene.events()).last as HitDieEvent;
      expect(event.roll.manual, isTrue);
    });

    testWidgets('Ein unmöglicher Wert wird mit einer Meldung abgelehnt', (
      tester,
    ) async {
      final scene = Scene();
      final aria = await scene.aria(hp: 12);
      await scene.pump(tester);
      await startShortRest(tester);

      await tester.enterText(find.byKey(const Key('hit-die-face-0')), '11');
      await tapKey(tester, 'hit-die-0');

      expect(find.text('Ein W10 zeigt 1 bis 10.'), findsOneWidget);
      expect((await scene.stored(aria)).hitDiceSpent, 0);
    });

    testWidgets('Mit vollen TP oder ohne übrige Trefferwürfel ist der Knopf '
        'gesperrt und der Grund steht dabei', (tester) async {
      final scene = Scene();
      await scene.aria(hp: 12, hitDiceSpent: 5);
      await scene.borin();
      await scene.pump(tester);
      await startShortRest(tester);

      expect(enabled(tester, 'hit-die-0'), isFalse);
      expect(textOf(tester, 'hit-die-result-0'), 'keine Trefferwürfel übrig');
      expect(enabled(tester, 'hit-die-1'), isFalse);
      expect(textOf(tester, 'hit-die-result-1'), 'TP voll');
    });

    testWidgets('Nach dem letzten Trefferwürfel stehen Ergebnis und Grund '
        'für die Sperre zusammen da', (tester) async {
      final scene = Scene(faces: [5]);
      await scene.aria(hp: 12, hitDiceSpent: 4);
      await scene.pump(tester);
      await startShortRest(tester);

      await tapKey(tester, 'hit-die-0');

      expect(enabled(tester, 'hit-die-0'), isFalse);
      expect(
        textOf(tester, 'hit-die-result-0'),
        '+7 TP · keine Trefferwürfel übrig',
      );
    });

    testWidgets('Füllt ein Trefferwürfel die TP auf, steht "TP voll" neben '
        'dem Ergebnis', (tester) async {
      final scene = Scene(faces: [10]);
      await scene.aria(hp: 40);
      await scene.pump(tester);
      await startShortRest(tester);

      await tapKey(tester, 'hit-die-0');

      expect(textOf(tester, 'hit-die-result-0'), '+4 TP · TP voll');
    });

    testWidgets('2024: mit 0 TP ist der Knopf gesperrt', (tester) async {
      final scene = Scene(ruleset: Ruleset.dnd2024);
      final aria = await scene.aria(hp: 0);
      await scene.characters.save(aria..isStable = true);
      await scene.pump(tester);
      await startShortRest(tester);

      expect(enabled(tester, 'hit-die-0'), isFalse);
      expect(textOf(tester, 'hit-die-result-0'), 'kein Nutzen: 0 TP');
    });

    testWidgets('"Fertig" führt zurück zur Liste, die die neuen TP zeigt', (
      tester,
    ) async {
      final scene = Scene(faces: [5]);
      await scene.aria(hp: 12);
      await scene.pump(tester);
      await startShortRest(tester);
      await tapKey(tester, 'hit-die-0');

      await tapKey(tester, 'short-rest-done');

      expect(find.byType(ShortRestScreen), findsNothing);
      expect(textOf(tester, 'character-stats-0'), 'TP 19/44 · RK 18');
    });
  });

  testWidgets('Die Liste zeigt die übrigen Trefferwürfel jedes Charakters', (
    tester,
  ) async {
    final scene = Scene();
    await scene.aria(hitDiceSpent: 2);
    await scene.pump(tester);

    expect(textOf(tester, 'character-hit-dice-0'), 'Trefferwürfel 3/5 (W10)');
  });

  group('Rasten bei Erschöpfung', () {
    testWidgets('2014: Auswahl und Trefferwürfel-Seite zeigen das halbierte '
        'Maximum; bei vollen halbierten TP heißt es "TP voll"', (tester) async {
      final scene = Scene();
      await scene.aria(hp: 22, hitDiceSpent: 1, exhaustion: 4);
      await scene.pump(tester);

      await tapKey(tester, 'rest');
      expect(find.text('TP 22/22'), findsOneWidget);

      await tapKey(tester, 'rest-confirm');
      expect(
        textOf(tester, 'short-rest-stats-0'),
        'TP 22/22 · Trefferwürfel 4/5 (W10)',
      );
      expect(find.text('TP voll'), findsOneWidget);
    });
  });
}
