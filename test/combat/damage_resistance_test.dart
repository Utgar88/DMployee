import 'package:dmployee/combat/attack.dart';
import 'package:dmployee/combat/combatant.dart';
import 'package:dmployee/combat/damage.dart';
import 'package:dmployee/combat/encounter.dart';
import 'package:dmployee/combat/encounter_store.dart';
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

/// An encounter whose dice show the given [faces] in order, with the player
/// character Aria (RK 16, 20 TP, Langschwert 1d8+3 Hieb) and an Oger
/// (RK 11, 59 TP).
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
      isPlayer: true,
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

  /// Attack roll 15 hits; the damage die shows [damageDie], so the attack
  /// deals `damageDie + 3` before resistances.
  Future<AttackOutcome> ariaHitsOgre() =>
      encounter.attack(attacker: aria, target: ogre, attack: longsword);
}

void main() {
  group('Schadensarten', () {
    test('Die 13 Schadensarten der 5e-Regeln stehen zur Auswahl', () {
      expect(damageTypes, hasLength(13));
      expect(damageTypes, containsAll(['Feuer', 'Hieb', 'Stich', 'Wucht']));
    });
  });

  group('Resistenz, Anfälligkeit und Immunität: Angriff', () {
    test('Ohne Eintrag wirkt der volle Schaden', () async {
      final scene = Scene([15, 6]);

      final outcome = await scene.ariaHitsOgre();

      expect(outcome.damage, 9);
      expect(outcome.damageEffect, isNull);
      expect(scene.ogre.hp, 50);
    });

    test('Resistenz halbiert den Schaden und rundet ab', () async {
      final scene = Scene([15, 6]);
      scene.encounter.setDamageTrait(
        scene.ogre,
        'Hieb',
        DamageEffect.resistance,
      );

      final outcome = await scene.ariaHitsOgre();

      expect(outcome.damage, 4);
      expect(outcome.damageEffect, DamageEffect.resistance);
      expect(scene.ogre.hp, 55);
    });

    test('Anfälligkeit verdoppelt den Schaden', () async {
      final scene = Scene([15, 6]);
      scene.encounter.setDamageTrait(
        scene.ogre,
        'Hieb',
        DamageEffect.vulnerability,
      );

      final outcome = await scene.ariaHitsOgre();

      expect(outcome.damage, 18);
      expect(scene.ogre.hp, 41);
    });

    test('Immunität verhindert den Schaden ganz', () async {
      final scene = Scene([15, 6]);
      scene.encounter.setDamageTrait(scene.ogre, 'Hieb', DamageEffect.immunity);

      final outcome = await scene.ariaHitsOgre();

      expect(outcome.hit, isTrue);
      expect(outcome.damage, 0);
      expect(scene.ogre.hp, 59);
    });

    test('Ein Eintrag für eine andere Schadensart wirkt nicht', () async {
      final scene = Scene([15, 6]);
      scene.encounter.setDamageTrait(
        scene.ogre,
        'Feuer',
        DamageEffect.immunity,
      );

      final outcome = await scene.ariaHitsOgre();

      expect(outcome.damage, 9);
      expect(outcome.damageEffect, isNull);
    });

    test('Groß- und Kleinschreibung der Schadensart spielt keine '
        'Rolle', () async {
      final scene = Scene([15, 6]);
      scene.encounter.setDamageTrait(
        scene.ogre,
        ' hieb ',
        DamageEffect.resistance,
      );

      expect((await scene.ariaHitsOgre()).damage, 4);
    });

    test('Bei einem kritischen Treffer wird erst verdoppelt gewürfelt, '
        'dann halbiert', () async {
      // Natural 20, damage dice 6 and 5: 11 + 3 = 14, halved to 7.
      final scene = Scene([20, 6, 5]);
      scene.encounter.setDamageTrait(
        scene.ogre,
        'Hieb',
        DamageEffect.resistance,
      );

      expect((await scene.ariaHitsOgre()).damage, 7);
    });

    test('Pro Schadensart gilt ein Eintrag: ein neuer ersetzt den '
        'bisherigen, ohne Angabe wird er gelöscht', () async {
      final scene = Scene([]);
      final encounter = scene.encounter;

      encounter.setDamageTrait(scene.ogre, 'Feuer', DamageEffect.resistance);
      encounter.setDamageTrait(scene.ogre, 'feuer', DamageEffect.immunity);
      expect(scene.ogre.damageTraits, {'Feuer': DamageEffect.immunity});

      encounter.setDamageTrait(scene.ogre, 'Feuer', null);
      expect(scene.ogre.damageTraits, isEmpty);
    });
  });

  group('Resistenz, Anfälligkeit und Immunität: direkter Schaden', () {
    test('Mit Schadensart wirkt die Resistenz auch bei direkt eingetragenem '
        'Schaden', () async {
      final scene = Scene([]);
      scene.encounter.setDamageTrait(
        scene.ogre,
        'Feuer',
        DamageEffect.resistance,
      );

      await scene.encounter.damage(scene.ogre, 15, damageType: 'Feuer');

      expect(scene.ogre.hp, 52);
    });

    test('Ohne Schadensart wirkt direkt eingetragener Schaden voll', () async {
      final scene = Scene([]);
      scene.encounter.setDamageTrait(
        scene.ogre,
        'Feuer',
        DamageEffect.immunity,
      );

      await scene.encounter.damage(scene.ogre, 15);

      expect(scene.ogre.hp, 44);
    });

    test('Heilung wird von Resistenzen nicht verändert', () async {
      final scene = Scene([]);
      await scene.encounter.damage(scene.ogre, 30);
      scene.encounter.setDamageTrait(
        scene.ogre,
        'Feuer',
        DamageEffect.immunity,
      );

      await scene.encounter.heal(scene.ogre, 10);

      expect(scene.ogre.hp, 39);
    });

    test('Schaden, gegen den ein sterbender Charakter immun ist, ist kein '
        'Fehlschlag bei den Todesrettungswürfen', () async {
      final scene = Scene([]);
      await scene.encounter.damage(scene.aria, 20);
      scene.encounter.setDamageTrait(scene.aria, 'Gift', DamageEffect.immunity);

      await scene.encounter.damage(scene.aria, 5, damageType: 'Gift');

      expect(scene.aria.deathSaveFailures, 0);
    });

    test('Für den sofortigen Tod durch massiven Schaden zählt der Schaden '
        'nach der Resistenz', () async {
      final scene = Scene([]);
      scene.encounter.setDamageTrait(
        scene.aria,
        'Feuer',
        DamageEffect.resistance,
      );

      // 40 fire damage would kill outright, halved to 20 it does not.
      await scene.encounter.damage(scene.aria, 40, damageType: 'Feuer');

      expect(scene.aria.hp, 0);
      expect(scene.aria.isDead, isFalse);
    });
  });

  group('Resistenz, Anfälligkeit und Immunität: Log und Speichern', () {
    test('Der Angriff steht mit gewürfeltem Schaden, Resistenz und '
        'wirksamem Schaden im Log', () async {
      final scene = Scene([15, 6]);
      scene.encounter.setDamageTrait(
        scene.ogre,
        'Hieb',
        DamageEffect.resistance,
      );

      await scene.ariaHitsOgre();

      final event = (await scene.events()).single as AttackEvent;
      expect(event.damageRoll!.total, 9);
      expect(event.damageEffect, DamageEffect.resistance);
      expect(event.damage, 4);
    });

    test('Direkter Schaden steht mit Schadensart und Resistenz im '
        'Log', () async {
      final scene = Scene([]);
      scene.encounter.setDamageTrait(
        scene.ogre,
        'Feuer',
        DamageEffect.vulnerability,
      );

      await scene.encounter.damage(scene.ogre, 6, damageType: 'Feuer');

      final event = (await scene.events()).single as HpChangeEvent;
      expect(event.amount, 6);
      expect(event.damageType, 'Feuer');
      expect(event.damageEffect, DamageEffect.vulnerability);
      expect(event.hpAfter, 47);
    });

    test('Resistenzen, Anfälligkeiten und Immunitäten kommen nach dem '
        'Neustart zurück', () async {
      final scene = Scene([]);
      scene.encounter
        ..setDamageTrait(scene.ogre, 'Feuer', DamageEffect.resistance)
        ..setDamageTrait(scene.ogre, 'Gift', DamageEffect.immunity)
        ..setDamageTrait(scene.ogre, 'Kälte', DamageEffect.vulnerability);
      await scene.encounter.flush();

      final restored = await Encounter.load(log: scene.log, store: scene.store);

      expect(restored.combatants.last.damageTraits, {
        'Feuer': DamageEffect.resistance,
        'Gift': DamageEffect.immunity,
        'Kälte': DamageEffect.vulnerability,
      });
    });
  });
}
