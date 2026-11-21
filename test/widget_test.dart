import 'package:dmployee/characters/character.dart';
import 'package:dmployee/characters/character_repository.dart';
import 'package:dmployee/combat/encounter.dart';
import 'package:dmployee/log/log_repository.dart';
import 'package:dmployee/main.dart';
import 'package:dmployee/ui/characters_screen.dart';
import 'package:dmployee/ui/combat_screen.dart';
import 'package:dmployee/ui/dice_screen.dart';
import 'package:dmployee/ui/log_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('Die App startet mit dem Würfler-Bildschirm', (tester) async {
    await tester.pumpWidget(DMployeeApp(log: InMemoryLogRepository()));

    expect(find.byType(DiceScreen), findsOneWidget);
  });

  testWidgets('Über die untere Leiste wechselt man zum Log und sieht dort '
      'den gerade gemachten Wurf', (tester) async {
    await tester.pumpWidget(DMployeeApp(log: InMemoryLogRepository()));

    await tester.tap(find.byKey(const Key('roll-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-log')));
    await tester.pumpAndSettle();

    expect(find.byType(LogScreen), findsOneWidget);
    expect(find.byKey(const Key('log-line-1')), findsOneWidget);
  });

  testWidgets('Die untere Leiste führt zum Kampf-Bildschirm', (tester) async {
    await tester.pumpWidget(DMployeeApp(log: InMemoryLogRepository()));

    await tester.tap(find.byKey(const Key('nav-combat')));
    await tester.pumpAndSettle();

    expect(find.byType(CombatScreen), findsOneWidget);
    expect(find.text('Noch keine Kämpfer'), findsOneWidget);
  });

  testWidgets('Ein beim Start geladener Kampf erscheint auf dem '
      'Kampf-Bildschirm', (tester) async {
    final log = InMemoryLogRepository();
    final encounter = Encounter(log: log)
      ..add(name: 'Aria', armorClass: 16, maxHp: 20);
    await tester.pumpWidget(DMployeeApp(log: log, encounter: encounter));

    await tester.tap(find.byKey(const Key('nav-combat')));
    await tester.pumpAndSettle();

    expect(find.text('Aria'), findsOneWidget);
    expect(find.text('Noch keine Kämpfer'), findsNothing);
  });

  group('Navigation: Einschub von links', () {
    Future<void> openCharacters(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('open-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('drawer-characters')));
      await tester.pumpAndSettle();
    }

    testWidgets('Würfler, Kampf und Log haben oben links einen Knopf für '
        'das Menü', (tester) async {
      await tester.pumpWidget(DMployeeApp(log: InMemoryLogRepository()));

      for (final tab in ['nav-dice', 'nav-combat', 'nav-log']) {
        await tester.tap(find.byKey(Key(tab)));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('open-menu')), findsOneWidget);
      }
    });

    testWidgets('Über das Menü öffnet sich die Charakterliste; zurück geht '
        'es zum vorherigen Bereich', (tester) async {
      await tester.pumpWidget(DMployeeApp(log: InMemoryLogRepository()));

      await openCharacters(tester);
      expect(find.byType(CharactersScreen), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(CharactersScreen), findsNothing);
      expect(find.byType(DiceScreen), findsOneWidget);
    });

    testWidgets('Ein aus der Charakterliste in den Kampf geschickter '
        'Charakter steht danach auf dem Kampf-Bildschirm', (tester) async {
      final characters = InMemoryCharacterRepository();
      await characters.save(
        Character(name: 'Borin', maxHp: 24, armorClass: 18),
      );
      await tester.pumpWidget(
        DMployeeApp(log: InMemoryLogRepository(), characters: characters),
      );

      await openCharacters(tester);
      await tester.tap(find.byKey(const Key('to-combat-0')));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-combat')));
      await tester.pumpAndSettle();

      expect(find.text('Borin'), findsOneWidget);
    });
  });
}
