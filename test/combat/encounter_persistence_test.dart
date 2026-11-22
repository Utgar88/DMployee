import 'package:dmployee/combat/attack.dart';
import 'package:dmployee/combat/combatant.dart';
import 'package:dmployee/combat/encounter.dart';
import 'package:dmployee/combat/encounter_store.dart';
import 'package:dmployee/dice/dice_expression.dart';
import 'package:dmployee/dice/dice_roller.dart';
import 'package:dmployee/log/log_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixed_random.dart';

final longsword = Attack(
  name: 'Langschwert',
  attackBonus: 5,
  damage: DiceExpression.parse('1d8+3'),
  damageType: 'Hieb',
);

/// An encounter that saves into [store], with dice showing [faces] in order,
/// the fighter Aria (RK 16, 20 TP, Initiative +2, Langschwert) and a Goblin
/// (RK 13, 7 TP, Initiative +1).
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
    goblin = encounter.add(
      name: 'Goblin',
      armorClass: 13,
      maxHp: 7,
      initiativeBonus: 1,
    );
  }

  final log = InMemoryLogRepository();
  final store = InMemoryEncounterStore();
  late final Encounter encounter;
  late final Combatant aria;
  late final Combatant goblin;

  /// What the app finds after it was closed and opened again.
  Future<Encounter> reopen() async {
    await encounter.flush();
    return Encounter.load(log: log, store: store);
  }
}

