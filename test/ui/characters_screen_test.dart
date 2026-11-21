import 'package:dmployee/characters/character.dart';
import 'package:dmployee/characters/character_repository.dart';
import 'package:dmployee/combat/encounter.dart';
import 'package:dmployee/log/log_repository.dart';
import 'package:dmployee/ui/character_edit_screen.dart';
import 'package:dmployee/ui/characters_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

class Scene {
  final characters = InMemoryCharacterRepository();
  late final encounter = Encounter(
    log: InMemoryLogRepository(),
    characters: characters,
  );

  Future<Character> save(String name, {String player = '', int hp = 44}) =>
      characters.save(
        Character(
          name: name,
          player: player,
          characterClass: 'Kämpferin',
          level: 5,
          maxHp: 44,
          armorClass: 18,
          hp: hp,
        ),
      );

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CharactersScreen(characters: characters, encounter: encounter),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

String textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  group('Charakterliste', () {
    testWidgets('Ohne Charaktere steht ein Hinweis da', (tester) async {
      await Scene().pump(tester);

      expect(find.text('Noch keine Charaktere'), findsOneWidget);
    });

    testWidgets('Jeder Charakter steht mit Klasse, Stufe, Spieler, TP und RK '
        'in der Liste, nach Namen sortiert', (tester) async {
      final scene = Scene();
      await scene.save('Borin');
      await scene.save('Aria', player: 'Dirk', hp: 30);
      await scene.pump(tester);

      expect(textOf(tester, 'character-name-0'), 'Aria');
      expect(textOf(tester, 'character-details-0'), 'Kämpferin 5 · Dirk');
      expect(textOf(tester, 'character-stats-0'), 'TP 30/44 · RK 18');
      expect(textOf(tester, 'character-name-1'), 'Borin');
      expect(textOf(tester, 'character-details-1'), 'Kämpferin 5');
    });

    testWidgets('Ein toter Charakter ist als tot markiert', (tester) async {
      final scene = Scene();
      final aria = await scene.save('Aria', hp: 0);
      await scene.characters.save(aria..isDead = true);
      await scene.pump(tester);

      expect(find.text('tot'), findsOneWidget);
    });

    testWidgets('Über den Knopf unten öffnet sich ein leerer Charakterbogen; '
        'der gespeicherte Charakter steht danach in der Liste', (tester) async {
      final scene = Scene();
      await scene.pump(tester);

      await tapKey(tester, 'new-character');
      expect(find.byType(CharacterEditScreen), findsOneWidget);
      await tester.enterText(find.byKey(const Key('character-name')), 'Cael');
      await tester.enterText(find.byKey(const Key('character-hp')), '9');
      await tester.enterText(find.byKey(const Key('character-ac')), '12');
      await tester.ensureVisible(find.byKey(const Key('character-save')));
      await tapKey(tester, 'character-save');

      expect(textOf(tester, 'character-name-0'), 'Cael');
    });

    testWidgets('Ein Tipp auf einen Charakter öffnet seinen Bogen; '
        'Änderungen stehen danach in der Liste', (tester) async {
      final scene = Scene();
      await scene.save('Aria');
      await scene.pump(tester);

      await tapKey(tester, 'character-0');
      await tester.enterText(find.byKey(const Key('character-ac')), '19');
      await tester.ensureVisible(find.byKey(const Key('character-save')));
      await tapKey(tester, 'character-save');

      expect(textOf(tester, 'character-stats-0'), 'TP 44/44 · RK 19');
    });

    testWidgets('"In den Kampf" übernimmt den Charakter in den Kampf; danach '
        'ist er als "im Kampf" markiert', (tester) async {
      final scene = Scene();
      final aria = await scene.save('Aria');
      await scene.pump(tester);

      await tapKey(tester, 'to-combat-0');

      expect(scene.encounter.hasCharacter(aria.id!), isTrue);
      expect(find.byKey(const Key('to-combat-0')), findsNothing);
      expect(find.byKey(const Key('in-combat-0')), findsOneWidget);
    });

    testWidgets('Ein im Kampf geänderter Zustand steht beim Zurückkehren in '
        'der Liste', (tester) async {
      final scene = Scene();
      await scene.save('Aria');
      await scene.pump(tester);
      await tapKey(tester, 'to-combat-0');

      await scene.encounter.damage(scene.encounter.combatants.single, 10);
      await scene.encounter.flush();
      await tapKey(tester, 'character-0');
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(textOf(tester, 'character-stats-0'), 'TP 34/44 · RK 18');
    });
  });
}
