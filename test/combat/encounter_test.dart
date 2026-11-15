import 'package:dmployee/combat/attack.dart';
import 'package:dmployee/combat/combatant.dart';
import 'package:dmployee/combat/encounter.dart';
import 'package:dmployee/dice/dice_expression.dart';
import 'package:dmployee/dice/dice_roller.dart';
import 'package:dmployee/log/log_event.dart';
import 'package:dmployee/log/log_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixed_random.dart';

final longsword = Attack(
  name: 'Langschwert',
  attackBonus: 5,
  damage: DiceExpression.parse('1d8+3'),
  damageType: 'Hieb',
);

/// An encounter whose dice show the given [faces] in order, with the
/// fighter Aria (RK 16, 20 TP, Initiative +2, Langschwert) and a Goblin
/// (RK 13, 7 TP, Initiative +1).
class Scene {
  Scene(List<int> faces) {
    encounter = Encounter(log: log, roller: DiceRoller(FixedRandom(faces)));
    aria = encounter.add(
      name: 'Aria',
      armorClass: 16,
      maxHp: 20,
      initiativeBonus: 2,
      attacks: [longsword],
    );
    goblin = encounter.add(
      name: 'Goblin',
      armorClass: 13,
      maxHp: 7,
      initiativeBonus: 1,
    );
  }

  final log = InMemoryLogRepository();
  late final Encounter encounter;
  late final Combatant aria;
  late final Combatant goblin;

  /// Logged events, oldest first.
  Future<List<LogEvent>> events() async =>
      (await log.entries()).reversed.map((entry) => entry.event).toList();

  Future<AttackOutcome> ariaAttacksGoblin({
    RollMode mode = RollMode.normal,
    int? manualAttackRoll,
    int? manualDamage,
  }) => encounter.attack(
    attacker: aria,
    target: goblin,
    attack: longsword,
    mode: mode,
    manualAttackRoll: manualAttackRoll,
    manualDamage: manualDamage,
  );
}

