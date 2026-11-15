import 'package:dmployee/dice/dice_expression.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Würfelausdruck lesen (DiceExpression.parse)', () {
    test('"2d6+3" ergibt 2 Würfel mit 6 Seiten und Modifier +3', () {
      final expression = DiceExpression.parse('2d6+3');

      expect(expression.count, 2);
      expect(expression.sides, 6);
      expect(expression.modifier, 3);
    });

    test('"d20" ohne Anzahl ergibt genau 1 Würfel und Modifier 0', () {
      final expression = DiceExpression.parse('d20');

      expect(expression.count, 1);
      expect(expression.sides, 20);
      expect(expression.modifier, 0);
    });

    test('"1d8-1" ergibt einen negativen Modifier von -1', () {
      expect(DiceExpression.parse('1d8-1').modifier, -1);
    });

    test('Die deutsche Schreibweise "2W6+3" wird wie "2d6+3" gelesen', () {
      expect(DiceExpression.parse('2W6+3'), DiceExpression.parse('2d6+3'));
    });

    test('Groß-/Kleinschreibung und Leerzeichen spielen keine Rolle', () {
      expect(
        DiceExpression.parse(' 2 D 6 + 3 '),
        DiceExpression.parse('2d6+3'),
      );
      expect(DiceExpression.parse('2w6'), DiceExpression.parse('2d6'));
    });

    test('Ungültige Eingaben werden mit einer FormatException abgelehnt', () {
      for (final input in [
        '',
        'abc',
        '2d',
        'd',
        '2x6',
        '2d6+',
        '2d6++3',
        '3',
      ]) {
        expect(
          () => DiceExpression.parse(input),
          throwsFormatException,
          reason: 'Eingabe "$input" muss abgelehnt werden',
        );
      }
    });

    test('0 Würfel oder Würfel mit weniger als 2 Seiten werden abgelehnt', () {
      expect(() => DiceExpression.parse('0d6'), throwsFormatException);
      expect(() => DiceExpression.parse('1d1'), throwsFormatException);
      expect(() => DiceExpression.parse('1d0'), throwsFormatException);
    });
  });

  group('Würfelausdruck Eigenschaften', () {
    test('2d6+3 hat das Minimum 5 und das Maximum 15', () {
      final expression = DiceExpression.parse('2d6+3');

      expect(expression.min, 5);
      expect(expression.max, 15);
    });

    test('Die Textdarstellung ist die Standardnotation', () {
      expect(DiceExpression.parse('2W6+3').toString(), '2d6+3');
      expect(DiceExpression.parse('d20').toString(), '1d20');
      expect(DiceExpression.parse('1d8-1').toString(), '1d8-1');
    });
  });
}
