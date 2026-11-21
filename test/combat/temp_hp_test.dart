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

final scimitar = Attack(
  name: 'Krummsäbel',
  attackBonus: 4,
  damage: DiceExpression.parse('1d6+2'),
  damageType: 'Hieb',
);

/// An encounter whose dice show the given [faces] in order, with the player
/// character Aria (RK 16, 20 TP) and a Goblin (monster, RK 13, 7 TP,
/// Krummsäbel +4, 1d6+2 Hieb). The Goblin hits Aria with a d20 of 12 or
/// more.
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
    );
    goblin = encounter.add(
      name: 'Goblin',
      armorClass: 13,
      maxHp: 7,
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

  Future<AttackOutcome> goblinAttacksAria() =>
      encounter.attack(attacker: goblin, target: aria, attack: scimitar);
}

void main() {
  group('Temporäre Trefferpunkte: vergeben', () {
    test('Ein Kämpfer erhält temporäre Trefferpunkte zusätzlich zu seinen '
        'Trefferpunkten', () async {
      final scene = Scene([]);

      await scene.encounter.grantTempHp(scene.aria, 8);

      expect(scene.aria.tempHp, 8);
      expect(scene.aria.hp, 20);
    });

    test('Temporäre Trefferpunkte addieren sich nicht: höhere ersetzen '
        'niedrigere', () async {
      final scene = Scene([]);
      await scene.encounter.grantTempHp(scene.aria, 5);

      await scene.encounter.grantTempHp(scene.aria, 8);

      expect(scene.aria.tempHp, 8);
    });

    test('Niedrigere oder gleich hohe neue temporäre Trefferpunkte ändern '
        'nichts', () async {
      final scene = Scene([]);
      await scene.encounter.grantTempHp(scene.aria, 8);

      final event = await scene.encounter.grantTempHp(scene.aria, 5);

      expect(scene.aria.tempHp, 8);
      expect(event.kept, isTrue);
    });

    test('Ein Betrag unter 1 wird abgelehnt und ändert nichts', () async {
      final scene = Scene([]);

      expect(
        () => scene.encounter.grantTempHp(scene.aria, 0),
        throwsArgumentError,
      );
      expect(scene.aria.tempHp, 0);
      expect(await scene.events(), isEmpty);
    });

    test('Temporäre Trefferpunkte lassen sich wieder entfernen', () async {
      final scene = Scene([]);
      await scene.encounter.grantTempHp(scene.aria, 8);

      await scene.encounter.removeTempHp(scene.aria);

      expect(scene.aria.tempHp, 0);
    });

    test('Heilung stellt keine temporären Trefferpunkte wieder her', () async {
      final scene = Scene([]);
      await scene.encounter.grantTempHp(scene.aria, 5);
      await scene.encounter.damage(scene.aria, 10);

      await scene.encounter.heal(scene.aria, 20);

      expect(scene.aria.tempHp, 0);
      expect(scene.aria.hp, 20);
    });
  });

  group('Temporäre Trefferpunkte: Schaden', () {
    test('Schaden trifft zuerst die temporären Trefferpunkte', () async {
      final scene = Scene([]);
      await scene.encounter.grantTempHp(scene.aria, 8);

      await scene.encounter.damage(scene.aria, 5);

      expect(scene.aria.tempHp, 3);
      expect(scene.aria.hp, 20);
    });

    test('Übriger Schaden geht auf die Trefferpunkte', () async {
      final scene = Scene([]);
      await scene.encounter.grantTempHp(scene.aria, 8);

      await scene.encounter.damage(scene.aria, 12);

      expect(scene.aria.tempHp, 0);
      expect(scene.aria.hp, 16);
    });

    test('Ein Angriff trifft ebenso zuerst die temporären '
        'Trefferpunkte', () async {
      // d20 15 hits; d6 4 + 2 = 6.
      final scene = Scene([15, 4]);
      await scene.encounter.grantTempHp(scene.aria, 4);

      final outcome = await scene.goblinAttacksAria();

      expect(outcome.damage, 6);
      expect(outcome.event.tempHpAbsorbed, 4);
      expect(scene.aria.tempHp, 0);
      expect(scene.aria.hp, 18);
    });

    test('Resistenzen wirken vor den temporären Trefferpunkten', () async {
      final scene = Scene([]);
      scene.encounter.setDamageTrait(
        scene.aria,
        'Feuer',
        DamageEffect.resistance,
      );
      await scene.encounter.grantTempHp(scene.aria, 5);

      await scene.encounter.damage(scene.aria, 14, damageType: 'Feuer');

      expect(scene.aria.tempHp, 0);
      expect(scene.aria.hp, 18);
    });

    test('Fangen temporäre Trefferpunkte den Schaden bei 0 Trefferpunkten '
        'ganz ab, gibt es keinen Fehlschlag beim Todesrettungswurf', () async {
      final scene = Scene([]);
      await scene.encounter.damage(scene.aria, 20);
      await scene.encounter.grantTempHp(scene.aria, 5);

      await scene.encounter.damage(scene.aria, 3);

      expect(scene.aria.deathSaveFailures, 0);
      expect(scene.aria.tempHp, 2);
      expect(scene.aria.isDying, isTrue);
    });

    test('Übriger Schaden bei 0 Trefferpunkten zählt als Fehlschlag', () async {
      final scene = Scene([]);
      await scene.encounter.damage(scene.aria, 20);
      await scene.encounter.grantTempHp(scene.aria, 2);

      await scene.encounter.damage(scene.aria, 3);

      expect(scene.aria.deathSaveFailures, 1);
    });

    test('Temporäre Trefferpunkte holen einen Kämpfer bei 0 Trefferpunkten '
        'nicht zurück', () async {
      final scene = Scene([]);
      await scene.encounter.damage(scene.goblin, 7);

      await scene.encounter.grantTempHp(scene.goblin, 5);

      expect(scene.goblin.isDown, isTrue);
    });

    test('Für sofortigen Tod durch massiven Schaden zählt nur der Schaden '
        'nach den temporären Trefferpunkten', () async {
      // 45 damage - 10 temporary = 35: 20 to 0, 15 left < 20 maximum.
      final scene = Scene([]);
      await scene.encounter.grantTempHp(scene.aria, 10);

      await scene.encounter.damage(scene.aria, 45);

      expect(scene.aria.isDead, isFalse);
      expect(scene.aria.isDying, isTrue);
    });
  });

  group('Temporäre Trefferpunkte: Log und Speichern', () {
    test('Vergeben, Behalten und Entfernen stehen im Log', () async {
      final scene = Scene([]);

      await scene.encounter.grantTempHp(
        scene.aria,
        8,
        source: 'Falsches Leben',
      );
      await scene.encounter.grantTempHp(scene.aria, 5);
      await scene.encounter.removeTempHp(scene.aria);

      final events = (await scene.events()).cast<TempHpEvent>();
      expect(events.map((e) => (e.amount, e.tempHpBefore, e.tempHpAfter)), [
        (8, 0, 8),
        (5, 8, 8),
        (0, 8, 0),
      ]);
      expect(events.first.source, 'Falsches Leben');
      expect(events.first.name, 'Aria');
    });

    test('Entfernen ohne temporäre Trefferpunkte schreibt nichts in den '
        'Log', () async {
      final scene = Scene([]);

      await scene.encounter.removeTempHp(scene.aria);

      expect(await scene.events(), isEmpty);
    });

    test('Direkter Schaden hält fest, wie viel die temporären '
        'Trefferpunkte abgefangen haben', () async {
      final scene = Scene([]);
      await scene.encounter.grantTempHp(scene.aria, 8);

      final event = await scene.encounter.damage(scene.aria, 12);

      expect(event.tempHpBefore, 8);
      expect(event.tempHpAfter, 0);
      expect(event.hpAfter, 16);
    });

    test('Temporäre Trefferpunkte kommen nach dem Neustart zurück', () async {
      final scene = Scene([]);
      await scene.encounter.grantTempHp(scene.aria, 8);
      await scene.encounter.flush();

      final restored = await Encounter.load(log: scene.log, store: scene.store);

      expect(restored.combatants.first.tempHp, 8);
    });
  });
}
