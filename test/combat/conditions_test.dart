import 'package:dmployee/combat/attack.dart';
import 'package:dmployee/combat/combatant.dart';
import 'package:dmployee/combat/condition.dart';
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
    RollMode mode = RollMode.normal,
    bool applyConditions = true,
  }) => encounter.attack(
    attacker: aria,
    target: ogre,
    attack: longsword,
    mode: mode,
    applyConditions: applyConditions,
  );

  /// Starts the combat with Aria first (10 + 2) and the Oger second (5).
  /// Uses the first two dice of the scene.
  Future<void> startCombat() => encounter.rollInitiative();
}

void main() {
  group('Zustände: verwalten', () {
    test('Die 14 Zustände der 5e-Regeln stehen mit deutschem Namen zur '
        'Auswahl', () {
      expect(Condition.values, hasLength(14));
      expect(Condition.poisoned.label, 'Vergiftet');
      expect(Condition.restrained.label, 'Festgesetzt');
      expect(Condition.prone.label, 'Liegend');
    });

    test('Ein Zustand lässt sich einem Kämpfer geben', () async {
      final scene = Scene([]);

      await scene.encounter.addCondition(scene.ogre, Condition.poisoned);

      expect(scene.ogre.hasCondition(Condition.poisoned), isTrue);
      expect(scene.ogre.conditions.single.roundsLeft, isNull);
      expect(scene.aria.hasCondition(Condition.poisoned), isFalse);
    });

    test('Derselbe Zustand steht nur einmal beim Kämpfer; erneutes Vergeben '
        'ersetzt die Dauer', () async {
      final scene = Scene([]);
      await scene.encounter.addCondition(scene.ogre, Condition.poisoned);

      await scene.encounter.addCondition(
        scene.ogre,
        Condition.poisoned,
        rounds: 3,
      );

      expect(scene.ogre.conditions, hasLength(1));
      expect(scene.ogre.conditions.single.roundsLeft, 3);
    });

    test('Ein Zustand lässt sich wieder entfernen', () async {
      final scene = Scene([]);
      await scene.encounter.addCondition(scene.ogre, Condition.poisoned);

      await scene.encounter.removeCondition(scene.ogre, Condition.poisoned);

      expect(scene.ogre.conditions, isEmpty);
    });

    test('Eine Dauer unter 1 Runde wird abgelehnt und ändert nichts', () async {
      final scene = Scene([]);

      expect(
        () => scene.encounter.addCondition(
          scene.ogre,
          Condition.poisoned,
          rounds: 0,
        ),
        throwsArgumentError,
      );
      expect(scene.ogre.conditions, isEmpty);
      expect(await scene.events(), isEmpty);
    });
  });

  group('Zustände: Vorteil und Nachteil beim Angriff', () {
    test('Ein vergifteter Angreifer greift mit Nachteil an', () async {
      // Two d20: 15 and 4, the lower one counts: 4 + 5 = 9 misses RK 11.
      final scene = Scene([15, 4]);
      await scene.encounter.addCondition(scene.aria, Condition.poisoned);

      final outcome = await scene.ariaAttacksOgre();

      expect(outcome.attackRoll.mode, RollMode.disadvantage);
      expect(outcome.hit, isFalse);
    });

    test('Blinde, festgesetzte und liegende Angreifer greifen ebenfalls mit '
        'Nachteil an', () async {
      for (final condition in [
        Condition.blinded,
        Condition.restrained,
        Condition.prone,
      ]) {
        final scene = Scene([15, 4]);
        await scene.encounter.addCondition(scene.aria, condition);

        final outcome = await scene.ariaAttacksOgre();

        expect(
          outcome.attackRoll.mode,
          RollMode.disadvantage,
          reason: '$condition',
        );
      }
    });

    test('Ein Angriff gegen ein festgesetztes Ziel hat Vorteil', () async {
      // Two d20: 4 and 15, the higher one counts; then the damage die.
      final scene = Scene([4, 15, 6]);
      await scene.encounter.addCondition(scene.ogre, Condition.restrained);

      final outcome = await scene.ariaAttacksOgre();

      expect(outcome.attackRoll.mode, RollMode.advantage);
      expect(outcome.hit, isTrue);
    });

    test('Angriffe gegen blinde, gelähmte, versteinerte, betäubte und '
        'bewusstlose Ziele haben ebenfalls Vorteil', () async {
      for (final condition in [
        Condition.blinded,
        Condition.paralyzed,
        Condition.petrified,
        Condition.stunned,
        Condition.unconscious,
      ]) {
        final scene = Scene([4, 15, 6]);
        await scene.encounter.addCondition(scene.ogre, condition);

        final outcome = await scene.ariaAttacksOgre();

        expect(
          outcome.attackRoll.mode,
          RollMode.advantage,
          reason: '$condition',
        );
      }
    });

    test('Ein unsichtbarer Angreifer hat Vorteil, ein Angriff gegen ein '
        'unsichtbares Ziel Nachteil', () async {
      final attacker = Scene([4, 15, 6]);
      await attacker.encounter.addCondition(attacker.aria, Condition.invisible);
      expect(
        (await attacker.ariaAttacksOgre()).attackRoll.mode,
        RollMode.advantage,
      );

      final target = Scene([15, 4]);
      await target.encounter.addCondition(target.ogre, Condition.invisible);
      expect(
        (await target.ariaAttacksOgre()).attackRoll.mode,
        RollMode.disadvantage,
      );
    });

    test('Vorteil und Nachteil heben sich auf: es wird ein einzelner d20 '
        'gewürfelt', () async {
      final scene = Scene([15, 6]);
      await scene.encounter.addCondition(scene.aria, Condition.poisoned);
      await scene.encounter.addCondition(scene.ogre, Condition.restrained);

      final outcome = await scene.ariaAttacksOgre();

      expect(outcome.attackRoll.mode, RollMode.normal);
      expect(outcome.attackRoll.rolls, [15]);
    });

    test('Mehrere Nachteile und ein einziger Vorteil heben sich ebenfalls '
        'auf', () async {
      final scene = Scene([15, 6]);
      await scene.encounter.addCondition(scene.aria, Condition.poisoned);
      await scene.encounter.addCondition(scene.aria, Condition.blinded);
      await scene.encounter.addCondition(scene.ogre, Condition.stunned);

      expect((await scene.ariaAttacksOgre()).attackRoll.mode, RollMode.normal);
    });

    test('Ein von der Spielleitung gewählter Vorteil hebt den Nachteil aus '
        'einem Zustand auf', () async {
      final scene = Scene([15, 6]);
      await scene.encounter.addCondition(scene.aria, Condition.poisoned);

      final outcome = await scene.ariaAttacksOgre(mode: RollMode.advantage);

      expect(outcome.attackRoll.mode, RollMode.normal);
    });

    test(
      'Auf Wunsch bleiben die Zustände beim Angriff unberücksichtigt',
      () async {
        final scene = Scene([15, 6]);
        await scene.encounter.addCondition(scene.aria, Condition.poisoned);

        final outcome = await scene.ariaAttacksOgre(applyConditions: false);

        expect(outcome.attackRoll.mode, RollMode.normal);
        expect(outcome.event.conditionEffects, isEmpty);
      },
    );

    test('Zustände, deren Wirkung von der Lage am Tisch abhängt, ändern den '
        'Wurf nicht von selbst', () async {
      for (final setup in <(bool onAttacker, Condition)>[
        (true, Condition.frightened),
        (true, Condition.charmed),
        (false, Condition.prone),
        (false, Condition.grappled),
      ]) {
        final scene = Scene([15, 6]);
        await scene.encounter.addCondition(
          setup.$1 ? scene.aria : scene.ogre,
          setup.$2,
        );

        expect(
          (await scene.ariaAttacksOgre()).attackRoll.mode,
          RollMode.normal,
          reason: '$setup',
        );
      }
    });
  });

  group('Zustände: versteinert', () {
    test('Ein versteinertes Ziel hat Resistenz gegen jeden Schaden', () async {
      // Advantage (15, 3), damage 6 + 3 = 9, halved to 4.
      final scene = Scene([15, 3, 6]);
      await scene.encounter.addCondition(scene.ogre, Condition.petrified);

      final outcome = await scene.ariaAttacksOgre();

      expect(outcome.damage, 4);
      expect(outcome.damageEffect, DamageEffect.resistance);
    });

    test('Die Resistenz gilt auch für direkt eingetragenen Schaden ohne '
        'Schadensart', () async {
      final scene = Scene([]);
      await scene.encounter.addCondition(scene.ogre, Condition.petrified);

      await scene.encounter.damage(scene.ogre, 10);

      expect(scene.ogre.hp, 54);
    });

    test('Ein eigener Eintrag für die Schadensart geht der Versteinerung '
        'vor', () async {
      final scene = Scene([15, 3, 6]);
      await scene.encounter.addCondition(scene.ogre, Condition.petrified);
      scene.encounter.setDamageTrait(scene.ogre, 'Hieb', DamageEffect.immunity);

      expect((await scene.ariaAttacksOgre()).damage, 0);
    });
  });

  group('Zustände: Dauer in Runden', () {
    test('Die Dauer sinkt am Ende jedes Zugs des betroffenen Kämpfers; bei '
        '0 endet der Zustand', () async {
      final scene = Scene([10, 5]);
      await scene.startCombat();
      await scene.encounter.addCondition(
        scene.ogre,
        Condition.poisoned,
        rounds: 2,
      );

      await scene.encounter.nextTurn(); // Oger's first turn begins.
      expect(scene.ogre.conditions.single.roundsLeft, 2);

      await scene.encounter.nextTurn(); // Oger's first turn ends.
      expect(scene.ogre.conditions.single.roundsLeft, 1);

      await scene.encounter.nextTurn();
      await scene.encounter.nextTurn(); // Oger's second turn ends.
      expect(scene.ogre.conditions, isEmpty);
    });

    test('Ein Zustand ohne Dauer bleibt, bis er entfernt wird', () async {
      final scene = Scene([10, 5]);
      await scene.startCombat();
      await scene.encounter.addCondition(scene.ogre, Condition.poisoned);

      for (var i = 0; i < 8; i++) {
        await scene.encounter.nextTurn();
      }

      expect(scene.ogre.hasCondition(Condition.poisoned), isTrue);
    });

    test('Die Dauer läuft auch ab, wenn der Kämpfer am Boden liegt und '
        'übersprungen wird', () async {
      final scene = Scene([10, 5]);
      await scene.startCombat();
      await scene.encounter.addCondition(
        scene.ogre,
        Condition.poisoned,
        rounds: 1,
      );
      await scene.encounter.damage(scene.ogre, 59);

      await scene.encounter.nextTurn();

      expect(scene.encounter.current, scene.aria);
      expect(scene.ogre.conditions, isEmpty);
    });

    test('Ohne laufenden Kampf läuft keine Dauer ab', () async {
      final scene = Scene([]);
      await scene.encounter.addCondition(
        scene.ogre,
        Condition.poisoned,
        rounds: 1,
      );

      await scene.encounter.nextTurn();

      expect(scene.ogre.conditions.single.roundsLeft, 1);
    });
  });

  group('Zustände: Log und Speichern', () {
    test('Vergeben und Entfernen stehen im Log', () async {
      final scene = Scene([]);

      await scene.encounter.addCondition(
        scene.ogre,
        Condition.poisoned,
        rounds: 3,
      );
      await scene.encounter.removeCondition(scene.ogre, Condition.poisoned);

      final events = (await scene.events()).cast<ConditionEvent>();
      expect(events.first.name, 'Oger');
      expect(events.first.condition, 'poisoned');
      expect(events.first.change, ConditionChange.added);
      expect(events.first.rounds, 3);
      expect(events.last.change, ConditionChange.removed);
    });

    test('Das Entfernen eines Zustands, den der Kämpfer nicht hat, schreibt '
        'nichts in den Log', () async {
      final scene = Scene([]);

      await scene.encounter.removeCondition(scene.ogre, Condition.poisoned);

      expect(await scene.events(), isEmpty);
    });

    test('Das Ablaufen der Dauer steht im Log', () async {
      final scene = Scene([10, 5]);
      await scene.startCombat();
      await scene.encounter.addCondition(
        scene.ogre,
        Condition.poisoned,
        rounds: 1,
      );

      await scene.encounter.nextTurn();
      await scene.encounter.nextTurn();

      final expired = (await scene.events()).whereType<ConditionEvent>().last;
      expect(expired.change, ConditionChange.expired);
      expect(expired.name, 'Oger');
    });

    test('Der Angriff hält im Log fest, welche Zustände den Wurf verändert '
        'haben und was die Spielleitung gewählt hatte', () async {
      final scene = Scene([15, 6]);
      await scene.encounter.addCondition(scene.aria, Condition.poisoned);
      await scene.encounter.addCondition(scene.ogre, Condition.restrained);

      await scene.ariaAttacksOgre();

      final event = (await scene.events()).last as AttackEvent;
      expect(event.chosenMode, RollMode.normal);
      expect(event.conditionEffects, hasLength(2));
      final poisoned = event.conditionEffects.firstWhere((e) => e.onAttacker);
      expect(poisoned.condition, 'poisoned');
      expect(poisoned.advantage, isFalse);
      final restrained = event.conditionEffects.firstWhere(
        (e) => !e.onAttacker,
      );
      expect(restrained.condition, 'restrained');
      expect(restrained.advantage, isTrue);
    });

    test('Zustände und ihre Restdauer kommen nach dem Neustart '
        'zurück', () async {
      final scene = Scene([]);
      await scene.encounter.addCondition(
        scene.ogre,
        Condition.poisoned,
        rounds: 3,
      );
      await scene.encounter.addCondition(scene.ogre, Condition.prone);
      await scene.encounter.flush();

      final restored = await Encounter.load(log: scene.log, store: scene.store);

      final ogre = restored.combatants.last;
      expect(ogre.conditions.map((c) => c.condition), [
        Condition.poisoned,
        Condition.prone,
      ]);
      expect(ogre.conditions.first.roundsLeft, 3);
      expect(ogre.conditions.last.roundsLeft, isNull);
    });
  });
}
