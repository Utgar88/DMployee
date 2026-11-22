import 'package:dmployee/characters/character.dart';
import 'package:dmployee/characters/character_repository.dart';
import 'package:dmployee/characters/exhaustion.dart';
import 'package:dmployee/characters/rest.dart';
import 'package:dmployee/combat/attack.dart';
import 'package:dmployee/combat/encounter.dart';
import 'package:dmployee/dice/dice_expression.dart';
import 'package:dmployee/dice/dice_roller.dart';
import 'package:dmployee/log/log_event.dart';
import 'package:dmployee/log/log_repository.dart';
import 'package:dmployee/rules/ruleset.dart';
import 'package:dmployee/settings/app_settings.dart';
import 'package:dmployee/ui/characters_screen.dart';
import 'package:dmployee/ui/combat_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fixed_random.dart';

final longsword = Attack(
  name: 'Langschwert',
  attackBonus: 5,
  damage: DiceExpression.parse('1d8+3'),
  damageType: 'Hieb',
);

/// Characters, combat and exhaustion under [ruleset]. Aria: 40 TP.
class Scene {
  Scene({Ruleset ruleset = Ruleset.dnd2014, List<int> faces = const []}) {
    settings.setRuleset(ruleset);
    encounter = Encounter(
      log: log,
      characters: characters,
      settings: settings,
      roller: DiceRoller(FixedRandom(faces)),
    );
    exhaustion = ExhaustionService(
      characters: characters,
      log: log,
      settings: settings,
      encounter: encounter,
    );
  }

  final log = InMemoryLogRepository();
  final characters = InMemoryCharacterRepository();
  final settings = AppSettings();
  late final Encounter encounter;
  late final ExhaustionService exhaustion;

  Future<Character> aria({int exhaustion = 0, int? hp}) => characters.save(
    Character(
      name: 'Aria',
      maxHp: 40,
      armorClass: 16,
      hp: hp,
      attacks: [longsword],
    )..exhaustion = exhaustion,
  );

