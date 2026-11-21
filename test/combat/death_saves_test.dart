import 'package:dmployee/combat/attack.dart';
import 'package:dmployee/combat/combatant.dart';
import 'package:dmployee/combat/encounter.dart';
import 'package:dmployee/combat/encounter_store.dart';
import 'package:dmployee/dice/dice_expression.dart';
import 'package:dmployee/dice/dice_roller.dart';
import 'package:dmployee/log/log_event.dart';
import 'package:dmployee/log/log_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixed_random.dart';

final scimitar = Attack(
  name: 'Krummsäbel',
  attackBonus: 4,
  damage: DiceExpression.parse('1d6+2'),
  damageType: 'Hieb',
);

/// An encounter whose dice show the given [faces] in order, with the player
/// character Aria (RK 16, 20 TP, Initiative +2) and a Goblin (monster,
/// RK 13, 7 TP, Initiative +1, Krummsäbel).
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
      isPlayer: true,
    );
    goblin = encounter.add(
      name: 'Goblin',
      armorClass: 13,
      maxHp: 7,
      initiativeBonus: 1,
      attacks: [scimitar],
    );
  }

  final log = InMemoryLogRepository();
  final store = InMemoryEncounterStore();
  late final Encounter encounter;
  late final Combatant aria;
  late final Combatant goblin;

  /// Logged events, oldest first.
  Future<List<LogEvent>> events() async =>
      (await log.entries()).reversed.map((entry) => entry.event).toList();

  /// Brings Aria to 0 hit points without killing her.
  Future<void> ariaDrops() => encounter.damage(aria, 20);

  Future<DeathSaveEvent> deathSave({int? manualRoll}) =>
      encounter.rollDeathSave(aria, manualRoll: manualRoll);

  Future<Encounter> reopen() async {
    await encounter.flush();
    return Encounter.load(log: log, store: store);
  }
}

