import 'package:dmployee/dice/dice_roller.dart';
import 'package:dmployee/dice/modifier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixed_random.dart';

void main() {
  group('Wurf gegen einen Schwierigkeitsgrad (DiceRoller.rollCheck)', () {
    test('Ein Gesamtwert über dem Schwierigkeitsgrad ist ein Erfolg', () {
      final roller = DiceRoller(FixedRandom([12]));

      final check = roller.rollCheck(dc: 15, modifiers: [Modifier('Bonus', 4)]);

      expect(check.roll.total, 16);
      expect(check.dc, 15);
      expect(check.isSuccess, isTrue);
    });

    test('Ein Gesamtwert genau auf dem Schwierigkeitsgrad ist ein Erfolg', () {
      final roller = DiceRoller(FixedRandom([11]));

      expect(
        roller.rollCheck(dc: 15, modifiers: [Modifier('Bonus', 4)]).isSuccess,
        isTrue,
      );
    });

    test('Ein Gesamtwert unter dem Schwierigkeitsgrad ist ein Fehlschlag', () {
      final roller = DiceRoller(FixedRandom([10]));

      expect(
        roller.rollCheck(dc: 15, modifiers: [Modifier('Bonus', 4)]).isSuccess,
        isFalse,
      );
    });

    test('Der Abstand zum Schwierigkeitsgrad wird mitgeliefert', () {
      expect(
        DiceRoller(FixedRandom([12]))
            .rollCheck(dc: 15, modifiers: [Modifier('Bonus', 4)])
            .margin,
        1,
      );
      expect(
        DiceRoller(FixedRandom([8]))
            .rollCheck(dc: 15, modifiers: [Modifier('Bonus', 4)])
            .margin,
        -3,
      );
    });

    test('Mit Vorteil entscheidet der höhere der beiden Würfel', () {
      final roller = DiceRoller(FixedRandom([3, 14]));

      final check = roller.rollCheck(dc: 12, mode: RollMode.advantage);

      expect(check.roll.kept, 14);
      expect(check.isSuccess, isTrue);
    });

    test('Mit Nachteil entscheidet der niedrigere der beiden Würfel', () {
      final roller = DiceRoller(FixedRandom([3, 14]));

      final check = roller.rollCheck(dc: 12, mode: RollMode.disadvantage);

      expect(check.roll.kept, 3);
      expect(check.isSuccess, isFalse);
    });

    test('Eine natürliche 20 ist bei Rettungswürfen kein automatischer Erfolg '
        '(5e-Regel: nur der Gesamtwert zählt)', () {
      final roller = DiceRoller(FixedRandom([20]));

      final check = roller.rollCheck(dc: 25, modifiers: [Modifier('Bonus', 2)]);

      expect(check.roll.isNatural20, isTrue);
      expect(check.isSuccess, isFalse);
    });

    test('Eine natürliche 1 ist bei Rettungswürfen kein automatischer '
        'Fehlschlag (5e-Regel: nur der Gesamtwert zählt)', () {
      final roller = DiceRoller(FixedRandom([1]));

      final check = roller.rollCheck(dc: 10, modifiers: [Modifier('Bonus', 9)]);

      expect(check.roll.isNatural1, isTrue);
      expect(check.isSuccess, isTrue);
    });
  });
}
