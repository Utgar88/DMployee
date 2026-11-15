import 'package:dmployee/dice/dice_expression.dart';
import 'package:dmployee/dice/dice_roller.dart';
import 'package:dmployee/dice/modifier.dart';
import 'package:dmployee/log/log_event.dart';
import 'package:dmployee/log/roll_record.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixed_random.dart';

void main() {
  group('Wurf-Protokoll (RollRecord)', () {
    test('Ein normaler Wurf merkt sich Würfel, Einzelwürfe, Modifier und '
        'Summe', () {
      final result = DiceRoller(
        FixedRandom([4, 5]),
      ).roll(DiceExpression.parse('2d6+3'), modifiers: [Modifier('Stärke', 2)]);

      final record = RollRecord.fromRoll(result);

      expect(record.count, 2);
      expect(record.sides, 6);
      expect(record.rolls, [4, 5]);
      expect(record.mode, RollMode.normal);
      expect(record.modifiers, [
        Modifier('Modifier', 3),
        Modifier('Stärke', 2),
      ]);
      expect(record.total, 14);
    });

    test('Ein d20-Wurf mit Vorteil merkt sich beide Würfel und den '
        'gewerteten', () {
      final result = DiceRoller(
        FixedRandom([7, 15]),
      ).rollD20(mode: RollMode.advantage, modifiers: [Modifier('Stärke', 5)]);

      final record = RollRecord.fromD20(result);

      expect(record.count, 1);
      expect(record.sides, 20);
      expect(record.rolls, [7, 15]);
      expect(record.mode, RollMode.advantage);
      expect(record.kept, 15);
      expect(record.total, 20);
    });

    test('Die Notation nennt Würfel und Summe der Modifier: "2d6+5"', () {
      final result = DiceRoller(
        FixedRandom([4, 5]),
      ).roll(DiceExpression.parse('2d6+3'), modifiers: [Modifier('Stärke', 2)]);

      expect(RollRecord.fromRoll(result).notation, '2d6+5');
    });

    test('Speichern und Laden (JSON) erhält alle Angaben', () {
      final record = RollRecord.fromD20(
        DiceRoller(FixedRandom([7, 15])).rollD20(
          mode: RollMode.disadvantage,
          modifiers: [Modifier('Stärke', 5), Modifier('Fluch', -1)],
        ),
      );

      final loaded = RollRecord.fromJson(record.toJson());

      expect(loaded.rolls, [7, 15]);
      expect(loaded.mode, RollMode.disadvantage);
      expect(loaded.kept, 7);
      expect(loaded.modifiers, [Modifier('Stärke', 5), Modifier('Fluch', -1)]);
      expect(loaded.total, 11);
    });
  });

  group('Log-Ereignis: freier Wurf (FreeRollEvent)', () {
    test('Ein freier Wurf ist als solcher gekennzeichnet', () {
      final event = FreeRollEvent(
        roll: RollRecord.fromD20(DiceRoller(FixedRandom([10])).rollD20()),
      );

      expect(event.type, 'freeRoll');
    });

    test('Mit Schwierigkeitsgrad weiß das Ereignis, ob der Wurf gelungen '
        'ist', () {
      final roll = RollRecord.fromD20(DiceRoller(FixedRandom([10])).rollD20());

      expect(FreeRollEvent(roll: roll, dc: 10).isSuccess, isTrue);
      expect(FreeRollEvent(roll: roll, dc: 11).isSuccess, isFalse);
      expect(FreeRollEvent(roll: roll).isSuccess, isNull);
    });

    test('Speichern und Laden (JSON) liefert wieder einen freien Wurf mit '
        'denselben Angaben', () {
      final event = FreeRollEvent(
        roll: RollRecord.fromD20(
          DiceRoller(FixedRandom([13]))
              .rollD20(modifiers: [Modifier('Modifier', 2)]),
        ),
        dc: 15,
      );

      final loaded = LogEvent.fromJson(event.type, event.toJson());

      expect(loaded, isA<FreeRollEvent>());
      loaded as FreeRollEvent;
      expect(loaded.roll.total, 15);
      expect(loaded.dc, 15);
      expect(loaded.isSuccess, isTrue);
    });

    test('Ein unbekannter Ereignistyp geht beim Laden nicht verloren, '
        'sondern bleibt als unbekanntes Ereignis erhalten', () {
      final loaded = LogEvent.fromJson('typAusDerZukunft', {'x': 1});

      expect(loaded, isA<UnknownEvent>());
      expect(loaded.type, 'typAusDerZukunft');
      expect(loaded.toJson(), {'x': 1});
    });
  });
}
