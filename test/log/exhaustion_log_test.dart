import 'package:dmployee/dice/dice_roller.dart';
import 'package:dmployee/dice/modifier.dart';
import 'package:dmployee/log/log_event.dart';
import 'package:dmployee/log/log_formatter.dart';
import 'package:dmployee/log/roll_record.dart';
import 'package:flutter_test/flutter_test.dart';

const formatter = LogFormatter();

ExhaustionEvent change(int before, int after, {String ruleset = '5e-2014'}) =>
    ExhaustionEvent(
      name: 'Aria',
      before: before,
      after: after,
      ruleset: ruleset,
    );

List<String> detailsOf(LogEvent event) =>
    formatter.format(event).spans.firstWhere((s) => s.hasDetails).details;

RollRecord d20(List<int> rolls, {RollMode mode = RollMode.normal}) =>
    RollRecord(count: 1, sides: 20, rolls: rolls, mode: mode);

void main() {
  group('Log: Erschöpfung', () {
    test('Steigt die Erschöpfung, nennt die Zeile die neue Stufe', () {
      expect(
        formatter.format(change(1, 2)).text,
        'Aria ist erschöpft: Stufe 2',
      );
    });

    test('Sinkt sie, heißt es "weniger erschöpft"; bei 0 "nicht mehr '
        'erschöpft"', () {
      expect(
        formatter.format(change(3, 2)).text,
        'Aria ist weniger erschöpft: Stufe 2',
      );
      expect(
        formatter.format(change(1, 0)).text,
        'Aria ist nicht mehr erschöpft',
      );
    });

    test('Die Details nennen Stufen, Regelwerk und die Folgen nach 2014', () {
      expect(detailsOf(change(2, 3)), [
        'Stufe: 2 → 3',
        'Regelwerk: D&D 5e (2014)',
        'Nachteil auf Attributswürfe',
        'Bewegungsrate halbiert',
        'Nachteil auf Angriffs- und Rettungswürfe',
      ]);
    });

    test('Die Details nennen die Folgen nach 2024', () {
      expect(detailsOf(change(1, 2, ruleset: '5e-2024')), [
        'Stufe: 1 → 2',
        'Regelwerk: D&D 5e (2024)',
        '−4 auf alle W20-Würfe',
        'Bewegungsrate −3 m',
      ]);
    });

    test('Ohne Erschöpfung gibt es keine Folgen in den Details', () {
      expect(detailsOf(change(1, 0)), [
        'Stufe: 1 → 0',
        'Regelwerk: D&D 5e (2014)',
      ]);
    });

    test('Erschöpfungs-Einträge werden gespeichert und geladen', () {
      final event = change(2, 3, ruleset: '5e-2024');

      final restored =
          LogEvent.fromJson(event.type, event.toJson()) as ExhaustionEvent;

      expect(restored.name, 'Aria');
      expect(restored.before, 2);
      expect(restored.after, 3);
      expect(restored.ruleset, '5e-2024');
    });
  });

  group('Log: Tod durch Erschöpfung', () {
    test('Die Zeile nennt die Erschöpfung als Ursache', () {
      expect(
        formatter
            .format(const CombatantDiedEvent('Aria', exhaustion: true))
            .text,
        'Aria stirbt an Erschöpfung',
      );
    });

    test('Der Grund wird gespeichert und geladen', () {
      const event = CombatantDiedEvent('Aria', exhaustion: true);

      final restored =
          LogEvent.fromJson(event.type, event.toJson()) as CombatantDiedEvent;

      expect(restored.exhaustion, isTrue);
      expect(restored.massiveDamage, isFalse);
    });
  });

  group('Log: Nachteil durch Erschöpfung', () {
    test('Bei der Initiative nennen die Details die Erschöpfung als Grund '
        'für den Nachteil', () {
      final event = InitiativeEvent([
        InitiativeEntry(
          name: 'Aria',
          roll: d20([4, 15], mode: RollMode.disadvantage),
          disadvantageFromExhaustion: 1,
        ),
      ]);

      expect(detailsOf(event), contains('Nachteil: erschöpft (Stufe 1)'));

      final restored =
          LogEvent.fromJson(event.type, event.toJson()) as InitiativeEvent;
      expect(restored.entries.single.disadvantageFromExhaustion, 1);
    });

    test('Beim Todesrettungswurf ebenso', () {
      final event = DeathSaveEvent(
        name: 'Aria',
        roll: d20([4, 15], mode: RollMode.disadvantage),
        successes: 0,
        failures: 1,
        disadvantageFromExhaustion: 3,
      );

      expect(detailsOf(event), contains('Nachteil: erschöpft (Stufe 3)'));

      final restored =
          LogEvent.fromJson(event.type, event.toJson()) as DeathSaveEvent;
      expect(restored.disadvantageFromExhaustion, 3);
    });

    test('Ohne Erschöpfung gibt es keinen solchen Grund', () {
      final event = DeathSaveEvent(
        name: 'Aria',
        roll: d20([15]),
        successes: 1,
        failures: 0,
      );

      expect(detailsOf(event), isNot(contains(startsWith('Nachteil'))));
      expect(event.toJson().containsKey('disadvantageFromExhaustion'), isFalse);
    });

    test('Beim Angriff steht die Erschöpfung des Angreifers als Grund', () {
      final event = AttackEvent(
        attackerName: 'Aria',
        targetName: 'Oger',
        attackName: 'Langschwert',
        targetArmorClass: 11,
        attackRoll: RollRecord(
          count: 1,
          sides: 20,
          rolls: [4, 2],
          mode: RollMode.disadvantage,
          modifiers: [Modifier('Angriffsbonus', 5)],
        ),
        hit: false,
        critical: false,
        damageType: 'Hieb',
        conditionEffects: const [
          ConditionEffect(
            onAttacker: true,
            condition: exhaustionCondition,
            advantage: false,
          ),
        ],
      );

      expect(detailsOf(event), contains('Nachteil: Aria ist erschöpft'));
    });
  });
}
