import 'package:dmployee/log/log_event.dart';
import 'package:dmployee/log/log_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

const formatter = LogFormatter();

SpellSlotEvent slot({
  int level = 3,
  bool pact = false,
  SlotChange change = SlotChange.used,
  int remaining = 1,
  int total = 3,
}) => SpellSlotEvent(
  name: 'Aria',
  level: level,
  pact: pact,
  change: change,
  remaining: remaining,
  total: total,
);

void main() {
  group('Log: Zauberplätze', () {
    test('Verbrauch eines Zauberplatzes mit Grad und übrigen Plätzen', () {
      expect(
        formatter.format(slot()).text,
        'Aria verbraucht einen Zauberplatz des 3. Grades (1 von 3 übrig)',
      );
    });

    test('Zurückgegebener Zauberplatz', () {
      expect(
        formatter.format(slot(change: SlotChange.restored, remaining: 2)).text,
        'Aria erhält einen Zauberplatz des 3. Grades zurück (2 von 3 übrig)',
      );
    });

    test('Paktmagie wird als solche benannt', () {
      expect(
        formatter.format(slot(pact: true, total: 2, remaining: 1)).text,
        'Aria verbraucht einen Paktmagie-Platz des 3. Grades (1 von 2 übrig)',
      );
      expect(
        formatter
            .format(
              slot(
                pact: true,
                change: SlotChange.restored,
                total: 2,
                remaining: 2,
              ),
            )
            .text,
        'Aria erhält einen Paktmagie-Platz des 3. Grades zurück '
        '(2 von 2 übrig)',
      );
    });

    test('Zauberplatz-Einträge werden gespeichert und geladen', () {
      for (final event in [
        slot(),
        slot(pact: true, change: SlotChange.restored),
      ]) {
        final restored = LogEvent.fromJson(event.type, event.toJson());
        expect(restored, isA<SpellSlotEvent>());
        expect(restored.toJson(), event.toJson());
      }
    });
  });
}
