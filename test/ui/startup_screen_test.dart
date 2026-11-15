import 'dart:async';

import 'package:dmployee/combat/encounter.dart';
import 'package:dmployee/log/log_repository.dart';
import 'package:dmployee/main.dart';
import 'package:dmployee/ui/dice_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

AppData appData() {
  final log = InMemoryLogRepository();
  return (
    log: log,
    encounter: Encounter(log: log)
      ..add(name: 'Aria', armorClass: 16, maxHp: 20),
  );
}

final splash = find.byKey(const Key('splash-image'));

void main() {
  group('Ladebildschirm', () {
    testWidgets('Beim Start ist der Ladebildschirm mit dem Bild zu sehen, '
        'solange die Daten geladen werden', (tester) async {
      final loading = Completer<AppData>();
      await tester.pumpWidget(DMployeeApp.starting(load: () => loading.future));
      await tester.pump(const Duration(seconds: 5));

      expect(splash, findsOneWidget);
      expect(find.byType(DiceScreen), findsNothing);

      loading.complete(appData());
      await tester.pumpAndSettle();
    });

    testWidgets('Auf einem schmalen, hohen Bildschirm wird das Bild '
        'vollständig gezeigt und nicht seitlich abgeschnitten', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final loading = Completer<AppData>();
      await tester.pumpWidget(DMployeeApp.starting(load: () => loading.future));
      await tester.pump(const Duration(seconds: 2));

      // The picture is 941 x 1672: full width, its own proportions.
      final size = tester.getSize(splash);
      expect(size.width, 1080);
      expect(size.width / size.height, closeTo(941 / 1672, 0.01));

      loading.complete(appData());
      await tester.pumpAndSettle();
    });

    testWidgets('Sind die Daten geladen, folgt der Würfler-Bildschirm', (
      tester,
    ) async {
      await tester.pumpWidget(
        DMployeeApp.starting(load: () async => appData()),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byType(DiceScreen), findsOneWidget);
      expect(splash, findsNothing);
    });

    testWidgets('Geht das Laden schneller als die Mindestzeit, bleibt der '
        'Ladebildschirm bis zum Ablauf der Mindestzeit stehen', (tester) async {
      await tester.pumpWidget(
        DMployeeApp.starting(
          load: () async => appData(),
          minimumSplash: const Duration(seconds: 2),
        ),
      );

      await tester.pump(const Duration(milliseconds: 1900));
      expect(splash, findsOneWidget);
      expect(find.byType(DiceScreen), findsNothing);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.byType(DiceScreen), findsOneWidget);
    });

    testWidgets('Der beim Start geladene Kampf steht danach auf dem '
        'Kampf-Bildschirm', (tester) async {
      await tester.pumpWidget(
        DMployeeApp.starting(load: () async => appData()),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      await tester.tap(find.byKey(const Key('nav-combat')));
      await tester.pumpAndSettle();

      expect(find.text('Aria'), findsOneWidget);
    });

    testWidgets('Schlägt das Laden fehl, steht eine Meldung da statt eines '
        'endlosen Ladebildschirms', (tester) async {
      await tester.pumpWidget(
        DMployeeApp.starting(
          load: () async => throw StateError('Datenbank kaputt'),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.byKey(const Key('startup-error')), findsOneWidget);
      expect(find.byType(DiceScreen), findsNothing);
    });
  });
}
