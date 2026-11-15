import 'package:dmployee/combat/attack.dart';
import 'package:dmployee/combat/buff.dart';
import 'package:dmployee/combat/combatant.dart';
import 'package:dmployee/combat/encounter.dart';
import 'package:dmployee/combat/encounter_store.dart';
import 'package:dmployee/dice/dice_expression.dart';
import 'package:dmployee/dice/dice_roller.dart';
import 'package:dmployee/dice/modifier.dart';
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

/// An encounter whose dice show the given [faces] in order, with Aria
/// (RK 16, 20 TP, Initiative +2, Langschwert +5, 1d8+3 Hieb) and an Oger
/// (RK 11, 59 TP). Aria hits the Oger with a d20 of 6 or more.
class Scene {
  Scene(List<int> faces) {
    encounter = Encounter(
      log: log,
      store: store,
      roller: DiceRoller(FixedRandom(faces)),
    );
    aria = encounter.add(
      name: 'Aria',
      armorClass: 16,
      maxHp: 20,
      initiativeBonus: 2,
      attacks: [longsword],
    );
    ogre = encounter.add(name: 'Oger', armorClass: 11, maxHp: 59);
  }

  final log = InMemoryLogRepository();
  final store = InMemoryEncounterStore();
  late final Encounter encounter;
  late final Combatant aria;
  late final Combatant ogre;

  Future<List<LogEvent>> events() async =>
      (await log.entries()).reversed.map((entry) => entry.event).toList();

  Future<AttackOutcome> ariaAttacksOgre({
    int? manualAttackRoll,
    Map<Buff, int> manualBuffRolls = const {},
  }) => encounter.attack(
    attacker: aria,
    target: ogre,
    attack: longsword,
    manualAttackRoll: manualAttackRoll,
    manualBuffRolls: manualBuffRolls,
  );

  Future<Buff> bless(Combatant combatant, {int? rounds}) => encounter.addBuff(
    combatant,
    name: 'Segen',
    attackBonus: Bonus.parse('1d4'),
    rounds: rounds,
  );
}

