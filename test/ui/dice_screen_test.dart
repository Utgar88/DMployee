import 'package:dmployee/dice/dice_roller.dart';
import 'package:dmployee/log/log_event.dart';
import 'package:dmployee/log/log_formatter.dart';
import 'package:dmployee/log/log_repository.dart';
import 'package:dmployee/ui/dice_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixed_random.dart';

/// Starts the dice screen with predetermined die faces.
Future<InMemoryLogRepository> pumpDiceScreen(
  WidgetTester tester,
  List<int> faces,
) async {
  final log = InMemoryLogRepository();
  await tester.pumpWidget(
    MaterialApp(
      home: DiceScreen(roller: DiceRoller(FixedRandom(faces)), log: log),
    ),
  );
  return log;
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  group('Würfler-Bildschirm: Aufbau', () {
    testWidgets('Alle gängigen Würfel stehen zur Auswahl', (tester) async {
      await pumpDiceScreen(tester, []);

      for (final sides in [4, 6, 8, 10, 12, 20, 100]) {
        expect(find.byKey(Key('die-$sides')), findsOneWidget);
      }
    });

    testWidgets('Beim Start ist 1d20 gewählt und noch kein Ergebnis zu sehen', (
      tester,
    ) async {
      await pumpDiceScreen(tester, []);

      expect(textOf(tester, 'expression'), '1d20');
      expect(find.byKey(const Key('result-total')), findsNothing);
    });
  });

  group('Würfler-Bildschirm: normaler Wurf', () {
    testWidgets('2d6+3 mit den Augen 4 und 5 zeigt die Summe 12 und die '
        'einzelnen Würfel', (tester) async {
      await pumpDiceScreen(tester, [4, 5]);

      await tapKey(tester, 'die-6');
      await tapKey(tester, 'count-plus');
      await tapKey(tester, 'modifier-plus');
      await tapKey(tester, 'modifier-plus');
      await tapKey(tester, 'modifier-plus');
      expect(textOf(tester, 'expression'), '2d6+3');

      await tapKey(tester, 'roll-button');

      expect(textOf(tester, 'result-total'), '12');
      expect(textOf(tester, 'result-detail'), '2d6+3: 4 + 5 + 3');
    });

    testWidgets('Die Würfelanzahl kann nicht unter 1 sinken', (tester) async {
      await pumpDiceScreen(tester, []);

      await tapKey(tester, 'count-minus');

      expect(textOf(tester, 'expression'), '1d20');
    });

    testWidgets('Ein negativer Modifier wird abgezogen', (tester) async {
      await pumpDiceScreen(tester, [5]);

      await tapKey(tester, 'die-8');
      await tapKey(tester, 'modifier-minus');
      await tapKey(tester, 'roll-button');

      expect(textOf(tester, 'result-total'), '4');
      expect(textOf(tester, 'result-detail'), '1d8-1: 5 - 1');
    });
  });

  group('Würfler-Bildschirm: d20 mit Vorteil und Nachteil', () {
    testWidgets('Vorteil und Nachteil gibt es nur bei einem einzelnen d20', (
      tester,
    ) async {
      await pumpDiceScreen(tester, []);
      expect(find.byKey(const Key('mode-selector')), findsOneWidget);

      await tapKey(tester, 'count-plus');
      expect(find.byKey(const Key('mode-selector')), findsNothing);

      await tapKey(tester, 'count-minus');
      await tapKey(tester, 'die-6');
      expect(find.byKey(const Key('mode-selector')), findsNothing);
    });

    testWidgets('Mit Vorteil zählt der höhere Würfel, beide werden angezeigt', (
      tester,
    ) async {
      await pumpDiceScreen(tester, [7, 15]);

      await tapKey(tester, 'mode-advantage');
      await tapKey(tester, 'roll-button');

      expect(textOf(tester, 'result-total'), '15');
      expect(textOf(tester, 'result-detail'), '1d20 Vorteil: 7 | 15 → 15');
    });

    testWidgets('Mit Nachteil zählt der niedrigere Würfel', (tester) async {
      await pumpDiceScreen(tester, [7, 15]);

      await tapKey(tester, 'mode-disadvantage');
      await tapKey(tester, 'roll-button');

      expect(textOf(tester, 'result-total'), '7');
      expect(textOf(tester, 'result-detail'), '1d20 Nachteil: 7 | 15 → 7');
    });

    testWidgets('Eine natürliche 20 und eine natürliche 1 werden '
        'hervorgehoben', (tester) async {
      await pumpDiceScreen(tester, [20, 1]);

      await tapKey(tester, 'roll-button');
      expect(textOf(tester, 'result-note'), 'Natürliche 20');

      await tapKey(tester, 'roll-button');
      expect(textOf(tester, 'result-note'), 'Natürliche 1');
    });
  });

  group('Würfler-Bildschirm: Rettungswurf gegen Schwierigkeitsgrad', () {
    testWidgets('Mit eingetragenem SG wird Erfolg angezeigt, wenn der '
        'Gesamtwert reicht', (tester) async {
      await pumpDiceScreen(tester, [13]);

      await tester.enterText(find.byKey(const Key('dc-field')), '15');
      await tapKey(tester, 'modifier-plus');
      await tapKey(tester, 'modifier-plus');
      await tapKey(tester, 'roll-button');

      expect(textOf(tester, 'result-total'), '15');
      expect(textOf(tester, 'result-note'), 'Erfolg gegen SG 15');
    });

    testWidgets('Mit eingetragenem SG wird Fehlschlag angezeigt, wenn der '
        'Gesamtwert nicht reicht', (tester) async {
      await pumpDiceScreen(tester, [10]);

      await tester.enterText(find.byKey(const Key('dc-field')), '15');
      await tapKey(tester, 'roll-button');

      expect(textOf(tester, 'result-note'), 'Fehlschlag gegen SG 15');
    });

    testWidgets('Ohne SG gibt es keine Erfolgsanzeige', (tester) async {
      await pumpDiceScreen(tester, [10]);

      await tapKey(tester, 'roll-button');

      expect(find.byKey(const Key('result-note')), findsNothing);
    });
  });

  group('Würfler-Bildschirm: Würfe landen im Log', () {
    testWidgets('Jeder Wurf wird als freier Wurf in den Log geschrieben', (
      tester,
    ) async {
      final log = await pumpDiceScreen(tester, [3, 18]);

      await tapKey(tester, 'roll-button');
      await tapKey(tester, 'roll-button');

      final entries = await log.entries();
      expect(entries, hasLength(2));
      expect(entries.every((entry) => entry.event is FreeRollEvent), isTrue);
      expect(
        const LogFormatter().format(entries.first.event).text,
        'Freier Wurf 1d20: 18',
      );
    });

    testWidgets('Vorteil, Modifier und Schwierigkeitsgrad stehen vollständig '
        'im Log-Eintrag', (tester) async {
      final log = await pumpDiceScreen(tester, [7, 15]);

      await tester.enterText(find.byKey(const Key('dc-field')), '15');
      await tapKey(tester, 'mode-advantage');
      await tapKey(tester, 'modifier-plus');
      await tapKey(tester, 'roll-button');

      final event = (await log.entries()).single.event as FreeRollEvent;
      expect(event.roll.rolls, [7, 15]);
      expect(event.roll.mode, RollMode.advantage);
      expect(event.roll.total, 16);
      expect(event.dc, 15);
    });

    testWidgets('Ein Wurf mit mehreren Würfeln steht mit allen Einzelwürfen '
        'im Log', (tester) async {
      final log = await pumpDiceScreen(tester, [4, 5]);

      await tapKey(tester, 'die-6');
      await tapKey(tester, 'count-plus');
      await tapKey(tester, 'roll-button');

      final event = (await log.entries()).single.event as FreeRollEvent;
      expect(event.roll.rolls, [4, 5]);
      expect(event.roll.notation, '2d6');
    });
  });
}
