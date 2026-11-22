import 'package:dmployee/rules/ruleset.dart';
import 'package:dmployee/settings/app_settings.dart';
import 'package:dmployee/settings/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Einstellungen der App', () {
    test('Ohne gespeicherte Wahl gelten die Regeln von 2014', () async {
      final settings = await AppSettings.load(InMemorySettingsRepository());

      expect(settings.ruleset, Ruleset.dnd2014);
    });

    test('Ohne Speicher angelegte Einstellungen nutzen ebenfalls die '
        'Regeln von 2014', () {
      expect(AppSettings().ruleset, Ruleset.dnd2014);
    });

    test('Das gewählte Regelwerk gilt sofort und wird gespeichert', () async {
      final repository = InMemorySettingsRepository();
      final settings = await AppSettings.load(repository);

      await settings.setRuleset(Ruleset.dnd2024);

      expect(settings.ruleset, Ruleset.dnd2024);
      expect(await repository.read('ruleset'), '5e-2024');
    });

    test('Beim nächsten Start ist das gewählte Regelwerk wieder '
        'eingestellt', () async {
      final repository = InMemorySettingsRepository();
      await (await AppSettings.load(repository)).setRuleset(Ruleset.dnd2024);

      final reloaded = await AppSettings.load(repository);

      expect(reloaded.ruleset, Ruleset.dnd2024);
    });

    test('Ein unbekanntes gespeichertes Regelwerk ergibt die Regeln von '
        '2014', () async {
      final repository = InMemorySettingsRepository();
      await repository.write('ruleset', 'unbekannt');

      final settings = await AppSettings.load(repository);

      expect(settings.ruleset, Ruleset.dnd2014);
    });

    test('Wer auf die Einstellungen hört, erfährt vom Wechsel des '
        'Regelwerks', () async {
      final settings = await AppSettings.load(InMemorySettingsRepository());
      var notified = 0;
      settings.addListener(() => notified++);

      await settings.setRuleset(Ruleset.dnd2024);
      await settings.setRuleset(Ruleset.dnd2024);

      expect(notified, 1);
    });
  });
}
