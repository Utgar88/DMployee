import 'package:dmployee/dice/dice_expression.dart';
import 'package:dmployee/dice/dice_roller.dart';
import 'package:dmployee/dice/modifier.dart';
import 'package:dmployee/log/log_event.dart';
import 'package:dmployee/log/log_formatter.dart';
import 'package:dmployee/log/roll_record.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixed_random.dart';

FreeRollEvent d20Event(
  List<int> faces, {
  RollMode mode = RollMode.normal,
  List<Modifier> modifiers = const [],
  int? dc,
}) {
  return FreeRollEvent(
    roll: RollRecord.fromD20(
      DiceRoller(FixedRandom(faces)).rollD20(mode: mode, modifiers: modifiers),
    ),
    dc: dc,
  );
}

void main() {
  const formatter = LogFormatter();

  group('Log-Zeile für einen freien Wurf', () {
    test('Die Zeile beginnt mit "Freier Wurf" und nennt Würfel und Summe', () {
      final line = formatter.format(
        d20Event([15], modifiers: [Modifier('Modifier', 2)]),
      );

      expect(line.text, 'Freier Wurf 1d20+2: 17');
      expect(line.isFreeRoll, isTrue);
    });

    test('Nur die Summe ist antippbar und trägt die Details', () {
      final line = formatter.format(d20Event([15]));

      final tappable = line.spans.where((span) => span.hasDetails).toList();

      expect(tappable, hasLength(1));
      expect(tappable.single.text, '15');
    });

    test(
      'Mit Schwierigkeitsgrad steht Erfolg oder Fehlschlag in der Zeile',
      () {
        expect(
          formatter.format(d20Event([15], dc: 15)).text,
          'Freier Wurf 1d20: 15 (Erfolg gegen SG 15)',
        );
        expect(
          formatter.format(d20Event([14], dc: 15)).text,
          'Freier Wurf 1d20: 14 (Fehlschlag gegen SG 15)',
        );
      },
    );
  });

  group('Details hinter der Summe', () {
    List<String> detailsOf(LogEvent event) =>
        formatter.format(event).spans.firstWhere((s) => s.hasDetails).details;

    test('Ein einfacher d20-Wurf zeigt den Würfel und die Summe', () {
      expect(detailsOf(d20Event([15])), ['1d20: 15', 'Summe: 15']);
    });

    test('Vorteil zeigt beide Würfel und welcher zählt', () {
      expect(detailsOf(d20Event([7, 15], mode: RollMode.advantage)), [
        '1d20 mit Vorteil: 7 | 15 → 15',
        'Summe: 15',
      ]);
    });

    test('Nachteil zeigt beide Würfel und welcher zählt', () {
      expect(detailsOf(d20Event([7, 15], mode: RollMode.disadvantage)), [
        '1d20 mit Nachteil: 7 | 15 → 7',
        'Summe: 7',
      ]);
    });

    test('Jeder Modifier steht mit Herkunft in einer eigenen Zeile', () {
      final event = d20Event(
        [10],
        modifiers: [Modifier('Stärke', 5), Modifier('Fluch', -1)],
      );

      expect(detailsOf(event), [
        '1d20: 10',
        '+5 Stärke',
        '-1 Fluch',
        'Summe: 14',
      ]);
    });

    test('Mehrere Würfel werden einzeln aufgeführt', () {
      final event = FreeRollEvent(
        roll: RollRecord.fromRoll(
          DiceRoller(FixedRandom([4, 5])).roll(DiceExpression.parse('2d6+3')),
        ),
      );

      expect(detailsOf(event), ['2d6: 4 + 5 = 9', '+3 Modifier', 'Summe: 12']);
    });

    test('Natürliche 20 und natürliche 1 werden genannt', () {
      expect(detailsOf(d20Event([20])), contains('Natürliche 20'));
      expect(detailsOf(d20Event([1])), contains('Natürliche 1'));
    });

    test('Mit Schwierigkeitsgrad steht das Ergebnis der Probe am Ende', () {
      expect(detailsOf(d20Event([15], dc: 12)).last, 'Erfolg gegen SG 12');
    });
  });

  group('Unbekannte Ereignisse', () {
    test('Ein unbekanntes Ereignis erscheint als lesbare Zeile statt die '
        'App zu stören', () {
      final line = formatter.format(const UnknownEvent('neuerTyp', {}));

      expect(line.text, 'Unbekannter Eintrag (neuerTyp)');
      expect(line.isFreeRoll, isFalse);
    });
  });
}