void main() {
  group('Bonus eines Effekts lesen', () {
    test('Ein Würfel wie "1d4" wird als Bonuswürfel gelesen', () {
      final bonus = Bonus.parse('1d4');

      expect(bonus.isDice, isTrue);
      expect(bonus.negative, isFalse);
      expect('$bonus', '+1d4');
    });

    test('Ein Minus davor macht daraus einen Abzug', () {
      final bonus = Bonus.parse('-1d4');

      expect(bonus.negative, isTrue);
      expect('$bonus', '-1d4');
    });

    test('Feste Werte wie "2", "+2" und "-1" werden gelesen', () {
      expect('${Bonus.parse('2')}', '+2');
      expect('${Bonus.parse('+2')}', '+2');
      expect('${Bonus.parse('-1')}', '-1');
      expect(Bonus.parse('2').isDice, isFalse);
    });

    test('Die deutsche Schreibweise "1W4" und Leerzeichen sind erlaubt', () {
      expect('${Bonus.parse(' + 1W4 ')}', '+1d4');
    });

    test('Unlesbare Eingaben und 0 werden abgelehnt', () {
      expect(() => Bonus.parse('viel'), throwsFormatException);
      expect(() => Bonus.parse(''), throwsFormatException);
      expect(() => Bonus.parse('0'), throwsFormatException);
      expect(() => Bonus.parse('1d4+2'), throwsFormatException);
    });
  });

  group('Effekte: verwalten', () {
    test('Ein Effekt lässt sich einem Kämpfer geben', () async {
      final scene = Scene([]);

      final buff = await scene.bless(scene.aria);

      expect(scene.aria.buffs, [buff]);
      expect(buff.name, 'Segen');
      expect(buff.roundsLeft, isNull);
    });

    test('Ein Effekt gleichen Namens wirkt nur einmal: der neue ersetzt den '
        'alten', () async {
      final scene = Scene([]);
      await scene.bless(scene.aria);

      await scene.encounter.addBuff(
        scene.aria,
        name: 'segen',
        attackBonus: Bonus.parse('1d4'),
        rounds: 10,
      );

      expect(scene.aria.buffs, hasLength(1));
      expect(scene.aria.buffs.single.roundsLeft, 10);
    });

    test('Ein Effekt lässt sich wieder entfernen', () async {
      final scene = Scene([]);
      final buff = await scene.bless(scene.aria);

      await scene.encounter.removeBuff(scene.aria, buff);

      expect(scene.aria.buffs, isEmpty);
    });

    test('Ein Effekt ohne Namen oder mit einer Dauer unter 1 Runde wird '
        'abgelehnt', () async {
      final scene = Scene([]);

      expect(
        () => scene.encounter.addBuff(scene.aria, name: '  '),
        throwsArgumentError,
      );
      expect(
        () => scene.encounter.addBuff(scene.aria, name: 'Segen', rounds: 0),
        throwsArgumentError,
      );
      expect(scene.aria.buffs, isEmpty);
      expect(await scene.events(), isEmpty);
    });

    test('Ein Effekt ohne Zahlenwerte ist als reine Markierung '
        'erlaubt', () async {
      final scene = Scene([]);

      final buff = await scene.encounter.addBuff(
        scene.aria,
        name: 'Konzentration',
      );

      expect(buff.attackBonus, isNull);
      expect(buff.armorClassBonus, 0);
    });
  });

  group('Effekte: Bonus auf den Angriffswurf', () {
    test('Ein Bonuswürfel wird gewürfelt und zum Angriffswurf '
        'addiert', () async {
      // Bonus die 3, then d20 2: 2 + 5 + 3 = 10 misses RK 11.
      final scene = Scene([3, 2]);
      await scene.bless(scene.aria);

      final outcome = await scene.ariaAttacksOgre();

      expect(outcome.attackRoll.total, 10);
      expect(outcome.attackRoll.modifiers, [
        Modifier('Angriffsbonus', 5),
        Modifier('Segen (1d4)', 3),
      ]);
      expect(outcome.hit, isFalse);
    });

    test('Der Bonuswürfel kann aus einem Fehlschlag einen Treffer '
        'machen', () async {
      // Bonus die 4, d20 2: 2 + 5 + 4 = 11 hits RK 11; damage die 1.
      final scene = Scene([4, 2, 1]);
      await scene.bless(scene.aria);

      expect((await scene.ariaAttacksOgre()).hit, isTrue);
    });

    test('Ein Abzugswürfel wird vom Angriffswurf abgezogen', () async {
      // Penalty die 4, d20 9: 9 + 5 - 4 = 10 misses RK 11.
      final scene = Scene([4, 9]);
      await scene.encounter.addBuff(
        scene.aria,
        name: 'Verderben',
        attackBonus: Bonus.parse('-1d4'),
      );

      final outcome = await scene.ariaAttacksOgre();

      expect(outcome.attackRoll.total, 10);
      expect(
        outcome.attackRoll.modifiers.last,
        Modifier('Verderben (1d4)', -4),
      );
    });

    test('Ein fester Bonus wird ohne Wurf addiert', () async {
      final scene = Scene([4]);
      await scene.encounter.addBuff(
        scene.aria,
        name: 'Magische Waffe',
        attackBonus: Bonus.parse('+1'),
      );

      final outcome = await scene.ariaAttacksOgre();

      expect(outcome.attackRoll.total, 10);
      expect(outcome.attackRoll.modifiers.last, Modifier('Magische Waffe', 1));
    });

    test('Eine natürliche 1 verfehlt trotz Bonus', () async {
      final scene = Scene([4, 1]);
      await scene.bless(scene.aria);

      expect((await scene.ariaAttacksOgre()).hit, isFalse);
    });

    test('Ein am Tisch gewürfelter Bonuswürfel lässt sich von Hand '
        'eintragen', () async {
      final scene = Scene([]);
      final buff = await scene.bless(scene.aria);

      final outcome = await scene.ariaAttacksOgre(
        manualAttackRoll: 3,
        manualBuffRolls: {buff: 2},
      );

      expect(outcome.attackRoll.total, 10);
      expect(
        outcome.attackRoll.modifiers.last,
        Modifier('Segen (1d4 von Hand)', 2),
      );
    });

    test('Ein eingetragener Bonuswürfel, den der Würfel nicht zeigen kann, '
        'wird abgelehnt und ändert nichts', () async {
      final scene = Scene([]);
      final buff = await scene.bless(scene.aria);
      final before = (await scene.events()).length;

      expect(
        () => scene.ariaAttacksOgre(
          manualAttackRoll: 15,
          manualBuffRolls: {buff: 5},
        ),
        throwsArgumentError,
      );
      expect(scene.ogre.hp, 59);
      expect(await scene.events(), hasLength(before));
    });

    test('Der Effekt des Ziels verändert den Angriffswurf des Angreifers '
        'nicht', () async {
      final scene = Scene([2]);
      await scene.bless(scene.ogre);

      expect((await scene.ariaAttacksOgre()).attackRoll.total, 7);
    });
  });

  group('Effekte: Bonus auf die Rüstungsklasse', () {
    test('Ein Bonus erhöht die wirksame Rüstungsklasse', () async {
      final scene = Scene([]);

      await scene.encounter.addBuff(
        scene.ogre,
        name: 'Schild des Glaubens',
        armorClassBonus: 2,
      );

      expect(scene.ogre.armorClass, 11);
      expect(scene.ogre.effectiveArmorClass, 13);
    });

    test('Der Angriff muss die wirksame Rüstungsklasse erreichen', () async {
      // d20 7: 7 + 5 = 12 would hit RK 11 but misses RK 13.
      final scene = Scene([7]);
      await scene.encounter.addBuff(
        scene.ogre,
        name: 'Schild des Glaubens',
        armorClassBonus: 2,
      );

      expect((await scene.ariaAttacksOgre()).hit, isFalse);
    });

    test('Ein Abzug senkt die wirksame Rüstungsklasse', () async {
      final scene = Scene([]);

      await scene.encounter.addBuff(
        scene.aria,
        name: 'Verlangsamt',
        armorClassBonus: -2,
      );

      expect(scene.aria.effectiveArmorClass, 14);
    });

    test('Nach dem Entfernen gilt wieder die normale '
        'Rüstungsklasse', () async {
      final scene = Scene([]);
      final buff = await scene.encounter.addBuff(
        scene.ogre,
        name: 'Schild des Glaubens',
        armorClassBonus: 2,
      );

      await scene.encounter.removeBuff(scene.ogre, buff);

      expect(scene.ogre.effectiveArmorClass, 11);
    });
  });

  group('Effekte: Dauer in Runden', () {
    test('Die Dauer sinkt am Ende jedes Zugs des Kämpfers; bei 0 endet der '
        'Effekt', () async {
      final scene = Scene([10, 5]);
      await scene.encounter.rollInitiative();
      await scene.bless(scene.aria, rounds: 2);

      await scene.encounter.nextTurn(); // Aria's first turn ends.
      expect(scene.aria.buffs.single.roundsLeft, 1);

      await scene.encounter.nextTurn();
      await scene.encounter.nextTurn(); // Aria's second turn ends.
      expect(scene.aria.buffs, isEmpty);
    });

    test('Ein Effekt ohne Dauer bleibt, bis er entfernt wird', () async {
      final scene = Scene([10, 5]);
      await scene.encounter.rollInitiative();
      await scene.bless(scene.aria);

      for (var i = 0; i < 8; i++) {
        await scene.encounter.nextTurn();
      }

      expect(scene.aria.buffs, hasLength(1));
    });
  });

  group('Effekte: Log und Speichern', () {
    test('Vergeben, Entfernen und Ablaufen stehen im Log', () async {
      final scene = Scene([10, 5]);
      await scene.encounter.rollInitiative();

      final shield = await scene.encounter.addBuff(
        scene.ogre,
        name: 'Schild des Glaubens',
        armorClassBonus: 2,
      );
      await scene.encounter.removeBuff(scene.ogre, shield);
      await scene.bless(scene.aria, rounds: 1);
      await scene.encounter.nextTurn();

      final events = (await scene.events()).whereType<BuffEvent>().toList();
      expect(events.map((e) => e.change), [
        EffectChange.added,
        EffectChange.removed,
        EffectChange.added,
        EffectChange.expired,
      ]);
      expect(events.first.name, 'Oger');
      expect(events.first.buff, 'Schild des Glaubens');
      expect(events.first.armorClassBonus, 2);
      expect(events[2].attackBonus, '+1d4');
      expect(events[2].rounds, 1);
    });

    test('Der Angriff hält im Log fest, woraus sich die Rüstungsklasse des '
        'Ziels zusammensetzt', () async {
      final scene = Scene([7]);
      await scene.encounter.addBuff(
        scene.ogre,
        name: 'Schild des Glaubens',
        armorClassBonus: 2,
      );

      await scene.ariaAttacksOgre();

      final event = (await scene.events()).last as AttackEvent;
      expect(event.targetArmorClass, 13);
      expect(event.armorClassModifiers, [Modifier('Schild des Glaubens', 2)]);
    });

    test('Effekte kommen mit Bonus und Restdauer nach dem Neustart '
        'zurück', () async {
      final scene = Scene([]);
      await scene.bless(scene.aria, rounds: 10);
      await scene.encounter.addBuff(
        scene.aria,
        name: 'Schild des Glaubens',
        armorClassBonus: 2,
      );
      await scene.encounter.flush();

      final restored = await Encounter.load(log: scene.log, store: scene.store);

      final aria = restored.combatants.first;
      expect(aria.buffs.map((b) => b.name), ['Segen', 'Schild des Glaubens']);
      expect('${aria.buffs.first.attackBonus}', '+1d4');
      expect(aria.buffs.first.roundsLeft, 10);
      expect(aria.buffs.last.armorClassBonus, 2);
      expect(aria.effectiveArmorClass, 18);
    });
  });
}
