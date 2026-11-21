import 'package:dmployee/combat/attack.dart';
import 'package:dmployee/combat/buff.dart';
import 'package:dmployee/combat/combatant.dart';
import 'package:dmployee/combat/damage.dart';
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
    int? manualDamage,
    Map<Buff, int> manualBuffRolls = const {},
    Map<Buff, int> manualBuffDamage = const {},
    Set<Buff> ignoredBuffs = const {},
  }) => encounter.attack(
    attacker: aria,
    target: ogre,
    attack: longsword,
    manualAttackRoll: manualAttackRoll,
    manualDamage: manualDamage,
    manualBuffRolls: manualBuffRolls,
    manualBuffDamage: manualBuffDamage,
    ignoredBuffs: ignoredBuffs,
  );

  /// Mal des Jägers: +1d6 damage of the attack's own type.
  Future<Buff> huntersMark(Combatant combatant) => encounter.addBuff(
    combatant,
    name: 'Mal des Jägers',
    damageBonus: Bonus.parse('1d6'),
  );

  /// Verhexen: +1d6 necrotic damage.
  Future<Buff> hex(Combatant combatant) => encounter.addBuff(
    combatant,
    name: 'Verhexen',
    damageBonus: Bonus.parse('1d6'),
    damageType: 'Nekrotisch',
  );

  /// Kampfrausch: +2 damage, no dice.
  Future<Buff> rage(Combatant combatant) => encounter.addBuff(
    combatant,
    name: 'Kampfrausch',
    damageBonus: Bonus.parse('2'),
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

  group('Effekte: Bonus auf den Schaden', () {
    test('Ein Bonuswürfel ohne eigene Schadensart wird nach den '
        'Schadenswürfeln gewürfelt und zum Waffenschaden addiert', () async {
      // d20 10 hits; d8 4, bonus d6 5: 4 + 3 + 5 = 12.
      final scene = Scene([10, 4, 5]);
      await scene.huntersMark(scene.aria);

      final outcome = await scene.ariaAttacksOgre();

      expect(outcome.damage, 12);
      expect(outcome.damageRoll!.modifiers, [
        Modifier('Schadensbonus', 3),
        Modifier('Mal des Jägers (1d6)', 5),
      ]);
      expect(outcome.event.extraDamage, isEmpty);
      expect(scene.ogre.hp, 47);
    });

    test('Ein fester Bonus wird ohne Wurf zum Schaden addiert', () async {
      final scene = Scene([10, 4]);
      await scene.rage(scene.aria);

      final outcome = await scene.ariaAttacksOgre();

      expect(outcome.damage, 9);
      expect(outcome.damageRoll!.modifiers.last, Modifier('Kampfrausch', 2));
    });

    test('Ein Abzug verringert den Schaden, aber nie unter 0', () async {
      // d8 1: 1 + 3 - 6 would be -2.
      final scene = Scene([10, 1]);
      await scene.encounter.addBuff(
        scene.aria,
        name: 'Geschwächt',
        damageBonus: Bonus.parse('-6'),
      );

      final outcome = await scene.ariaAttacksOgre();

      expect(outcome.damage, 0);
      expect(scene.ogre.hp, 59);
    });

    test('Ein kritischer Treffer verdoppelt die Bonuswürfel, aber nicht den '
        'festen Bonus', () async {
      // d20 20; 2d8 4 + 3; bonus 2d6 5 + 6: 7 + 3 + 11 + 2 = 23.
      final scene = Scene([20, 4, 3, 5, 6]);
      await scene.huntersMark(scene.aria);
      await scene.rage(scene.aria);

      final outcome = await scene.ariaAttacksOgre();

      expect(outcome.damage, 23);
      expect(outcome.damageRoll!.modifiers, [
        Modifier('Schadensbonus', 3),
        Modifier('Mal des Jägers (2d6)', 11),
        Modifier('Kampfrausch', 2),
      ]);
    });

    test('Ein Bonus mit eigener Schadensart wird getrennt vom Waffenschaden '
        'festgehalten', () async {
      // d8 4 + 3 = 7 Hieb, d6 5 Nekrotisch.
      final scene = Scene([10, 4, 5]);
      await scene.hex(scene.aria);

      final outcome = await scene.ariaAttacksOgre();

      expect(outcome.damage, 12);
      expect(outcome.damageRoll!.total, 7);
      final extra = outcome.event.extraDamage.single;
      expect(extra.damageType, 'Nekrotisch');
      expect(extra.modifiers, [Modifier('Verhexen (1d6)', 5)]);
      expect(extra.damage, 5);
    });

    test('Resistenzen wirken je Schadensart getrennt', () async {
      // 7 Hieb + 5 Nekrotisch, Resistenz gegen Nekrotisch: 7 + 2 = 9.
      final necrotic = Scene([10, 4, 5]);
      await necrotic.hex(necrotic.aria);
      necrotic.encounter.setDamageTrait(
        necrotic.ogre,
        'Nekrotisch',
        DamageEffect.resistance,
      );
      final outcome = await necrotic.ariaAttacksOgre();
      expect(outcome.damage, 9);
      expect(outcome.damageEffect, isNull);
      expect(
        outcome.event.extraDamage.single.damageEffect,
        DamageEffect.resistance,
      );

      // Resistenz gegen Hieb: 3 + 5 = 8.
      final slashing = Scene([10, 4, 5]);
      await slashing.hex(slashing.aria);
      slashing.encounter.setDamageTrait(
        slashing.ogre,
        'Hieb',
        DamageEffect.resistance,
      );
      expect((await slashing.ariaAttacksOgre()).damage, 8);
    });

    test('Ein Bonus mit derselben Schadensart wie der Angriff zählt zum '
        'Waffenschaden; die Resistenz halbiert die Summe', () async {
      // 4 + 3 + 5 = 12 Hieb, halbiert 6 (getrennt halbiert wären es 5).
      final scene = Scene([10, 4, 5]);
      await scene.encounter.addBuff(
        scene.aria,
        name: 'Mal des Jägers',
        damageBonus: Bonus.parse('1d6'),
        damageType: 'hieb',
      );
      scene.encounter.setDamageTrait(
        scene.ogre,
        'Hieb',
        DamageEffect.resistance,
      );

      final outcome = await scene.ariaAttacksOgre();

      expect(outcome.damage, 6);
      expect(outcome.event.extraDamage, isEmpty);
    });

    test('Bei einem Fehlschlag wird kein Bonusschaden gewürfelt', () async {
      final scene = Scene([2]);
      await scene.hex(scene.aria);

      final outcome = await scene.ariaAttacksOgre();

      expect(outcome.damage, 0);
      expect(outcome.event.extraDamage, isEmpty);
    });

    test('Am Tisch gewürfelte Bonuswürfel für den Schaden lassen sich von '
        'Hand eintragen', () async {
      final scene = Scene([]);
      final mark = await scene.huntersMark(scene.aria);

      final outcome = await scene.ariaAttacksOgre(
        manualAttackRoll: 15,
        manualDamage: 4,
        manualBuffDamage: {mark: 6},
      );

      expect(outcome.damage, 13);
      expect(
        outcome.damageRoll!.modifiers.last,
        Modifier('Mal des Jägers (1d6 von Hand)', 6),
      );
    });

    test('Bei einem kritischen Treffer gilt für eingetragene Bonuswürfel '
        'die doppelte Anzahl', () async {
      final scene = Scene([]);
      final mark = await scene.huntersMark(scene.aria);

      final outcome = await scene.ariaAttacksOgre(
        manualAttackRoll: 20,
        manualDamage: 9,
        manualBuffDamage: {mark: 11},
      );

      expect(
        outcome.damageRoll!.modifiers.last,
        Modifier('Mal des Jägers (2d6 von Hand)', 11),
      );
    });

    test('Ein eingetragener Bonuswürfel, den die Würfel nicht zeigen können, '
        'wird abgelehnt und ändert nichts', () async {
      final scene = Scene([]);
      final mark = await scene.huntersMark(scene.aria);
      final before = (await scene.events()).length;

      expect(
        () => scene.ariaAttacksOgre(
          manualAttackRoll: 15,
          manualDamage: 4,
          manualBuffDamage: {mark: 7},
        ),
        throwsArgumentError,
      );
      expect(scene.ogre.hp, 59);
      expect(await scene.events(), hasLength(before));
    });

    test('Der Schadensbonus des Ziels verändert den Schaden des Angreifers '
        'nicht', () async {
      final scene = Scene([10, 4]);
      await scene.rage(scene.ogre);

      expect((await scene.ariaAttacksOgre()).damage, 7);
    });
  });

  group('Effekte im Angriff abwählen', () {
    test('Ein abgewählter Effekt bringt weder Angriffs- noch Schadensbonus '
        'und es wird nichts für ihn gewürfelt', () async {
      // Only d20 10 and d8 4 are rolled.
      final scene = Scene([10, 4]);
      final blessing = await scene.bless(scene.aria);
      final mark = await scene.huntersMark(scene.aria);

      final outcome = await scene.ariaAttacksOgre(
        ignoredBuffs: {blessing, mark},
      );

      expect(outcome.attackRoll.modifiers, [Modifier('Angriffsbonus', 5)]);
      expect(outcome.damage, 7);
    });

    test('Nicht abgewählte Effekte wirken weiter', () async {
      final scene = Scene([10, 4]);
      final mark = await scene.huntersMark(scene.aria);
      await scene.rage(scene.aria);

      final outcome = await scene.ariaAttacksOgre(ignoredBuffs: {mark});

      expect(outcome.damage, 9);
    });
  });

  group('Effekte: Bonus auf Rettungswürfe', () {
    Future<Combatant> dyingPlayer(Scene scene) async {
      final hero = scene.encounter.add(
        name: 'Borin',
        armorClass: 15,
        maxHp: 12,
        isPlayer: true,
      );
      await scene.encounter.damage(hero, 12);
      return hero;
    }

    Future<Buff> blessSaves(Scene scene, Combatant combatant) =>
        scene.encounter.addBuff(
          combatant,
          name: 'Segen',
          attackBonus: Bonus.parse('1d4'),
          saveBonus: Bonus.parse('1d4'),
        );

    test('Ein Bonuswürfel wird vor dem d20 gewürfelt und zum '
        'Todesrettungswurf addiert', () async {
      // Bonus die 3, d20 8: 11 is a success.
      final scene = Scene([3, 8]);
      final hero = await dyingPlayer(scene);
      await blessSaves(scene, hero);

      final event = await scene.encounter.rollDeathSave(hero);

      expect(event.roll.total, 11);
      expect(event.roll.modifiers, [Modifier('Segen (1d4)', 3)]);
      expect(hero.deathSaveSuccesses, 1);
    });

    test('Ein fester Bonus wird ohne Wurf addiert', () async {
      final scene = Scene([8]);
      final hero = await dyingPlayer(scene);
      await scene.encounter.addBuff(
        hero,
        name: 'Aura des Schutzes',
        saveBonus: Bonus.parse('2'),
      );

      final event = await scene.encounter.rollDeathSave(hero);

      expect(event.roll.total, 10);
      expect(hero.deathSaveSuccesses, 1);
    });

    test('Eine natürliche 1 zählt trotz Bonus als zwei Fehlschläge', () async {
      final scene = Scene([4, 1]);
      final hero = await dyingPlayer(scene);
      await blessSaves(scene, hero);

      await scene.encounter.rollDeathSave(hero);

      expect(hero.deathSaveFailures, 2);
    });

    test('Ein Effekt nur auf Angriffswürfe ändert den Rettungswurf '
        'nicht', () async {
      final scene = Scene([9]);
      final hero = await dyingPlayer(scene);
      await scene.bless(hero);

      final event = await scene.encounter.rollDeathSave(hero);

      expect(event.roll.total, 9);
      expect(hero.deathSaveFailures, 1);
    });

    test('Ein am Tisch gewürfelter Bonuswürfel lässt sich von Hand '
        'eintragen', () async {
      final scene = Scene([]);
      final hero = await dyingPlayer(scene);
      final blessing = await blessSaves(scene, hero);

      final event = await scene.encounter.rollDeathSave(
        hero,
        manualRoll: 8,
        manualBuffRolls: {blessing: 2},
      );

      expect(event.roll.total, 10);
      expect(event.roll.modifiers, [Modifier('Segen (1d4 von Hand)', 2)]);
    });

    test('Ein eingetragener Bonuswürfel, den der Würfel nicht zeigen kann, '
        'wird abgelehnt und ändert nichts', () async {
      final scene = Scene([]);
      final hero = await dyingPlayer(scene);
      final blessing = await blessSaves(scene, hero);
      final before = (await scene.events()).length;

      expect(
        () => scene.encounter.rollDeathSave(
          hero,
          manualRoll: 8,
          manualBuffRolls: {blessing: 5},
        ),
        throwsArgumentError,
      );
      expect(hero.deathSaveSuccesses, 0);
      expect(await scene.events(), hasLength(before));
    });
  });

  group('Effekte auf Schaden und Rettungswürfe: Anzeige, Log und '
      'Speichern', () {
    test('Die Kurzform nennt Schadens- und Rettungswurfbonus', () async {
      final scene = Scene([]);

      final hex = await scene.hex(scene.aria);
      final blessing = await scene.encounter.addBuff(
        scene.aria,
        name: 'Segen',
        attackBonus: Bonus.parse('1d4'),
        saveBonus: Bonus.parse('1d4'),
        rounds: 10,
      );

      expect(hex.summary, 'Verhexen: Schaden +1d6 Nekrotisch');
      expect(blessing.summary, 'Segen: Angriff +1d4, Rettungswurf +1d4 (10)');
      expect(
        (await scene.huntersMark(scene.aria)).summary,
        'Mal des Jägers: Schaden +1d6',
      );
    });

    test('Beim Vergeben stehen Schadens- und Rettungswurfbonus im '
        'Log', () async {
      final scene = Scene([]);
      await scene.hex(scene.aria);
      await scene.encounter.addBuff(
        scene.aria,
        name: 'Segen',
        saveBonus: Bonus.parse('1d4'),
      );

      final events = (await scene.events()).whereType<BuffEvent>().toList();
      expect(events.first.damageBonus, '+1d6');
      expect(events.first.damageType, 'Nekrotisch');
      expect(events.last.saveBonus, '+1d4');
    });

    test('Eine leere Schadensart zählt als die des Angriffs', () async {
      final scene = Scene([]);

      final buff = await scene.encounter.addBuff(
        scene.aria,
        name: 'Mal des Jägers',
        damageBonus: Bonus.parse('1d6'),
        damageType: '  ',
      );

      expect(buff.damageType, isNull);
    });

    test('Schadens- und Rettungswurfbonus kommen nach dem Neustart '
        'zurück', () async {
      final scene = Scene([]);
      await scene.hex(scene.aria);
      await scene.encounter.addBuff(
        scene.aria,
        name: 'Segen',
        saveBonus: Bonus.parse('1d4'),
      );
      await scene.encounter.flush();

      final restored = await Encounter.load(log: scene.log, store: scene.store);

      final buffs = restored.combatants.first.buffs;
      expect('${buffs.first.damageBonus}', '+1d6');
      expect(buffs.first.damageType, 'Nekrotisch');
      expect('${buffs.last.saveBonus}', '+1d4');
    });

    test('Ein Effekt aus einem älteren Stand ohne diese Angaben lässt sich '
        'laden', () {
      final buff = Buff.fromJson({
        'name': 'Segen',
        'attackBonus': '+1d4',
        'armorClassBonus': 0,
      });

      expect(buff.damageBonus, isNull);
      expect(buff.damageType, isNull);
      expect(buff.saveBonus, isNull);
    });
  });
}
