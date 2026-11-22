import 'package:dmployee/rules/ruleset.dart';
import 'package:dmployee/settings/app_settings.dart';
import 'package:dmployee/settings/settings_repository.dart';
import 'package:dmployee/ui/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<AppSettings> show(
    WidgetTester tester, {
    SettingsRepository? repository,
  }) async {
    final settings = await AppSettings.load(
      repository ?? InMemorySettingsRepository(),
    );
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(settings: settings)),
    );
    return settings;
  }

  bool selected(WidgetTester tester, Ruleset ruleset) {
    final group = tester.widget<RadioGroup<Ruleset>>(
      find.byType(RadioGroup<Ruleset>),
    );
    return group.groupValue == ruleset;
  }

  group('Einstellungen: Regelwerk', () {
    testWidgets('Der Bildschirm zeigt beide Regelwerke mit Beschreibung', (
      tester,
    ) async {
      await show(tester);

      expect(find.text('Einstellungen'), findsOneWidget);
      expect(find.text('Regelwerk'), findsOneWidget);
      expect(find.text('D&D 5e (2014)'), findsOneWidget);
      expect(find.text('D&D 5e (2024)'), findsOneWidget);
      expect(find.text(Ruleset.dnd2014.description), findsOneWidget);
      expect(find.text(Ruleset.dnd2024.description), findsOneWidget);
    });

    testWidgets('Ohne gespeicherte Wahl ist 2014 ausgewählt', (tester) async {
      await show(tester);

      expect(selected(tester, Ruleset.dnd2014), isTrue);
    });

    testWidgets('Ein Tipp auf 2024 wählt dieses Regelwerk aus und speichert '
        'es', (tester) async {
      final repository = InMemorySettingsRepository();
      final settings = await show(tester, repository: repository);

      await tester.tap(find.byKey(const Key('ruleset-5e-2024')));
      await tester.pumpAndSettle();

      expect(selected(tester, Ruleset.dnd2024), isTrue);
      expect(settings.ruleset, Ruleset.dnd2024);
      expect(await repository.read('ruleset'), '5e-2024');
    });

    testWidgets('Ein früher gewähltes Regelwerk ist beim Öffnen ausgewählt', (
      tester,
    ) async {
      final repository = InMemorySettingsRepository();
      await repository.write('ruleset', '5e-2024');

      await show(tester, repository: repository);

      expect(selected(tester, Ruleset.dnd2024), isTrue);
    });
  });
}
