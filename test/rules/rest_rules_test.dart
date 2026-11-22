import 'package:dmployee/rules/rest_rules.dart';
import 'package:dmployee/rules/ruleset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Rastregeln 2014 (SRD 5.1)', () {
    const rules = Ruleset.dnd2014;

    test('Eine kurze Rast setzt keine Trefferpunkte voraus; eine lange Rast '
        'mindestens 1 TP', () {
      expect(rules.minHpForShortRest, 0);
      expect(rules.minHpForLongRest, 1);
    });

    test('Ein Trefferwürfel heilt um Wurf plus KON-Modifikator, aber nie '
        'unter 0', () {
      expect(rules.hitDieHealing(9), 9);
      expect(rules.hitDieHealing(1), 1);
      expect(rules.hitDieHealing(0), 0);
      expect(rules.hitDieHealing(-1), 0);
    });

    test('Nach einer langen Rast kommt die Hälfte aller Trefferwürfel zurück, '
        'abgerundet, mindestens einer', () {
      expect(rules.hitDiceRegainedOnLongRest(8), 4);
      expect(rules.hitDiceRegainedOnLongRest(5), 2);
      expect(rules.hitDiceRegainedOnLongRest(2), 1);
      expect(rules.hitDiceRegainedOnLongRest(1), 1);
    });
  });

  group('Rastregeln 2024 (SRD 5.2)', () {
    const rules = Ruleset.dnd2024;

    test('Kurze und lange Rast setzen mindestens 1 TP voraus', () {
      expect(rules.minHpForShortRest, 1);
      expect(rules.minHpForLongRest, 1);
    });

    test('Ein Trefferwürfel heilt um Wurf plus KON-Modifikator, mindestens '
        'um 1', () {
      expect(rules.hitDieHealing(9), 9);
      expect(rules.hitDieHealing(1), 1);
      expect(rules.hitDieHealing(0), 1);
      expect(rules.hitDieHealing(-1), 1);
    });

    test('Nach einer langen Rast kommen alle Trefferwürfel zurück', () {
      expect(rules.hitDiceRegainedOnLongRest(8), 8);
      expect(rules.hitDiceRegainedOnLongRest(5), 5);
      expect(rules.hitDiceRegainedOnLongRest(1), 1);
    });
  });

  test('Jede Rastregel nennt ihre Grundlage für die Details im Log', () {
    expect(
      Ruleset.dnd2014.longRestHitDiceRule,
      'die Hälfte aller Trefferwürfel, mindestens 1',
    );
    expect(Ruleset.dnd2024.longRestHitDiceRule, 'alle Trefferwürfel');
  });
}
