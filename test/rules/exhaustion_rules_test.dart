import 'package:dmployee/rules/exhaustion_rules.dart';
import 'package:dmployee/rules/ruleset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Erschöpfung hat in beiden Regelwerken die Stufen 0 bis 6', () {
    expect(maxExhaustion, 6);
  });

  group('Erschöpfung 2014 (SRD 5.1)', () {
    const rules = Ruleset.dnd2014;

    test('Es gibt keinen Abzug auf W20-Würfe', () {
      for (var level = 0; level <= 6; level++) {
        expect(rules.exhaustionD20Penalty(level), 0);
      }
    });

    test('Ab Stufe 1 gibt es Nachteil auf Attributswürfe', () {
      expect(rules.exhaustionDisadvantageOnChecks(0), isFalse);
      expect(rules.exhaustionDisadvantageOnChecks(1), isTrue);
      expect(rules.exhaustionDisadvantageOnChecks(6), isTrue);
    });

    test('Ab Stufe 3 gibt es Nachteil auf Angriffs- und Rettungswürfe', () {
      expect(rules.exhaustionDisadvantageOnAttacksAndSaves(2), isFalse);
      expect(rules.exhaustionDisadvantageOnAttacksAndSaves(3), isTrue);
      expect(rules.exhaustionDisadvantageOnAttacksAndSaves(5), isTrue);
    });

    test('Ab Stufe 4 sind die maximalen TP halbiert, abgerundet, '
        'mindestens 1', () {
      expect(rules.maxHpWithExhaustion(25, 3), 25);
      expect(rules.maxHpWithExhaustion(25, 4), 12);
      expect(rules.maxHpWithExhaustion(24, 5), 12);
      expect(rules.maxHpWithExhaustion(1, 4), 1);
    });

    test('Die Folgen jeder Stufe gelten zusammen mit denen der Stufen '
        'darunter', () {
      expect(rules.exhaustionEffects(0), isEmpty);
      expect(rules.exhaustionEffects(1), ['Nachteil auf Attributswürfe']);
      expect(rules.exhaustionEffects(4), [
        'Nachteil auf Attributswürfe',
        'Bewegungsrate halbiert',
        'Nachteil auf Angriffs- und Rettungswürfe',
        'Maximale TP halbiert',
      ]);
      expect(rules.exhaustionEffects(6).last, 'Tod');
      expect(rules.exhaustionEffects(6), hasLength(6));
    });
  });

  group('Erschöpfung 2024 (SRD 5.2)', () {
    const rules = Ruleset.dnd2024;

    test('Jeder W20-Wurf sinkt um 2 je Stufe', () {
      expect(rules.exhaustionD20Penalty(0), 0);
      expect(rules.exhaustionD20Penalty(1), -2);
      expect(rules.exhaustionD20Penalty(5), -10);
    });

    test('Es gibt keinen Nachteil und die maximalen TP bleiben', () {
      for (var level = 0; level <= 6; level++) {
        expect(rules.exhaustionDisadvantageOnChecks(level), isFalse);
        expect(rules.exhaustionDisadvantageOnAttacksAndSaves(level), isFalse);
        expect(rules.maxHpWithExhaustion(25, level), 25);
      }
    });

    test('Die Folgen nennen den Abzug und die Bewegungsrate in Metern', () {
      expect(rules.exhaustionEffects(0), isEmpty);
      expect(rules.exhaustionEffects(1), [
        '−2 auf alle W20-Würfe',
        'Bewegungsrate −1,5 m',
      ]);
      expect(rules.exhaustionEffects(4), [
        '−8 auf alle W20-Würfe',
        'Bewegungsrate −6 m',
      ]);
      expect(rules.exhaustionEffects(6), ['Tod']);
    });
  });

  test('In beiden Regelwerken tötet Stufe 6', () {
    for (final rules in Ruleset.values) {
      expect(rules.exhaustionKills(5), isFalse);
      expect(rules.exhaustionKills(6), isTrue);
    }
  });
}