void main() {
  group('Todesrettungswürfe: wer sie macht', () {
    test('Ein Spielercharakter mit 0 Trefferpunkten liegt im Sterben, ist '
        'aber nicht tot', () async {
      final scene = Scene([]);

      await scene.ariaDrops();

      expect(scene.aria.isDying, isTrue);
      expect(scene.aria.isDead, isFalse);
      expect(scene.aria.isStable, isFalse);
    });

    test('Ein Monster mit 0 Trefferpunkten macht keine '
        'Todesrettungswürfe', () async {
      final scene = Scene([]);
      await scene.encounter.damage(scene.goblin, 7);

      expect(scene.goblin.isDying, isFalse);
      expect(
        () => scene.encounter.rollDeathSave(scene.goblin),
        throwsStateError,
      );
    });

    test('Ein Spielercharakter mit Trefferpunkten kann keinen '
        'Todesrettungswurf machen', () async {
      final scene = Scene([]);

      expect(() => scene.deathSave(), throwsStateError);
      expect(await scene.events(), isEmpty);
    });
  });

  group('Todesrettungswürfe: der Wurf', () {
    test('Eine 10 oder höher ist ein Erfolg', () async {
      final scene = Scene([10]);
      await scene.ariaDrops();

      await scene.deathSave();

      expect(scene.aria.deathSaveSuccesses, 1);
      expect(scene.aria.deathSaveFailures, 0);
    });

    test('Eine 9 oder niedriger ist ein Fehlschlag', () async {
      final scene = Scene([9]);
      await scene.ariaDrops();

      await scene.deathSave();

      expect(scene.aria.deathSaveSuccesses, 0);
      expect(scene.aria.deathSaveFailures, 1);
    });

    test('Eine natürliche 1 zählt als zwei Fehlschläge', () async {
      final scene = Scene([1]);
      await scene.ariaDrops();

      await scene.deathSave();

      expect(scene.aria.deathSaveFailures, 2);
      expect(scene.aria.isDead, isFalse);
    });

    test('Eine natürliche 20 bringt den Charakter mit 1 Trefferpunkt zurück '
        'und setzt die Zähler zurück', () async {
      final scene = Scene([5, 20]);
      await scene.ariaDrops();
      await scene.deathSave();

      await scene.deathSave();

      expect(scene.aria.hp, 1);
      expect(scene.aria.isDying, isFalse);
      expect(scene.aria.deathSaveSuccesses, 0);
      expect(scene.aria.deathSaveFailures, 0);
    });

    test('Nach drei Erfolgen ist der Charakter stabil: er bleibt bei 0 '
        'Trefferpunkten, würfelt nicht mehr und die Zähler sind '
        'zurückgesetzt', () async {
      final scene = Scene([12, 4, 15, 10]);
      await scene.ariaDrops();

      for (var i = 0; i < 4; i++) {
        await scene.deathSave();
      }

      expect(scene.aria.isStable, isTrue);
      expect(scene.aria.isDying, isFalse);
      expect(scene.aria.isDead, isFalse);
      expect(scene.aria.hp, 0);
      expect(scene.aria.deathSaveSuccesses, 0);
      expect(scene.aria.deathSaveFailures, 0);
      expect(() => scene.deathSave(), throwsStateError);
    });

    test('Nach drei Fehlschlägen ist der Charakter tot', () async {
      final scene = Scene([3, 14, 8, 2]);
      await scene.ariaDrops();

      for (var i = 0; i < 4; i++) {
        await scene.deathSave();
      }

      expect(scene.aria.isDead, isTrue);
      expect(scene.aria.isDying, isFalse);
      expect(() => scene.deathSave(), throwsStateError);
    });

    test('Eine natürliche 1 beim zweiten Fehlschlag führt zum Tod', () async {
      final scene = Scene([4, 1]);
      await scene.ariaDrops();

      await scene.deathSave();
      await scene.deathSave();

      expect(scene.aria.isDead, isTrue);
    });

    test('Ein am Tisch gewürfelter Todesrettungswurf lässt sich von Hand '
        'eintragen', () async {
      final scene = Scene([]);
      await scene.ariaDrops();

      final event = await scene.deathSave(manualRoll: 15);

      expect(event.roll.manual, isTrue);
      expect(event.roll.total, 15);
      expect(scene.aria.deathSaveSuccesses, 1);
    });

    test('Ein eingetragener Wurf außerhalb von 1 bis 20 wird abgelehnt und '
        'ändert nichts', () async {
      final scene = Scene([]);
      await scene.ariaDrops();
      final before = (await scene.events()).length;

      expect(() => scene.deathSave(manualRoll: 21), throwsArgumentError);
      expect(scene.aria.deathSaveSuccesses, 0);
      expect(scene.aria.deathSaveFailures, 0);
      expect(await scene.events(), hasLength(before));
    });
  });

  group('Todesrettungswürfe: Schaden bei 0 Trefferpunkten', () {
    test('Schaden an einem sterbenden Charakter ist ein Fehlschlag', () async {
      final scene = Scene([]);
      await scene.ariaDrops();

      await scene.encounter.damage(scene.aria, 3);

      expect(scene.aria.deathSaveFailures, 1);
      expect(scene.aria.isDead, isFalse);
    });

    test('Ein kritischer Treffer gegen einen sterbenden Charakter zählt als '
        'zwei Fehlschläge', () async {
      // Natural 20 on the attack, then two damage dice.
      final scene = Scene([20, 3, 4]);
      await scene.ariaDrops();

      await scene.encounter.attack(
        attacker: scene.goblin,
        target: scene.aria,
        attack: scimitar,
      );

      expect(scene.aria.deathSaveFailures, 2);
    });

    test('Ein Angriff, der verfehlt, ist kein Fehlschlag', () async {
      final scene = Scene([2]);
      await scene.ariaDrops();

      await scene.encounter.attack(
        attacker: scene.goblin,
        target: scene.aria,
        attack: scimitar,
      );

      expect(scene.aria.deathSaveFailures, 0);
    });

    test('Der dritte Fehlschlag durch Schaden tötet den Charakter', () async {
      final scene = Scene([1]);
      await scene.ariaDrops();
      await scene.deathSave();

      await scene.encounter.damage(scene.aria, 1);

      expect(scene.aria.isDead, isTrue);
    });

    test('Ein stabiler Charakter, der Schaden erleidet, liegt wieder im '
        'Sterben und hat einen Fehlschlag', () async {
      final scene = Scene([10, 10, 10]);
      await scene.ariaDrops();
      for (var i = 0; i < 3; i++) {
        await scene.deathSave();
      }

      await scene.encounter.damage(scene.aria, 2);

      expect(scene.aria.isStable, isFalse);
      expect(scene.aria.isDying, isTrue);
      expect(scene.aria.deathSaveFailures, 1);
    });

    test('Schaden in Höhe der maximalen Trefferpunkte tötet einen '
        'sterbenden Charakter sofort', () async {
      final scene = Scene([]);
      await scene.ariaDrops();

      await scene.encounter.damage(scene.aria, 20);

      expect(scene.aria.isDead, isTrue);
    });
  });

  group('Todesrettungswürfe: sofortiger Tod durch massiven Schaden', () {
    test('Bleibt nach dem Fall auf 0 noch Schaden in Höhe der maximalen '
        'Trefferpunkte übrig, ist der Charakter sofort tot', () async {
      final scene = Scene([]);

      await scene.encounter.damage(scene.aria, 40);

      expect(scene.aria.hp, 0);
      expect(scene.aria.isDead, isTrue);
    });

    test('Bleibt weniger übrig, liegt der Charakter nur im Sterben', () async {
      final scene = Scene([]);

      await scene.encounter.damage(scene.aria, 39);

      expect(scene.aria.isDead, isFalse);
      expect(scene.aria.isDying, isTrue);
    });
  });

  group('Todesrettungswürfe: Heilung', () {
    test('Heilung holt einen sterbenden Charakter zurück und setzt die '
        'Zähler zurück', () async {
      final scene = Scene([4, 12]);
      await scene.ariaDrops();
      await scene.deathSave();
      await scene.deathSave();

      await scene.encounter.heal(scene.aria, 5);

      expect(scene.aria.hp, 5);
      expect(scene.aria.isDying, isFalse);
      expect(scene.aria.deathSaveSuccesses, 0);
      expect(scene.aria.deathSaveFailures, 0);
    });

    test('Heilung holt einen stabilen Charakter zurück', () async {
      final scene = Scene([10, 10, 10]);
      await scene.ariaDrops();
      for (var i = 0; i < 3; i++) {
        await scene.deathSave();
      }

      await scene.encounter.heal(scene.aria, 5);

      expect(scene.aria.hp, 5);
      expect(scene.aria.isStable, isFalse);
    });

    test('Ein toter Charakter lässt sich nicht heilen', () async {
      final scene = Scene([]);
      await scene.encounter.damage(scene.aria, 40);
      final before = (await scene.events()).length;

      expect(() => scene.encounter.heal(scene.aria, 5), throwsStateError);
      expect(scene.aria.hp, 0);
      expect(scene.aria.isDead, isTrue);
      expect(await scene.events(), hasLength(before));
    });
  });

  group('Todesrettungswürfe: Zugfolge', () {
    // Aria rolls 10 (+2 = 12), the Goblin 5 (+1 = 6): Aria goes first.
    test('Ein sterbender Charakter bleibt in der Zugfolge, damit er seinen '
        'Todesrettungswurf machen kann', () async {
      final scene = Scene([10, 5]);
      await scene.encounter.rollInitiative();
      await scene.ariaDrops();

      await scene.encounter.nextTurn();
      await scene.encounter.nextTurn();

      expect(scene.encounter.current, scene.aria);
    });

    test('Ein stabiler Charakter wird in der Zugfolge übersprungen', () async {
      final scene = Scene([10, 5, 10, 10, 10]);
      await scene.encounter.rollInitiative();
      await scene.ariaDrops();
      for (var i = 0; i < 3; i++) {
        await scene.deathSave();
      }

      await scene.encounter.nextTurn();
      await scene.encounter.nextTurn();

      expect(scene.encounter.current, scene.goblin);
    });

    test('Ein toter Charakter wird in der Zugfolge übersprungen', () async {
      final scene = Scene([10, 5]);
      await scene.encounter.rollInitiative();
      await scene.encounter.damage(scene.aria, 40);

      await scene.encounter.nextTurn();
      await scene.encounter.nextTurn();

      expect(scene.encounter.current, scene.goblin);
    });
  });

  group('Todesrettungswürfe: Log', () {
    test('Fällt ein Spielercharakter auf 0, steht "geht zu Boden" im '
        'Log', () async {
      final scene = Scene([]);

      await scene.ariaDrops();

      expect((await scene.events()).last, isA<CombatantDownEvent>());
    });

    test('Der Wurf steht mit Würfel und dem Stand der Erfolge und '
        'Fehlschläge im Log', () async {
      final scene = Scene([4, 13]);
      await scene.ariaDrops();
      await scene.deathSave();

      await scene.deathSave();

      final event = (await scene.events()).last as DeathSaveEvent;
      expect(event.name, 'Aria');
      expect(event.roll.total, 13);
      expect(event.successes, 1);
      expect(event.failures, 1);
    });

    test('Wird der Charakter stabil, folgt ein eigener Log-Eintrag', () async {
      final scene = Scene([10, 10, 10]);
      await scene.ariaDrops();
      for (var i = 0; i < 3; i++) {
        await scene.deathSave();
      }

      final events = await scene.events();
      expect((events[events.length - 2] as DeathSaveEvent).successes, 3);
      expect((events.last as CombatantStableEvent).name, 'Aria');
    });

    test('Stirbt der Charakter am dritten Fehlschlag, folgt ein eigener '
        'Log-Eintrag', () async {
      final scene = Scene([2, 2, 2]);
      await scene.ariaDrops();
      for (var i = 0; i < 3; i++) {
        await scene.deathSave();
      }

      final died = (await scene.events()).last as CombatantDiedEvent;
      expect(died.name, 'Aria');
      expect(died.massiveDamage, isFalse);
    });

    test('Schaden bei 0 Trefferpunkten steht als Fehlschlag im Log', () async {
      final scene = Scene([]);
      await scene.ariaDrops();

      await scene.encounter.damage(scene.aria, 3);

      final event = (await scene.events()).last as DyingDamageEvent;
      expect(event.name, 'Aria');
      expect(event.failuresAdded, 1);
      expect(event.failures, 1);
    });

    test('Sofortiger Tod durch massiven Schaden steht als solcher im Log, '
        'ohne "geht zu Boden"', () async {
      final scene = Scene([]);

      await scene.encounter.damage(scene.aria, 40);

      final events = await scene.events();
      expect(events.whereType<CombatantDownEvent>(), isEmpty);
      expect((events.last as CombatantDiedEvent).massiveDamage, isTrue);
    });
  });

  group('Todesrettungswürfe: Speichern', () {
    test('Spielercharakter, Erfolge und Fehlschläge kommen nach dem '
        'Neustart zurück', () async {
      final scene = Scene([4, 12, 3]);
      await scene.ariaDrops();
      for (var i = 0; i < 3; i++) {
        await scene.deathSave();
      }

      final aria = (await scene.reopen()).combatants.first;

      expect(aria.isPlayer, isTrue);
      expect(aria.deathSaveSuccesses, 1);
      expect(aria.deathSaveFailures, 2);
      expect(aria.isDying, isTrue);
    });

    test('Ein stabiler Charakter ist nach dem Neustart noch stabil', () async {
      final scene = Scene([10, 10, 10]);
      await scene.ariaDrops();
      for (var i = 0; i < 3; i++) {
        await scene.deathSave();
      }

      expect((await scene.reopen()).combatants.first.isStable, isTrue);
    });

    test('Ein toter Charakter ist nach dem Neustart noch tot', () async {
      final scene = Scene([]);
      await scene.encounter.damage(scene.aria, 40);

      expect((await scene.reopen()).combatants.first.isDead, isTrue);
    });

    test('Ein Kampfstand, der vor den Todesrettungswürfen gespeichert '
        'wurde, lässt sich weiter laden', () async {
      final store = InMemoryEncounterStore();
      await store.save({
        'round': 0,
        'current': null,
        'combatants': [
          {
            'name': 'Aria',
            'armorClass': 16,
            'maxHp': 20,
            'hp': 12,
            'initiativeBonus': 2,
            'initiative': null,
            'attacks': <Object?>[],
          },
        ],
      });

      final restored = await Encounter.load(
        log: InMemoryLogRepository(),
        store: store,
      );

      final aria = restored.combatants.single;
      expect(aria.hp, 12);
      expect(aria.isPlayer, isFalse);
      expect(aria.isDead, isFalse);
      expect(aria.deathSaveFailures, 0);
    });
  });

  group('Wiederbeleben', () {
    /// Aria dies outright from massive damage.
    Future<void> ariaDies(Scene scene) =>
        scene.encounter.damage(scene.aria, 40);

    test('Ein toter Charakter kommt mit 1 Trefferpunkt zurück, wenn nichts '
        'anderes angegeben ist', () async {
      final scene = Scene([]);
      await ariaDies(scene);

      await scene.encounter.revive(scene.aria);

      expect(scene.aria.isDead, isFalse);
      expect(scene.aria.hp, 1);
      expect(scene.aria.isDown, isFalse);
    });

    test('Die Trefferpunkte nach dem Wiederbeleben lassen sich angeben, '
        'z. B. alle bei Auferstehung', () async {
      final scene = Scene([]);
      await ariaDies(scene);

      await scene.encounter.revive(scene.aria, hp: 20);

      expect(scene.aria.hp, 20);
    });

    test('Todesrettungswürfe und die Markierung stabil sind danach '
        'zurückgesetzt', () async {
      final scene = Scene([1, 1]);
      await scene.ariaDrops();
      await scene.deathSave();
      await scene.deathSave();
      expect(scene.aria.isDead, isTrue);

      await scene.encounter.revive(scene.aria);

      expect(scene.aria.deathSaveFailures, 0);
      expect(scene.aria.deathSaveSuccesses, 0);
      expect(scene.aria.isStable, isFalse);
    });

    test('Nur Tote lassen sich wiederbeleben', () async {
      final scene = Scene([]);
      await scene.ariaDrops();

      expect(() => scene.encounter.revive(scene.aria), throwsStateError);
      expect(scene.aria.hp, 0);
    });

    test('Trefferpunkte unter 1 oder über dem Maximum werden abgelehnt und '
        'ändern nichts', () async {
      final scene = Scene([]);
      await ariaDies(scene);
      final before = (await scene.events()).length;

      expect(
        () => scene.encounter.revive(scene.aria, hp: 0),
        throwsArgumentError,
      );
      expect(
        () => scene.encounter.revive(scene.aria, hp: 21),
        throwsArgumentError,
      );
      expect(scene.aria.isDead, isTrue);
      expect(await scene.events(), hasLength(before));
    });

    test('Ein wiederbelebter Charakter ist wieder in der Zugfolge', () async {
      final scene = Scene([10, 5]);
      await scene.encounter.rollInitiative();
      await ariaDies(scene);

      await scene.encounter.revive(scene.aria);

      expect(scene.aria.takesTurns, isTrue);
    });

    test('Das Wiederbeleben steht mit Trefferpunkten und Quelle im '
        'Log', () async {
      final scene = Scene([]);
      await ariaDies(scene);

      await scene.encounter.revive(scene.aria, source: 'Wiederbeleben');

      final event = (await scene.events()).last as CombatantRevivedEvent;
      expect(event.name, 'Aria');
      expect(event.hp, 1);
      expect(event.source, 'Wiederbeleben');
    });

    test('Der Zustand nach dem Wiederbeleben kommt nach dem Neustart '
        'zurück', () async {
      final scene = Scene([]);
      await ariaDies(scene);
      await scene.encounter.revive(scene.aria, hp: 5);
      await scene.encounter.flush();

      final restored = await Encounter.load(log: scene.log, store: scene.store);

      final aria = restored.combatants.first;
      expect(aria.isDead, isFalse);
      expect(aria.hp, 5);
    });
  });
}
