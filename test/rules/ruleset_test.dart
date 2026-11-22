import 'package:dmployee/rules/ruleset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Regelwerke', () {
    test('Es gibt die Regeln von 2014 und von 2024, in dieser '
        'Reihenfolge', () {
      expect(Ruleset.values, [Ruleset.dnd2014, Ruleset.dnd2024]);
    });

    test('Jedes Regelwerk hat einen Namen und eine kurze Beschreibung', () {
      expect(Ruleset.dnd2014.label, 'D&D 5e (2014)');
      expect(Ruleset.dnd2024.label, 'D&D 5e (2024)');
      expect(Ruleset.dnd2014.description, contains('SRD 5.1'));
      expect(Ruleset.dnd2024.description, contains('SRD 5.2'));
    });

    test('Voreingestellt sind die Regeln von 2014', () {
      expect(Ruleset.standard, Ruleset.dnd2014);
    });

    test('Jedes Regelwerk hat eine feste Kennung zum Speichern und wird '
        'darüber wiedergefunden', () {
      expect(Ruleset.dnd2014.id, '5e-2014');
      expect(Ruleset.dnd2024.id, '5e-2024');
      for (final ruleset in Ruleset.values) {
        expect(Ruleset.byId(ruleset.id), ruleset);
      }
    });

    test('Eine unbekannte oder fehlende Kennung ergibt kein Regelwerk', () {
      expect(Ruleset.byId('3.5'), isNull);
      expect(Ruleset.byId(null), isNull);
    });
  });
}
