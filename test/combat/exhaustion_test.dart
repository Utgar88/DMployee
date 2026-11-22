import 'package:dmployee/combat/attack.dart';
import 'package:dmployee/combat/combatant.dart';
import 'package:dmployee/combat/encounter.dart';
import 'package:dmployee/combat/encounter_store.dart';
import 'package:dmployee/dice/dice_expression.dart';
import 'package:dmployee/dice/dice_roller.dart';
import 'package:dmployee/dice/modifier.dart';
import 'package:dmployee/log/log_event.dart';
import 'package:dmployee/log/log_repository.dart';
import 'package:dmployee/rules/ruleset.dart';
import 'package:dmployee/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixed_random.dart';

final longsword = Attack(
  name: 'Langschwert',
  attackBonus: 5,
  damage: DiceExpression.parse('1d8+3'),
  damageType: 'Hieb',
);

/// An encounter under [ruleset] whose dice show [faces] in order, with the
/// player character Aria (RK 16, 20 TP, Initiative +2, Langschwert +5) and
/// a Goblin (monster, RK 13, 7 TP, Initiative +1).
class Scene {
  Scene({List<int> faces = const [], Ruleset ruleset = Ruleset.dnd2014}) {
    settings.setRuleset(ruleset);
    encounter = Encounter(
      log: log,
      store: store,
      settings: settings,
      roller: DiceRoller(FixedRandom(faces)),
    );
    aria = encounter.add(
      name: 'Aria',
      armorClass: 16,
      maxHp: 20,
      initiativeBonus: 2,
      isPlayer: true,
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
  final store = InMemoryEncounterStore();
  final settings = AppSettings();
  late final Encounter encounter;
  late final Combatant aria;
  late final Combatant goblin;

  /// Logged events, oldest first.
  Future<List<LogEvent>> events() async =>
      (await log.entries()).reversed.map((entry) => entry.event).toList();

  Future<AttackOutcome> ariaAttacks({bool applyConditions = true}) =>
      encounter.attack(
        attacker: aria,
        target: goblin,
        attack: longsword,
        applyConditions: applyConditions,
      );
}

void main() {
  group('Erschöpfung einstellen', () {
    test('Die Stufe wird gesetzt und mit Regelwerk geloggt', () async {
      final scene = Scene(ruleset: Ruleset.dnd2024);

      await scene.encounter.setExhaustion(scene.aria, 2);

      expect(scene.aria.exhaustion, 2);
      final event = (await scene.events()).single as ExhaustionEvent;
      expect(event.name, 'Aria');
      expect(event.before, 0);
      expect(event.after, 2);
      expect(event.ruleset, '5e-2024');
    });

    test('Die Stufe übersteht den Neustart', () async {
      final scene = Scene();
      await scene.encounter.setExhaustion(scene.goblin, 3);
      await scene.encounter.flush();

      final restored = await Encounter.load(log: scene.log, store: scene.store);

      expect(restored.combatants.last.exhaustion, 3);
    });

    test(
      'Stufen außerhalb 0 bis 6 werden abgelehnt und ändern nichts',
      () async {
        final scene = Scene();

        expect(
          () => scene.encounter.setExhaustion(scene.aria, 7),
          throwsArgumentError,
        );
        expect(
          () => scene.encounter.setExhaustion(scene.aria, -1),
          throwsArgumentError,
        );
        expect(scene.aria.exhaustion, 0);
        expect(await scene.events(), isEmpty);
      },
    );

    test('Dieselbe Stufe noch einmal ändert nichts und schreibt nichts in '
        'den Log', () async {
      final scene = Scene();
      await scene.encounter.setExhaustion(scene.aria, 1);

      expect(await scene.encounter.setExhaustion(scene.aria, 1), isNull);
      expect(await scene.events(), hasLength(1));
    });
  });

  group('Tod bei Stufe 6', () {
    for (final ruleset in Ruleset.values) {
      test('${ruleset.label}: Stufe 6 tötet, auch Monster', () async {
        final scene = Scene(ruleset: ruleset);

        await scene.encounter.setExhaustion(scene.aria, 6);
        await scene.encounter.setExhaustion(scene.goblin, 6);

        expect(scene.aria.isDead, isTrue);
        expect(scene.aria.hp, 0);
        expect(scene.goblin.isDead, isTrue);
        final events = await scene.events();
        expect(events[0], isA<ExhaustionEvent>());
        expect(
          events[1],
          isA<CombatantDiedEvent>()
              .having((e) => e.name, 'name', 'Aria')
              .having((e) => e.exhaustion, 'exhaustion', isTrue),
        );
      });
    }

    test('Senken der Stufe belebt nicht wieder', () async {
      final scene = Scene();
      await scene.encounter.setExhaustion(scene.aria, 6);

      await scene.encounter.setExhaustion(scene.aria, 5);

      expect(scene.aria.isDead, isTrue);
    });

    test(
      'Wiederbeleben ist bei Stufe 6 gesperrt; nach dem Senken geht es',
      () async {
        final scene = Scene();
        await scene.encounter.setExhaustion(scene.aria, 6);

        expect(() => scene.encounter.revive(scene.aria), throwsStateError);
        expect(scene.aria.isDead, isTrue);

        await scene.encounter.setExhaustion(scene.aria, 5);
        await scene.encounter.revive(scene.aria);
        expect(scene.aria.isDead, isFalse);
        expect(scene.aria.hp, 1);
      },
    );

    test('Ein bereits Toter stirbt nicht noch einmal', () async {
      final scene = Scene();
      await scene.encounter.damage(scene.aria, 40);
      expect(scene.aria.isDead, isTrue);
      final before = (await scene.events()).length;

      await scene.encounter.setExhaustion(scene.aria, 6);

      final events = await scene.events();
      expect(events, hasLength(before + 1));
      expect(events.last, isA<ExhaustionEvent>());
    });
  });

  group('Maximale TP bei Erschöpfung', () {
    test('2014: Ab Stufe 4 sind die maximalen TP halbiert; höhere TP sinken '
        'mit', () async {
      final scene = Scene();

      await scene.encounter.setExhaustion(scene.aria, 4);

      expect(scene.encounter.maxHpOf(scene.aria), 10);
      expect(scene.aria.hp, 10);
      expect(scene.aria.maxHp, 20);
    });

    test('2014: Heilung endet bei den halbierten TP', () async {
      final scene = Scene();
      await scene.encounter.setExhaustion(scene.aria, 4);
      await scene.encounter.damage(scene.aria, 6);

      final event = await scene.encounter.heal(scene.aria, 20);

      expect(scene.aria.hp, 10);
      expect(event.maxHp, 10);
    });

    test('2014: Sinkt die Stufe unter 4, kommt das Maximum zurück, die TP '
        'nicht', () async {
      final scene = Scene();
      await scene.encounter.setExhaustion(scene.aria, 4);

      await scene.encounter.setExhaustion(scene.aria, 3);

      expect(scene.encounter.maxHpOf(scene.aria), 20);
      expect(scene.aria.hp, 10);
    });

    test('2014: Sofortiger Tod durch massiven Schaden zählt gegen die '
        'halbierten TP', () async {
      final scene = Scene();
      await scene.encounter.setExhaustion(scene.aria, 4);

      await scene.encounter.damage(scene.aria, 20);

      expect(scene.aria.isDead, isTrue);
    });

    test('2014: Wiederbeleben höchstens bis zu den halbierten TP', () async {
      final scene = Scene();
      await scene.encounter.setExhaustion(scene.aria, 4);
      await scene.encounter.damage(scene.aria, 20);

      expect(
        () => scene.encounter.revive(scene.aria, hp: 11),
        throwsArgumentError,
      );
      await scene.encounter.revive(scene.aria, hp: 10);
      expect(scene.aria.hp, 10);
    });

    test('2024: Die maximalen TP bleiben', () async {
      final scene = Scene(ruleset: Ruleset.dnd2024);

      await scene.encounter.setExhaustion(scene.aria, 5);

      expect(scene.encounter.maxHpOf(scene.aria), 20);
      expect(scene.aria.hp, 20);
    });
  });

  group('Angriffe bei Erschöpfung', () {
    test('2014: Ab Stufe 3 greift der Erschöpfte mit Nachteil an; der Log '
        'nennt den Grund', () async {
      final scene = Scene(faces: [15, 4, 6]);
      await scene.encounter.setExhaustion(scene.aria, 3);

      final outcome = await scene.ariaAttacks();

      expect(outcome.attackRoll.mode, RollMode.disadvantage);
      expect(outcome.attackRoll.kept, 4);
      expect(
        outcome.event.conditionEffects.single,
        isA<ConditionEffect>()
            .having((e) => e.condition, 'condition', exhaustionCondition)
            .having((e) => e.onAttacker, 'onAttacker', isTrue)
            .having((e) => e.advantage, 'advantage', isFalse),
      );
    });

    test('2014: Auf Stufe 2 gibt es noch keinen Nachteil', () async {
      final scene = Scene(faces: [15, 6]);
      await scene.encounter.setExhaustion(scene.aria, 2);

      final outcome = await scene.ariaAttacks();

      expect(outcome.attackRoll.mode, RollMode.normal);
    });

    test('2014: Werden Zustände nicht angewendet, gilt auch die Erschöpfung '
        'nicht', () async {
      final scene = Scene(faces: [15, 6]);
      await scene.encounter.setExhaustion(scene.aria, 3);

      final outcome = await scene.ariaAttacks(applyConditions: false);

      expect(outcome.attackRoll.mode, RollMode.normal);
    });

    test('2024: Der Angriffswurf sinkt um 2 je Stufe', () async {
      final scene = Scene(faces: [10], ruleset: Ruleset.dnd2024);
      await scene.encounter.setExhaustion(scene.aria, 2);

      final outcome = await scene.ariaAttacks();

      expect(outcome.attackRoll.mode, RollMode.normal);
      expect(
        outcome.attackRoll.modifiers,
        contains(Modifier('Erschöpfung', -4)),
      );
      expect(outcome.attackRoll.total, 10 + 5 - 4);
      expect(outcome.hit, isFalse);
    });

    test('Die Erschöpfung des Ziels ändert den Angriff nicht', () async {
      final scene = Scene(faces: [15, 6], ruleset: Ruleset.dnd2024);
      await scene.encounter.setExhaustion(scene.goblin, 3);

      final outcome = await scene.ariaAttacks();

      expect(outcome.attackRoll.total, 20);
      expect(outcome.attackRoll.mode, RollMode.normal);
    });
  });

  group('Todesrettungswürfe bei Erschöpfung', () {
    test('2014: Ab Stufe 3 mit Nachteil; der Log nennt den Grund', () async {
      final scene = Scene(faces: [15, 4]);
      await scene.encounter.setExhaustion(scene.aria, 3);
      await scene.encounter.damage(scene.aria, 20);

      final event = await scene.encounter.rollDeathSave(scene.aria);

      expect(event.roll.mode, RollMode.disadvantage);
      expect(event.roll.total, 4);
      expect(event.failures, 1);
      expect(event.disadvantageFromExhaustion, 3);
    });

    test('2024: Der Wurf sinkt um 2 je Stufe', () async {
      final scene = Scene(faces: [11], ruleset: Ruleset.dnd2024);
      await scene.encounter.setExhaustion(scene.aria, 1);
      await scene.encounter.damage(scene.aria, 20);

      final event = await scene.encounter.rollDeathSave(scene.aria);

      expect(event.roll.total, 9);
      expect(event.failures, 1);
      expect(event.disadvantageFromExhaustion, isNull);
    });

    test('2024: Eine natürliche 20 bringt trotzdem 1 TP zurück', () async {
      final scene = Scene(faces: [20], ruleset: Ruleset.dnd2024);
      await scene.encounter.setExhaustion(scene.aria, 3);
      await scene.encounter.damage(scene.aria, 20);

      await scene.encounter.rollDeathSave(scene.aria);

      expect(scene.aria.hp, 1);
    });

    test('2014: Von Hand eingetragen gilt ebenfalls der Nachteil', () async {
      final scene = Scene();
      await scene.encounter.setExhaustion(scene.aria, 3);
      await scene.encounter.damage(scene.aria, 20);

      final event = await scene.encounter.rollDeathSave(
        scene.aria,
        manualRoll: 12,
      );

      expect(event.roll.mode, RollMode.disadvantage);
      expect(event.roll.manual, isTrue);
      expect(event.disadvantageFromExhaustion, 3);
    });
  });

  group('Initiative bei Erschöpfung', () {
    test('2014: Ab Stufe 1 mit Nachteil, weil die Initiative ein '
        'Geschicklichkeitswurf ist', () async {
      final scene = Scene(faces: [15, 3, 10]);
      await scene.encounter.setExhaustion(scene.aria, 1);

      await scene.encounter.rollInitiative();

      final event = (await scene.events()).whereType<InitiativeEvent>().single;
      final aria = event.entries.firstWhere((e) => e.name == 'Aria');
      expect(aria.roll.mode, RollMode.disadvantage);
      expect(aria.roll.total, 3 + 2);
      expect(aria.disadvantageFromExhaustion, 1);
      final goblin = event.entries.firstWhere((e) => e.name == 'Goblin');
      expect(goblin.disadvantageFromExhaustion, isNull);
    });

    test('2024: Die Initiative sinkt um 2 je Stufe', () async {
      final scene = Scene(faces: [15, 10], ruleset: Ruleset.dnd2024);
      await scene.encounter.setExhaustion(scene.aria, 2);

      await scene.encounter.rollInitiative();

      expect(scene.aria.initiative, 15 + 2 - 4);
    });

    test('Von Hand eingetragen gelten Nachteil und Abzug ebenso', () async {
      final scene = Scene(faces: [10], ruleset: Ruleset.dnd2024);
      await scene.encounter.setExhaustion(scene.aria, 1);

      await scene.encounter.rollInitiative(manual: {scene.aria: 12});

      expect(scene.aria.initiative, 12 + 2 - 2);
    });
  });
}