void main() {
  group('Kampfstand speichern: Kämpfer', () {
    test('Kämpfer kommen nach dem Neustart mit Name, Rüstungsklasse, '
        'Trefferpunkten und Initiative-Bonus zurück', () async {
      final restored = await Scene([]).reopen();

      expect(restored.combatants.map((c) => c.name), ['Aria', 'Goblin']);
      final aria = restored.combatants.first;
      expect(aria.armorClass, 16);
      expect(aria.maxHp, 20);
      expect(aria.hp, 20);
      expect(aria.initiativeBonus, 2);
    });

    test('Hinterlegte Angriffe kommen vollständig zurück', () async {
      final restored = await Scene([]).reopen();

      final attack = restored.combatants.first.attacks.single;
      expect(attack.name, 'Langschwert');
      expect(attack.attackBonus, 5);
      expect(attack.damage, DiceExpression.parse('1d8+3'));
      expect(attack.damageType, 'Hieb');
    });

    test('Ein nachträglich hinterlegter Angriff wird gespeichert', () async {
      final scene = Scene([]);
      scene.encounter.addAttack(
        scene.goblin,
        Attack(
          name: 'Krummsäbel',
          attackBonus: 4,
          damage: DiceExpression.parse('1d6-1'),
          damageType: 'Hieb',
        ),
      );

      final restored = await scene.reopen();

      final attack = restored.combatants.last.attacks.single;
      expect(attack.name, 'Krummsäbel');
      expect(attack.damage, DiceExpression.parse('1d6-1'));
    });

    test('Ein entfernter Kämpfer bleibt nach dem Neustart entfernt', () async {
      final scene = Scene([]);
      scene.encounter.remove(scene.goblin);

      final restored = await scene.reopen();

      expect(restored.combatants.map((c) => c.name), ['Aria']);
    });
  });

  group('Kampfstand speichern: Erschöpfung', () {
    test('Die Erschöpfung eines Kämpfers bleibt nach dem Neustart '
        'erhalten', () async {
      final scene = Scene([]);
      scene.goblin.exhaustion = 2;
      await scene.encounter.damage(scene.goblin, 1);

      final restored = await scene.reopen();

      expect(restored.combatants.last.exhaustion, 2);
      expect(restored.combatants.first.exhaustion, 0);
    });
  });

  group('Kampfstand speichern: Trefferpunkte', () {
    test('Direkt eingetragener Schaden bleibt nach dem Neustart '
        'erhalten', () async {
      final scene = Scene([]);
      await scene.encounter.damage(scene.goblin, 3);

      final restored = await scene.reopen();

      expect(restored.combatants.last.hp, 4);
      expect(restored.combatants.last.maxHp, 7);
    });

    test('Heilung bleibt nach dem Neustart erhalten', () async {
      final scene = Scene([]);
      await scene.encounter.damage(scene.aria, 15);
      await scene.encounter.heal(scene.aria, 4);

      final restored = await scene.reopen();

      expect(restored.combatants.first.hp, 9);
    });

    test('Schaden aus einem Angriff bleibt nach dem Neustart erhalten, ein '
        'Kämpfer am Boden bleibt am Boden', () async {
      final scene = Scene([15, 8]);
      await scene.encounter.attack(
        attacker: scene.aria,
        target: scene.goblin,
        attack: longsword,
      );

      final restored = await scene.reopen();

      expect(restored.combatants.last.hp, 0);
      expect(restored.combatants.last.isDown, isTrue);
    });
  });

  group('Kampfstand speichern: laufender Kampf', () {
    test('Vor dem Initiativewurf läuft auch nach dem Neustart kein '
        'Kampf', () async {
      final restored = await Scene([]).reopen();

      expect(restored.isRunning, isFalse);
      expect(restored.current, isNull);
    });

    test('Zugfolge und Initiativewerte kommen zurück', () async {
      // Aria rolls 3 (+2 = 5), the Goblin 15 (+1 = 16): the Goblin goes first.
      final scene = Scene([3, 15]);
      await scene.encounter.rollInitiative();

      final restored = await scene.reopen();

      expect(restored.combatants.map((c) => c.name), ['Goblin', 'Aria']);
      expect(restored.combatants.map((c) => c.initiative), [16, 5]);
    });

    test('Runde und der Kämpfer, der am Zug ist, kommen zurück', () async {
      final scene = Scene([10, 5]);
      await scene.encounter.rollInitiative();
      await scene.encounter.nextTurn();
      await scene.encounter.nextTurn();
      await scene.encounter.nextTurn();

      final restored = await scene.reopen();

      expect(restored.isRunning, isTrue);
      expect(restored.round, 2);
      expect(restored.current!.name, 'Goblin');
    });

    test('Nach dem Neustart geht der Kampf normal weiter', () async {
      final scene = Scene([10, 5]);
      await scene.encounter.rollInitiative();
      final restored = await scene.reopen();

      await restored.nextTurn();
      expect(restored.current!.name, 'Goblin');
      await restored.nextTurn();

      expect(restored.current!.name, 'Aria');
      expect(restored.round, 2);
    });

    test('Ein beendeter Kampf bleibt nach dem Neustart beendet, die '
        'Trefferpunkte bleiben', () async {
      final scene = Scene([10, 5]);
      await scene.encounter.rollInitiative();
      await scene.encounter.damage(scene.goblin, 2);
      scene.encounter.end();

      final restored = await scene.reopen();

      expect(restored.isRunning, isFalse);
      expect(restored.combatants.every((c) => c.initiative == null), isTrue);
      expect(restored.combatants.firstWhere((c) => c.name == 'Goblin').hp, 5);
    });

    test('Änderungen nach dem Neustart werden wieder gespeichert', () async {
      final scene = Scene([]);
      final restored = await scene.reopen();
      await restored.damage(restored.combatants.last, 6);

      final again = await Encounter.load(log: scene.log, store: scene.store);

      expect(again.combatants.last.hp, 1);
    });
  });

  group('Kampfstand speichern: Sonderfälle', () {
    test('Ohne gespeicherten Stand startet die App mit einem leeren '
        'Kampf', () async {
      final restored = await Encounter.load(
        log: InMemoryLogRepository(),
        store: InMemoryEncounterStore(),
      );

      expect(restored.combatants, isEmpty);
      expect(restored.isRunning, isFalse);
    });

    test('Ein unlesbarer gespeicherter Stand führt zu einem leeren Kampf '
        'statt zu einem Absturz', () async {
      final store = InMemoryEncounterStore();
      await store.save({'combatants': 'kaputt', 'round': 'x'});

      final restored = await Encounter.load(
        log: InMemoryLogRepository(),
        store: store,
      );

      expect(restored.combatants, isEmpty);
      expect(restored.isRunning, isFalse);
    });

    test('Das Laden des Kampfstands schreibt nichts in den Log', () async {
      final scene = Scene([]);

      await scene.reopen();

      expect(await scene.log.entries(), isEmpty);
    });
  });
}
