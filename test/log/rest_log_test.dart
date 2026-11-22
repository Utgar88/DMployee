import 'package:dmployee/dice/modifier.dart';
import 'package:dmployee/log/log_event.dart';
import 'package:dmployee/log/log_formatter.dart';
import 'package:dmployee/log/roll_record.dart';
import 'package:flutter_test/flutter_test.dart';

const formatter = LogFormatter();

RestEvent longRest({int tempHpBefore = 0}) => RestEvent(
  name: 'Aria',
  kind: RestKind.long,
  ruleset: '5e-2014',
  hpBefore: 12,
  hpAfter: 31,
  maxHp: 31,
  tempHpBefore: tempHpBefore,
  hitDiceBefore: 1,
  hitDiceAfter: 3,
  hitDiceTotal: 5,
);

const shortRest = RestEvent(
  name: 'Aria',
  kind: RestKind.short,
  ruleset: '5e-2024',
  hpBefore: 12,
  hpAfter: 12,
  maxHp: 31,
  hitDiceBefore: 3,
  hitDiceAfter: 3,
  hitDiceTotal: 5,
);

RestEvent blocked(RestKind kind, RestBlocker blocker) => RestEvent(
  name: 'Borin',
  kind: kind,
  ruleset: '5e-2024',
  blocker: blocker,
  hpBefore: 0,
  hpAfter: 0,
  maxHp: 24,
  hitDiceBefore: 2,
  hitDiceAfter: 2,
  hitDiceTotal: 4,
);

HitDieEvent hitDie({
  List<int> rolls = const [5],
  int constitution = 2,
  int healing = 7,
  int hpBefore = 5,
  int hpAfter = 12,
  String ruleset = '5e-2014',
}) => HitDieEvent(
  name: 'Aria',
  ruleset: ruleset,
  roll: RollRecord(
    count: 1,
    sides: 8,
    rolls: rolls,
    modifiers: [Modifier('Konstitution', constitution)],
  ),
  healing: healing,
  hpBefore: hpBefore,
  hpAfter: hpAfter,
  maxHp: 31,
  hitDiceLeft: 2,
  hitDiceTotal: 5,
);

void main() {
  group('Log: Rasten', () {
    test('Eine lange Rast zeigt TP und übrige Trefferwürfel danach', () {
      final line = formatter.format(longRest());

      expect(
        line.text,
        'Aria beendet eine lange Rast: TP 31/31, Trefferwürfel 3/5',
      );
    });

    test('Die Details der langen Rast nennen Regelwerk, Trefferpunkte vorher '
        'und nachher und die zurückgewonnenen Trefferwürfel mit Regel', () {
      final span = formatter
          .format(longRest())
          .spans
          .singleWhere((s) => s.hasDetails);

      expect(span.text, 'TP 31/31, Trefferwürfel 3/5');
      expect(span.details, [
        'Regelwerk: D&D 5e (2014)',
        'Trefferpunkte: 12 → 31 (Maximum 31)',
        'Trefferwürfel übrig: 1 → 3 von 5',
        'Zurück nach der langen Rast: die Hälfte aller Trefferwürfel, '
            'mindestens 1',
      ]);
    });

    test('Verlorene temporäre TP stehen in den Details der langen Rast', () {
      final span = formatter
          .format(longRest(tempHpBefore: 5))
          .spans
          .singleWhere((s) => s.hasDetails);

      expect(span.details, contains('Temporäre TP: 5 → 0'));
    });

    test('Eine kurze Rast zeigt TP und übrige Trefferwürfel; die Details '
        'nennen das Regelwerk', () {
      final line = formatter.format(shortRest);

      expect(
        line.text,
        'Aria macht eine kurze Rast: TP 12/31, Trefferwürfel 3/5',
      );
      expect(line.spans.singleWhere((s) => s.hasDetails).details, [
        'Regelwerk: D&D 5e (2024)',
      ]);
    });

    test('Ohne Nutzen von der Rast steht der Grund in der Zeile und die '
        'Voraussetzung in den Details', () {
      expect(
        formatter.format(blocked(RestKind.long, RestBlocker.dead)).text,
        'Borin hat keinen Nutzen von der langen Rast (tot)',
      );
      expect(
        formatter.format(blocked(RestKind.short, RestBlocker.dying)).text,
        'Borin hat keinen Nutzen von der kurzen Rast (liegt im Sterben)',
      );
      final noHp = formatter.format(
        blocked(RestKind.short, RestBlocker.tooFewHp),
      );
      expect(noHp.text, 'Borin hat keinen Nutzen von der kurzen Rast (0 TP)');
      expect(noHp.spans.singleWhere((s) => s.hasDetails).details, [
        'Regelwerk: D&D 5e (2024)',
        'Voraussetzung: mindestens 1 TP',
      ]);
    });

    test('Ein ausgegebener Trefferwürfel zeigt die Heilung; nur der Betrag '
        'ist antippbar', () {
      final line = formatter.format(hitDie());

      expect(
        line.text,
        'Aria gibt einen Trefferwürfel aus und wird um 7 TP geheilt',
      );
      final span = line.spans.singleWhere((s) => s.hasDetails);
      expect(span.text, '7');
      expect(span.details, [
        '1d8: 5',
        '+2 Konstitution',
        'Summe: 7',
        'Trefferpunkte: 5 → 12 (Maximum 31)',
        'Trefferwürfel übrig: 2 von 5',
      ]);
    });

    test('Greift die Mindestheilung des Regelwerks, steht das in den '
        'Details', () {
      final span = formatter
          .format(
            hitDie(
              rolls: [1],
              constitution: -1,
              healing: 1,
              hpAfter: 6,
              ruleset: '5e-2024',
            ),
          )
          .spans
          .singleWhere((s) => s.hasDetails);

      expect(span.details, contains('Summe: 0'));
      expect(span.details, contains('Mindestens 1 TP nach D&D 5e (2024)'));
    });

    test('Heilt der Trefferwürfel über das Maximum hinaus, steht der '
        'wirksame Teil in den Details', () {
      final span = formatter
          .format(hitDie(hpBefore: 28, hpAfter: 31))
          .spans
          .singleWhere((s) => s.hasDetails);

      expect(span.details, contains('Davon wirksam: 3'));
    });

    test('Rasten und Trefferwürfel werden mit allen Angaben gespeichert und '
        'geladen', () {
      for (final event in <LogEvent>[
        longRest(tempHpBefore: 5),
        shortRest,
        blocked(RestKind.long, RestBlocker.tooFewHp),
        hitDie(),
      ]) {
        final restored = LogEvent.fromJson(event.type, event.toJson());
        expect(restored.runtimeType, event.runtimeType);
        expect(restored.toJson(), event.toJson());
        expect(formatter.format(restored).text, formatter.format(event).text);
      }
    });
  });
}