  Future<void> pumpList(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CharactersScreen(
          characters: characters,
          encounter: encounter,
          exhaustion: exhaustion,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpCombat(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CombatScreen(encounter: encounter, characters: characters),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<Character> stored(Character character) async =>
      (await characters.byId(character.id!))!;

  Future<List<LogEvent>> events() async => [
    for (final entry in (await log.entries()).reversed) entry.event,
  ];
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
  group('Erschöpfung in der Charakterliste', () {
    testWidgets('Ein erschöpfter Charakter zeigt seine Stufe, ein nicht '
        'erschöpfter nicht; beide haben einen Knopf', (tester) async {
      final scene = Scene();
      await scene.aria(exhaustion: 2);
      await scene.characters.save(
        Character(name: 'Borin', maxHp: 24, armorClass: 16),
      );
      await scene.pumpList(tester);

      expect(textOf(tester, 'character-exhaustion-0'), 'Erschöpfung: Stufe 2');
      expect(find.byKey(const Key('character-exhaustion-1')), findsNothing);
      expect(find.byKey(const Key('exhaustion-0')), findsOneWidget);
      expect(find.byKey(const Key('exhaustion-1')), findsOneWidget);
    });

    testWidgets('Im Fenster lässt sich die Stufe erhöhen und senken; '
        'Folgen, Speicher, Log und Liste ändern sich', (tester) async {
      final scene = Scene();
      final aria = await scene.aria();
      await scene.pumpList(tester);

      await tapKey(tester, 'exhaustion-0');
      expect(textOf(tester, 'exhaustion-level'), 'Stufe 0');
      expect(find.text('Keine Folgen'), findsOneWidget);

      await tapKey(tester, 'exhaustion-up');
      await tapKey(tester, 'exhaustion-up');
      expect(textOf(tester, 'exhaustion-level'), 'Stufe 2');
      expect(find.text('Bewegungsrate halbiert'), findsOneWidget);
      expect((await scene.stored(aria)).exhaustion, 2);

      await tapKey(tester, 'exhaustion-down');
      await tapKey(tester, 'exhaustion-close');

      expect((await scene.stored(aria)).exhaustion, 1);
      expect(await scene.events(), hasLength(3));
      expect(textOf(tester, 'character-exhaustion-0'), 'Erschöpfung: Stufe 1');
    });

    testWidgets('Die Knöpfe bleiben beim Ändern der Stufe an ihrem Platz', (
      tester,
    ) async {
      final scene = Scene();
      await scene.aria();
      await scene.pumpList(tester);
      await tapKey(tester, 'exhaustion-0');
      final up = tester.getCenter(find.byKey(const Key('exhaustion-up')));

      for (var level = 1; level <= 5; level++) {
        await tapKey(tester, 'exhaustion-up');
        expect(tester.getCenter(find.byKey(const Key('exhaustion-up'))), up);
      }
    });

    testWidgets('Erschöpfung hat ein anderes Symbol als die Rast', (
      tester,
    ) async {
      final scene = Scene();
      await scene.aria();
      await tester.pumpWidget(
        MaterialApp(
          home: CharactersScreen(
            characters: scene.characters,
            encounter: scene.encounter,
            exhaustion: scene.exhaustion,
            rests: RestService(
              characters: scene.characters,
              log: scene.log,
              settings: scene.settings,
              encounter: scene.encounter,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      IconData iconOf(String key) => tester
          .widget<Icon>(
            find.descendant(
              of: find.byKey(Key(key)),
              matching: find.byType(Icon),
            ),
          )
          .icon!;
      expect(iconOf('exhaustion-0'), isNot(iconOf('rest')));
    });

    testWidgets('Bei Stufe 0 ist "senken" gesperrt', (tester) async {
      final scene = Scene();
      await scene.aria();
      await scene.pumpList(tester);

      await tapKey(tester, 'exhaustion-0');

      expect(enabled(tester, 'exhaustion-down'), isFalse);
      expect(enabled(tester, 'exhaustion-up'), isTrue);
    });

    testWidgets('Stufe 6 muss bestätigt werden; abgebrochen bleibt es bei 5', (
      tester,
    ) async {
      final scene = Scene();
      final aria = await scene.aria(exhaustion: 5);
      await scene.pumpList(tester);
      await tapKey(tester, 'exhaustion-0');

      await tapKey(tester, 'exhaustion-up');
      expect(find.textContaining('stirbt'), findsOneWidget);
      await tapKey(tester, 'exhaustion-death-cancel');
      expect((await scene.stored(aria)).exhaustion, 5);

      await tapKey(tester, 'exhaustion-up');
      await tapKey(tester, 'exhaustion-death-confirm');
      expect((await scene.stored(aria)).isDead, isTrue);
      expect(enabled(tester, 'exhaustion-up'), isFalse);
    });

    testWidgets('Die Folgen richten sich nach dem Regelwerk (2024)', (
      tester,
    ) async {
      final scene = Scene(ruleset: Ruleset.dnd2024);
      await scene.aria(exhaustion: 1);
      await scene.pumpList(tester);

      await tapKey(tester, 'exhaustion-0');

      expect(find.text('−2 auf alle W20-Würfe'), findsOneWidget);
      expect(find.text('Regelwerk: D&D 5e (2024)'), findsOneWidget);
    });

    testWidgets('2014: Die TP in der Liste zeigen das halbierte Maximum', (
      tester,
    ) async {
      final scene = Scene();
      await scene.aria(exhaustion: 4, hp: 20);
      await scene.pumpList(tester);

      expect(textOf(tester, 'character-stats-0'), startsWith('TP 20/20 '));
    });
  });

  group('Erschöpfung im Kampf', () {
    testWidgets('Alle Kämpfer haben einen Knopf "Erschöpfung", auch Monster; '
        'die Stufe steht als Abzeichen dabei', (tester) async {
      final scene = Scene();
      scene.encounter.addCharacter(await scene.aria(exhaustion: 2));
      scene.encounter.add(name: 'Goblin', armorClass: 13, maxHp: 7);
      await scene.pumpCombat(tester);

      expect(find.byKey(const Key('exhaustion-0')), findsOneWidget);
      expect(find.byKey(const Key('exhaustion-1')), findsOneWidget);
      expect(find.text('Erschöpft 2'), findsOneWidget);
    });

    testWidgets('Erhöhen im Kampf ändert Kämpfer, Charakter und Log; 2014 '
        'zeigen die TP ab Stufe 4 das halbierte Maximum', (tester) async {
      final scene = Scene();
      final aria = await scene.aria(exhaustion: 3);
      final combatant = scene.encounter.addCharacter(aria);
      await scene.pumpCombat(tester);

      await tapKey(tester, 'exhaustion-0');
      await tapKey(tester, 'exhaustion-up');
      await tapKey(tester, 'exhaustion-close');

      expect(combatant.exhaustion, 4);
      expect(find.text('Erschöpft 4'), findsOneWidget);
      expect(textOf(tester, 'stats-0'), contains('TP 20/20'));
      await scene.encounter.flush();
      expect((await scene.stored(aria)).exhaustion, 4);
      expect((await scene.events()).single, isA<ExhaustionEvent>());
    });

    testWidgets('Wiederbeleben ist bei Stufe 6 gesperrt, mit Hinweis', (
      tester,
    ) async {
      final scene = Scene();
      final combatant = scene.encounter.addCharacter(await scene.aria());
      await scene.encounter.setExhaustion(combatant, 6);
      await scene.pumpCombat(tester);

      await tapKey(tester, 'revive-0');

      expect(
        find.textContaining('Erst die Erschöpfung senken'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('revive-confirm')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('Das Angriffsfenster nennt die Folgen der Erschöpfung des '
        'Angreifers', (tester) async {
      final scene = Scene();
      scene.encounter.addCharacter(await scene.aria(exhaustion: 3));
      scene.encounter.add(name: 'Goblin', armorClass: 13, maxHp: 7);
      await scene.pumpCombat(tester);

      await tapKey(tester, 'attack-0-0');

      expect(
        find.text('Aria ist erschöpft (Stufe 3): Nachteil auf den Angriff'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('attack-conditions')), findsOneWidget);
    });

    testWidgets('2024: Das Angriffsfenster nennt den Abzug', (tester) async {
      final scene = Scene(ruleset: Ruleset.dnd2024);
      scene.encounter.addCharacter(await scene.aria(exhaustion: 2));
      scene.encounter.add(name: 'Goblin', armorClass: 13, maxHp: 7);
      await scene.pumpCombat(tester);

      await tapKey(tester, 'attack-0-0');

      expect(
        find.text('Aria ist erschöpft (Stufe 2): −4 auf den Angriffswurf'),
        findsOneWidget,
      );
    });
  });
}