void main() {
  group('Kämpfer', () {
    test('Ein neuer Kämpfer startet mit vollen Trefferpunkten', () {
      final scene = Scene([]);

      expect(scene.aria.hp, 20);
      expect(scene.aria.maxHp, 20);
      expect(scene.aria.isDown, isFalse);
    });

    test('Kämpfer lassen sich wieder entfernen', () {
      final scene = Scene([]);

      scene.encounter.remove(scene.goblin);

      expect(scene.encounter.combatants, [scene.aria]);
    });

    test('Einem Kämpfer lassen sich Angriffe hinterlegen', () {
      final scene = Scene([]);

      scene.goblin.attacks.add(
        Attack(
          name: 'Krummsäbel',
          attackBonus: 4,
          damage: DiceExpression.parse('1d6+2'),
          damageType: 'Hieb',
        ),
      );

      expect(scene.goblin.attacks.single.name, 'Krummsäbel');
    });
  });

  group('Initiative', () {
    test('Vor dem Initiativewurf läuft kein Kampf', () {
      final scene = Scene([]);

      expect(scene.encounter.isRunning, isFalse);
      expect(scene.encounter.current, isNull);
    });

    test('Jeder Kämpfer würfelt d20 plus seinen Initiative-Bonus', () async {
      final scene = Scene([10, 5]);

      await scene.encounter.rollInitiative();

      expect(scene.aria.initiative, 12);
      expect(scene.goblin.initiative, 6);
    });

    test('Die Reihenfolge geht vom höchsten zum niedrigsten Wert', () async {
      final scene = Scene([3, 15]);

      await scene.encounter.rollInitiative();

      expect(scene.encounter.combatants, [scene.goblin, scene.aria]);
    });

    test('Bei Gleichstand ist der Kämpfer mit dem höheren Initiative-Bonus '
        'zuerst dran', () async {
      // Aria 9 + 2 = 11, Goblin 10 + 1 = 11.
      final scene = Scene([9, 10]);

      await scene.encounter.rollInitiative();

      expect(scene.encounter.combatants, [scene.aria, scene.goblin]);
    });

    test('Nach dem Wurf läuft Runde 1 und der Erste ist am Zug', () async {
      final scene = Scene([10, 5]);

      await scene.encounter.rollInitiative();

      expect(scene.encounter.isRunning, isTrue);
      expect(scene.encounter.round, 1);
      expect(scene.encounter.current, scene.aria);
    });

    test('Ein von Hand eingetragener Würfelwert ersetzt den Wurf der App und '
        'ist im Log als von Hand eingetragen vermerkt', () async {
      final scene = Scene([5]);

      await scene.encounter.rollInitiative(manual: {scene.aria: 18});

      expect(scene.aria.initiative, 20);
      expect(scene.goblin.initiative, 6);
      final event = (await scene.events()).whereType<InitiativeEvent>().single;
      expect(event.entries.first.name, 'Aria');
      expect(event.entries.first.roll.manual, isTrue);
      expect(event.entries.last.roll.manual, isFalse);
    });

    test('Der Initiativewurf steht mit allen Kämpfern in Zugreihenfolge im '
        'Log, danach beginnt Runde 1', () async {
      final scene = Scene([3, 15]);

      await scene.encounter.rollInitiative();

      final events = await scene.events();
      expect(events, hasLength(2));
      final initiative = events.first as InitiativeEvent;
      expect(initiative.entries.map((e) => e.name), ['Goblin', 'Aria']);
      expect(initiative.entries.map((e) => e.roll.total), [16, 5]);
      expect((events.last as RoundEvent).round, 1);
    });
  });

  group('Züge und Runden', () {
    test('"Nächster Zug" gibt an den nächsten Kämpfer weiter', () async {
      final scene = Scene([10, 5]);
      await scene.encounter.rollInitiative();

      await scene.encounter.nextTurn();

      expect(scene.encounter.current, scene.goblin);
      expect(scene.encounter.round, 1);
    });

    test('Nach dem letzten Kämpfer beginnt die nächste Runde beim Ersten '
        'und steht im Log', () async {
      final scene = Scene([10, 5]);
      await scene.encounter.rollInitiative();

      await scene.encounter.nextTurn();
      await scene.encounter.nextTurn();

      expect(scene.encounter.current, scene.aria);
      expect(scene.encounter.round, 2);
      expect((await scene.events()).last, isA<RoundEvent>());
      expect(((await scene.events()).last as RoundEvent).round, 2);
    });

    test('Kämpfer am Boden werden in der Zugfolge übersprungen', () async {
      final scene = Scene([10, 5]);
      final bandit = scene.encounter.add(
        name: 'Bandit',
        armorClass: 12,
        maxHp: 11,
      );
      await scene.encounter.rollInitiative(manual: {bandit: 1});
      scene.goblin.hp = 0;

      await scene.encounter.nextTurn();

      expect(scene.encounter.current, bandit);
    });

    test('"Kampf beenden" setzt Runde und Initiative zurück, die '
        'Trefferpunkte bleiben', () async {
      final scene = Scene([10, 5]);
      await scene.encounter.rollInitiative();
      scene.goblin.hp = 3;

      scene.encounter.end();

      expect(scene.encounter.isRunning, isFalse);
      expect(scene.aria.initiative, isNull);
      expect(scene.goblin.hp, 3);
    });
  });

  group('Angriff: Treffen', () {
    test(
      'Ein Angriffswurf, der die Rüstungsklasse genau erreicht, trifft',
      () async {
        // 8 + 5 = 13 gegen RK 13.
        final outcome = await Scene([8, 4]).ariaAttacksGoblin();

        expect(outcome.attackRoll.total, 13);
        expect(outcome.hit, isTrue);
        expect(outcome.critical, isFalse);
      },
    );

    test('Ein Angriffswurf unter der Rüstungsklasse verfehlt und richtet '
        'keinen Schaden an', () async {
      final scene = Scene([7]);

      final outcome = await scene.ariaAttacksGoblin();

      expect(outcome.hit, isFalse);
      expect(outcome.damage, 0);
      expect(outcome.damageRoll, isNull);
      expect(scene.goblin.hp, 7);
    });

    test('Eine natürliche 1 verfehlt immer, auch wenn der Gesamtwert '
        'reichen würde', () async {
      final scene = Scene([1]);
      scene.goblin.armorClass = 5;

      final outcome = await scene.ariaAttacksGoblin();

      expect(outcome.attackRoll.total, 6);
      expect(outcome.hit, isFalse);
    });

    test('Eine natürliche 20 trifft immer, auch wenn der Gesamtwert nicht '
        'reichen würde, und ist ein kritischer Treffer', () async {
      final scene = Scene([20, 4, 6]);
      scene.goblin.armorClass = 30;

      final outcome = await scene.ariaAttacksGoblin();

      expect(outcome.hit, isTrue);
      expect(outcome.critical, isTrue);
    });

    test('Mit Vorteil zählt der höhere der beiden Angriffswürfel', () async {
      final outcome = await Scene([3, 15, 4])
          .ariaAttacksGoblin(mode: RollMode.advantage);

      expect(outcome.attackRoll.rolls, [3, 15]);
      expect(outcome.hit, isTrue);
    });

    test(
      'Mit Nachteil zählt der niedrigere der beiden Angriffswürfel',
      () async {
        final outcome = await Scene([3, 15])
            .ariaAttacksGoblin(mode: RollMode.disadvantage);

        expect(outcome.hit, isFalse);
      },
    );
  });

  group('Angriff: Schaden', () {
    test('Ein Treffer würfelt die Schadenswürfel plus Schadensbonus und '
        'zieht das Ergebnis von den Trefferpunkten ab', () async {
      final scene = Scene([15, 2]);

      final outcome = await scene.ariaAttacksGoblin();

      expect(outcome.damageRoll!.rolls, [2]);
      expect(outcome.damage, 5);
      expect(scene.goblin.hp, 2);
    });

    test('Ein kritischer Treffer würfelt doppelt so viele Schadenswürfel, '
        'der Schadensbonus zählt nur einmal', () async {
      final scene = Scene([20, 1, 2]);

      final outcome = await scene.ariaAttacksGoblin();

      expect(outcome.damageRoll!.dice, '2d8');
      expect(outcome.damageRoll!.rolls, [1, 2]);
      expect(outcome.damage, 6);
    });

    test('Die Trefferpunkte fallen nie unter 0', () async {
      final scene = Scene([15, 8]);

      final outcome = await scene.ariaAttacksGoblin();

      expect(outcome.damage, 11);
      expect(scene.goblin.hp, 0);
    });

    test('Fällt ein Kämpfer auf 0 Trefferpunkte, geht er zu Boden', () async {
      final scene = Scene([15, 8]);

      final outcome = await scene.ariaAttacksGoblin();

      expect(outcome.targetDown, isTrue);
      expect(scene.goblin.isDown, isTrue);
    });

    test('Ein negativer Schadensbonus kann den Schaden nicht unter 0 '
        'drücken', () async {
      final scene = Scene([15, 1]);
      final weak = Attack(
        name: 'Schwacher Hieb',
        attackBonus: 5,
        damage: DiceExpression.parse('1d4-3'),
        damageType: 'Wucht',
      );

      final outcome = await scene.encounter.attack(
        attacker: scene.aria,
        target: scene.goblin,
        attack: weak,
      );

      expect(outcome.damage, 0);
      expect(scene.goblin.hp, 7);
    });
  });

  group('Angriff: von Hand eingetragene Würfe', () {
    test('Ein eingetragener Angriffswurf ersetzt den d20 der App', () async {
      final scene = Scene([4]);

      final outcome = await scene.ariaAttacksGoblin(manualAttackRoll: 12);

      expect(outcome.attackRoll.rolls, [12]);
      expect(outcome.attackRoll.manual, isTrue);
      expect(outcome.attackRoll.total, 17);
      expect(outcome.damageRoll!.manual, isFalse);
    });

    test('Eine eingetragene 20 ist ein kritischer Treffer', () async {
      final outcome = await Scene([1, 2])
          .ariaAttacksGoblin(manualAttackRoll: 20);

      expect(outcome.critical, isTrue);
    });

    test('Eine eingetragene Augensumme ersetzt die Schadenswürfel, der '
        'Schadensbonus kommt dazu', () async {
      final scene = Scene([15]);

      final outcome = await scene.ariaAttacksGoblin(manualDamage: 6);

      expect(outcome.damageRoll!.manual, isTrue);
      expect(outcome.damage, 9);
      expect(scene.goblin.hp, 0);
    });

    test('Ein Angriffswurf außerhalb von 1 bis 20 wird abgelehnt und ändert '
        'nichts', () async {
      final scene = Scene([]);

      await expectLater(
        scene.ariaAttacksGoblin(manualAttackRoll: 21),
        throwsArgumentError,
      );
      await expectLater(
        scene.ariaAttacksGoblin(manualAttackRoll: 0),
        throwsArgumentError,
      );
      expect(scene.goblin.hp, 7);
      expect(await scene.events(), isEmpty);
    });

    test('Eine Augensumme, die mit den Schadenswürfeln nicht möglich ist, '
        'wird abgelehnt und ändert nichts', () async {
      final scene = Scene([15, 15]);

      // 1d8 kann 1 bis 8 zeigen.
      await expectLater(
        scene.ariaAttacksGoblin(manualDamage: 9),
        throwsArgumentError,
      );
      await expectLater(
        scene.ariaAttacksGoblin(manualDamage: 0),
        throwsArgumentError,
      );
      expect(scene.goblin.hp, 7);
      expect(await scene.events(), isEmpty);
    });

    test('Bei einem kritischen Treffer darf die Augensumme bis zum '
        'Doppelten reichen', () async {
      final outcome = await Scene([])
          .ariaAttacksGoblin(manualAttackRoll: 20, manualDamage: 16);

      expect(outcome.damage, 19);
    });
  });

  group('Angriff: Log', () {
    test('Ein Treffer steht mit Angreifer, Ziel, Angriff, Würfen und '
        'Schaden im Log', () async {
      final scene = Scene([15, 2]);

      await scene.ariaAttacksGoblin();

      final event = (await scene.events()).single as AttackEvent;
      expect(event.attackerName, 'Aria');
      expect(event.targetName, 'Goblin');
      expect(event.attackName, 'Langschwert');
      expect(event.targetArmorClass, 13);
      expect(event.hit, isTrue);
      expect(event.attackRoll.total, 20);
      expect(event.damageRoll!.total, 5);
      expect(event.damage, 5);
      expect(event.damageType, 'Hieb');
    });

    test('Ein Fehlschlag steht ohne Schaden im Log', () async {
      final scene = Scene([2]);

      await scene.ariaAttacksGoblin();

      final event = (await scene.events()).single as AttackEvent;
      expect(event.hit, isFalse);
      expect(event.damageRoll, isNull);
    });

    test('Geht das Ziel zu Boden, folgt ein eigener Log-Eintrag', () async {
      final scene = Scene([15, 8]);

      await scene.ariaAttacksGoblin();

      final events = await scene.events();
      expect(events.first, isA<AttackEvent>());
      expect((events.last as CombatantDownEvent).name, 'Goblin');
    });
  });
}
