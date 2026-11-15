import 'dart:math';

import 'package:dmployee/dice/dice_expression.dart';
import 'package:dmployee/dice/dice_roller.dart';
import 'package:dmployee/dice/modifier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixed_random.dart';

void main() {
  group('Normaler Wurf (DiceRoller.roll)', () {
    test('2d6+3 mit den Augen 4 und 5 ergibt die Summe 12', () {
      final roller = DiceRoller(FixedRandom([4, 5]));

      final result = roller.roll(DiceExpression.parse('2d6+3'));

      expect(result.rolls, [4, 5]);
      expect(result.modifier, 3);
      expect(result.total, 12);
    });

    test('Ein negativer Modifier wird von der Summe abgezogen', () {
      final roller = DiceRoller(FixedRandom([1]));

      expect(roller.roll(DiceExpression.parse('1d8-1')).total, 0);
    });

    test('Es wird genau ein Ergebnis pro Würfel gespeichert', () {
      final roller = DiceRoller(Random(1));

      expect(roller.roll(DiceExpression.parse('8d6')).rolls, hasLength(8));
    });

    test(
      '2d6+3 liefert bei 1000 echten Würfen nur Werte zwischen 5 und 15',
      () {
        final roller = DiceRoller(Random(42));
        final expression = DiceExpression.parse('2d6+3');

        for (var i = 0; i < 1000; i++) {
          expect(roller.roll(expression).total, inInclusiveRange(5, 15));
        }
      },
    );

    test('Ein d20 zeigt bei 1000 echten Würfen jede Zahl von 1 bis 20', () {
      final roller = DiceRoller(Random(42));
      final expression = DiceExpression.parse('d20');

      final seen = {
        for (var i = 0; i < 1000; i++) roller.roll(expression).total,
      };

      expect(seen, {for (var face = 1; face <= 20; face++) face});
    });
  });

  group('d20-Wurf mit Vorteil und Nachteil (DiceRoller.rollD20)', () {
    test('Ein normaler Wurf würfelt einen d20 und addiert den Modifier', () {
      final roller = DiceRoller(FixedRandom([13]));

      final result = roller.rollD20(modifiers: [Modifier('Bonus', 5)]);

      expect(result.rolls, [13]);
      expect(result.kept, 13);
      expect(result.total, 18);
    });

    test('Mit Vorteil werden zwei d20 gewürfelt und der höhere zählt', () {
      final roller = DiceRoller(FixedRandom([7, 15]));

      final result = roller.rollD20(
        mode: RollMode.advantage,
        modifiers: [Modifier('Bonus', 2)],
      );

      expect(result.rolls, [7, 15]);
      expect(result.kept, 15);
      expect(result.total, 17);
    });

    test('Mit Nachteil werden zwei d20 gewürfelt und der niedrigere zählt', () {
      final roller = DiceRoller(FixedRandom([7, 15]));

      final result = roller.rollD20(
        mode: RollMode.disadvantage,
        modifiers: [Modifier('Bonus', 2)],
      );

      expect(result.rolls, [7, 15]);
      expect(result.kept, 7);
      expect(result.total, 9);
    });

    test(
      'Eine gewertete 20 ist eine natürliche 20, unabhängig vom Modifier',
      () {
        final roller = DiceRoller(FixedRandom([20]));

        final result = roller.rollD20(modifiers: [Modifier('Bonus', -5)]);

        expect(result.isNatural20, isTrue);
        expect(result.isNatural1, isFalse);
      },
    );

    test('Eine gewertete 1 ist eine natürliche 1, unabhängig vom Modifier', () {
      final roller = DiceRoller(FixedRandom([1]));

      final result = roller.rollD20(modifiers: [Modifier('Bonus', 10)]);

      expect(result.isNatural1, isTrue);
      expect(result.isNatural20, isFalse);
    });

    test('Bei Nachteil zählt eine 20 nicht als natürliche 20, wenn der andere '
        'Würfel niedriger ist', () {
      final roller = DiceRoller(FixedRandom([20, 4]));

      final result = roller.rollD20(mode: RollMode.disadvantage);

      expect(result.kept, 4);
      expect(result.isNatural20, isFalse);
    });
  });

  group('Modifier mit Herkunft (Modifier)', () {
    test('Mehrere Modifier werden beim d20-Wurf zusammengezählt', () {
      final roller = DiceRoller(FixedRandom([10]));

      final result = roller.rollD20(
        modifiers: [Modifier('Stärke', 5), Modifier('Übung', 2)],
      );

      expect(result.modifier, 7);
      expect(result.total, 17);
    });

    test('Jeder Modifier behält seine Herkunft und seinen Wert', () {
      final roller = DiceRoller(FixedRandom([10]));

      final result = roller.rollD20(
        modifiers: [Modifier('Stärke', 5), Modifier('Fluch', -1)],
      );

      expect(result.modifiers.map((m) => m.label), ['Stärke', 'Fluch']);
      expect(result.modifiers.map((m) => m.value), [5, -1]);
    });

    test('Ohne Modifier ist die Summe der Modifier 0', () {
      final result = DiceRoller(FixedRandom([10])).rollD20();

      expect(result.modifiers, isEmpty);
      expect(result.modifier, 0);
    });

    test('Beim normalen Wurf zählen Modifier mit Herkunft zusätzlich zum '
        'Modifier aus dem Würfelausdruck', () {
      final roller = DiceRoller(FixedRandom([4, 5]));

      final result = roller.roll(
        DiceExpression.parse('2d6+3'),
        modifiers: [Modifier('Stärke', 2)],
      );

      expect(result.modifier, 5);
      expect(result.total, 14);
    });

    test('Ein Modifier zeigt sich mit Vorzeichen: "+5 Stärke", "-1 Fluch"', () {
      expect(Modifier('Stärke', 5).toString(), '+5 Stärke');
      expect(Modifier('Fluch', -1).toString(), '-1 Fluch');
    });
  });
}
