import 'package:dmployee/dice/dice_roller.dart';
import 'package:dmployee/dice/modifier.dart';
import 'package:dmployee/log/log_event.dart';
import 'package:dmployee/log/log_repository.dart';
import 'package:dmployee/log/roll_record.dart';
import 'package:dmployee/ui/log_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fixed_random.dart';

FreeRollEvent rollEvent(
  List<int> faces, {
  RollMode mode = RollMode.normal,
  List<Modifier> modifiers = const [],
}) => FreeRollEvent(
  roll: RollRecord.fromD20(
    DiceRoller(FixedRandom(faces)).rollD20(mode: mode, modifiers: modifiers),
  ),
);

Future<void> pumpLogScreen(WidgetTester tester, LogRepository log) async {
  await tester.pumpWidget(MaterialApp(home: LogScreen(log: log)));
  await tester.pumpAndSettle();
}

/// The visible text of the log line for the entry with [id].
String lineText(WidgetTester tester, int id) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(Key('log-line-$id')),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.data)
    .join();

void main() {
  group('Log-Bildschirm: Einträge', () {
    testWidgets('Ein leerer Log zeigt einen Hinweis', (tester) async {
      await pumpLogScreen(tester, InMemoryLogRepository());

      expect(find.text('Noch keine Einträge'), findsOneWidget);
    });

    testWidgets('Einträge stehen mit dem neuesten zuerst im Log', (
      tester,
    ) async {
      final log = InMemoryLogRepository();
      await log.add(rollEvent([3]));
      await log.add(rollEvent([18]));

      await pumpLogScreen(tester, log);

      expect(lineText(tester, 2), 'Freier Wurf 1d20: 18');
      expect(lineText(tester, 1), 'Freier Wurf 1d20: 3');
      expect(
        tester.getTopLeft(find.byKey(const Key('log-line-2'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('log-line-1'))).dy),
      );
    });

    testWidgets('Ein freier Wurf ist am Würfel-Symbol erkennbar', (
      tester,
    ) async {
      final log = InMemoryLogRepository();
      await log.add(rollEvent([10]));

      await pumpLogScreen(tester, log);

      expect(find.byKey(const Key('free-roll-icon-1')), findsOneWidget);
    });

    testWidgets('Jeder Eintrag zeigt seine Uhrzeit', (tester) async {
      final log = InMemoryLogRepository(
        now: () => DateTime(2026, 11, 15, 20, 5),
      );
      await log.add(rollEvent([10]));

      await pumpLogScreen(tester, log);

      expect(find.text('20:05'), findsOneWidget);
    });
  });

  group('Log-Bildschirm: Details hinter der Summe', () {
    testWidgets('Die Details sind zunächst verborgen', (tester) async {
      final log = InMemoryLogRepository();
      await log.add(rollEvent([7, 15], mode: RollMode.advantage));

      await pumpLogScreen(tester, log);

      expect(find.text('1d20 mit Vorteil: 7 | 15 → 15'), findsNothing);
    });

    testWidgets('Ein Tipp auf die Summe zeigt Würfel, Modifier mit Herkunft '
        'und Summe', (tester) async {
      final log = InMemoryLogRepository();
      await log.add(
        rollEvent(
          [7, 15],
          mode: RollMode.advantage,
          modifiers: [Modifier('Stärke', 5)],
        ),
      );
      await pumpLogScreen(tester, log);

      await tester.tap(find.byKey(const Key('log-value-1')));
      await tester.pumpAndSettle();

      expect(find.text('1d20 mit Vorteil: 7 | 15 → 15'), findsOneWidget);
      expect(find.text('+5 Stärke'), findsOneWidget);
      expect(find.text('Summe: 20'), findsOneWidget);
    });

    testWidgets('Ein zweiter Tipp klappt die Details wieder zu', (
      tester,
    ) async {
      final log = InMemoryLogRepository();
      await log.add(rollEvent([12]));
      await pumpLogScreen(tester, log);

      await tester.tap(find.byKey(const Key('log-value-1')));
      await tester.pumpAndSettle();
      expect(find.text('Summe: 12'), findsOneWidget);

      await tester.tap(find.byKey(const Key('log-value-1')));
      await tester.pumpAndSettle();
      expect(find.text('Summe: 12'), findsNothing);
    });
  });

  group('Log-Bildschirm: Sessions', () {
    Future<InMemoryLogRepository> twoSessions() async {
      final log = InMemoryLogRepository();
      await log.startSession('Abend 1');
      await log.add(rollEvent([5]));
      await log.startSession('Abend 2');
      await log.add(rollEvent([6]));
      return log;
    }

    Future<void> chooseSession(WidgetTester tester, String name) async {
      await tester.tap(find.byKey(const Key('session-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    testWidgets('Ohne Filter sind die Einträge aller Sessions zu sehen', (
      tester,
    ) async {
      await pumpLogScreen(tester, await twoSessions());

      expect(find.byKey(const Key('log-line-1')), findsOneWidget);
      expect(find.byKey(const Key('log-line-2')), findsOneWidget);
    });

    testWidgets('Mit gewählter Session sind nur deren Einträge zu sehen', (
      tester,
    ) async {
      await pumpLogScreen(tester, await twoSessions());

      await chooseSession(tester, 'Abend 1');

      expect(find.byKey(const Key('log-line-1')), findsOneWidget);
      expect(find.byKey(const Key('log-line-2')), findsNothing);
    });

    testWidgets('"Alle Sessions" hebt den Filter wieder auf', (tester) async {
      await pumpLogScreen(tester, await twoSessions());

      await chooseSession(tester, 'Abend 1');
      await chooseSession(tester, 'Alle Sessions');

      expect(find.byKey(const Key('log-line-2')), findsOneWidget);
    });

    testWidgets('Eine neue Session lässt sich mit eigenem Namen starten und '
        'nimmt danach die neuen Einträge auf', (tester) async {
      final log = InMemoryLogRepository();
      await pumpLogScreen(tester, log);

      await tester.tap(find.byKey(const Key('new-session-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('session-name-field')),
        'Die Mine von Phandelver',
      );
      await tester.tap(find.byKey(const Key('session-start-button')));
      await tester.pumpAndSettle();

      expect((await log.activeSession()).name, 'Die Mine von Phandelver');
    });
  });
}
