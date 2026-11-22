import 'package:dmployee/characters/ability.dart';
import 'package:dmployee/characters/character.dart';
import 'package:dmployee/characters/character_repository.dart';
import 'package:dmployee/combat/attack.dart';
import 'package:dmployee/combat/encounter.dart';
import 'package:dmployee/combat/encounter_store.dart';
import 'package:dmployee/dice/dice_expression.dart';
import 'package:dmployee/dice/dice_roller.dart';
import 'package:dmployee/log/log_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixed_random.dart';

final longsword = Attack(
  name: 'Langschwert',
  attackBonus: 6,
  damage: DiceExpression.parse('1d8+3'),
  damageType: 'Hieb',
);

final scimitar = Attack(
  name: 'Krummsäbel',
  attackBonus: 4,
  damage: DiceExpression.parse('1d6+2'),
  damageType: 'Hieb',
);

/// An encounter with dice showing [faces], a character repository holding
/// Aria (Kämpferin 5, GE 14, 44 TP, RK 18, Langschwert) and a Goblin
/// monster (RK 13, 7 TP, Krummsäbel) that is already in the encounter.
class Scene {
  Scene([List<int> faces = const []]) {
    encounter = Encounter(
      log: log,
      store: store,
      characters: characters,
      roller: DiceRoller(FixedRandom(faces)),
    );
  }

  final log = InMemoryLogRepository();
  final store = InMemoryEncounterStore();
  final characters = InMemoryCharacterRepository();
  late final Encounter encounter;

  Future<Character> saveAria() => characters.save(
    Character(
      name: 'Aria',
      characterClass: 'Kämpferin',
      level: 5,
      abilityScores: {Ability.dexterity: 14},
      maxHp: 44,
      armorClass: 18,
      attacks: [longsword],
    ),
  );

  /// The stored character, as the character screen would load it.
  Future<Character> stored(Character character) async =>
      (await characters.byId(character.id!))!;
}

void main() {
  group('Charakter in den Kampf übernehmen', () {
    test('Der Kämpfer übernimmt Name, RK, TP, Initiative-Bonus und Angriffe '
        'und ist ein Spielercharakter', () async {
      final scene = Scene();
      final aria = await scene.saveAria();

      final combatant = scene.encounter.addCharacter(aria);

      expect(combatant.name, 'Aria');
      expect(combatant.armorClass, 18);
      expect(combatant.maxHp, 44);
      expect(combatant.hp, 44);
      expect(combatant.initiativeBonus, 2);
      expect(combatant.attacks.single.name, 'Langschwert');
      expect(combatant.isPlayer, isTrue);
      expect(combatant.characterId, aria.id);
      expect(scene.encounter.combatants, [combatant]);
    });

    test('Der aktuelle Zustand des Charakters kommt mit: TP, temporäre TP '
        'und Todesrettungswürfe', () async {
      final scene = Scene();
      final aria = await scene.saveAria()
        ..hp = 0
        ..tempHp = 3
        ..deathSaveFailures = 1;

      final combatant = scene.encounter.addCharacter(aria);

      expect(combatant.hp, 0);
      expect(combatant.tempHp, 3);
      expect(combatant.deathSaveFailures, 1);
      expect(combatant.isDying, isTrue);
    });

    test('Ein Charakter kann nur einmal im Kampf sein', () async {
      final scene = Scene();
      final aria = await scene.saveAria();
      scene.encounter.addCharacter(aria);

      expect(() => scene.encounter.addCharacter(aria), throwsStateError);
      expect(scene.encounter.combatants, hasLength(1));
      expect(scene.encounter.hasCharacter(aria.id!), isTrue);
    });

    test('Ein ungespeicherter Charakter ohne Kennung wird abgelehnt', () {
      final scene = Scene();

      expect(
        () => scene.encounter.addCharacter(
          Character(name: 'Borin', maxHp: 12, armorClass: 15),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Was im Kampf passiert, gilt für den Charakter', () {
    test('Schaden und temporäre TP landen beim gespeicherten '
        'Charakter', () async {
      final scene = Scene();
      final aria = await scene.saveAria();
      final combatant = scene.encounter.addCharacter(aria);

      await scene.encounter.grantTempHp(combatant, 5);
      await scene.encounter.damage(combatant, 12);
      await scene.encounter.flush();

      final stored = await scene.stored(aria);
      expect(stored.hp, 37);
      expect(stored.tempHp, 0);
    });

    test('Ein Treffer eines Monsters landet beim Charakter', () async {
      // d20 15 hits RK 18 (15 + 4 = 19); d6 3 + 2 = 5.
      final scene = Scene([15, 3]);
      final aria = await scene.saveAria();
      final combatant = scene.encounter.addCharacter(aria);
      final goblin = scene.encounter.add(
        name: 'Goblin',
        armorClass: 13,
        maxHp: 7,
        attacks: [scimitar],
      );

      await scene.encounter.attack(
        attacker: goblin,
        target: combatant,
        attack: scimitar,
      );
      await scene.encounter.flush();

      expect((await scene.stored(aria)).hp, 39);
    });

    test('Todesrettungswürfe, stabil und tot landen beim Charakter', () async {
      final scene = Scene([12, 1]);
      final aria = await scene.saveAria();
      final combatant = scene.encounter.addCharacter(aria);

      await scene.encounter.damage(combatant, 44);
      await scene.encounter.rollDeathSave(combatant);
      await scene.encounter.rollDeathSave(combatant);
      await scene.encounter.flush();

      var stored = await scene.stored(aria);
      expect(stored.hp, 0);
      expect(stored.deathSaveSuccesses, 1);
      expect(stored.deathSaveFailures, 2);

      await scene.encounter.damage(combatant, 1);
      await scene.encounter.flush();
      stored = await scene.stored(aria);
      expect(stored.isDead, isTrue);
    });

    test('Nach dem Entfernen aus dem Kampf behält der Charakter seinen '
        'Zustand', () async {
      final scene = Scene();
      final aria = await scene.saveAria();
      final combatant = scene.encounter.addCharacter(aria);
      await scene.encounter.damage(combatant, 10);

      scene.encounter.remove(combatant);
      await scene.encounter.flush();

      expect((await scene.stored(aria)).hp, 34);
      expect(scene.encounter.hasCharacter(aria.id!), isFalse);
    });

    test('Bei einem erneuten Kampf geht es mit dem gespeicherten Zustand '
        'weiter', () async {
      final scene = Scene();
      final aria = await scene.saveAria();
      final combatant = scene.encounter.addCharacter(aria);
      await scene.encounter.damage(combatant, 10);
      scene.encounter.remove(combatant);
      await scene.encounter.flush();

      final again = scene.encounter.addCharacter(await scene.stored(aria));

      expect(again.hp, 34);
    });

    test('Die Werte des Charakterbogens ändert der Kampf nicht', () async {
      final scene = Scene();
      final aria = await scene.saveAria();
      final combatant = scene.encounter.addCharacter(aria);

      await scene.encounter.damage(combatant, 10);
      await scene.encounter.flush();

      final stored = await scene.stored(aria);
      expect(stored.maxHp, 44);
      expect(stored.armorClass, 18);
      expect(stored.classAndLevel, 'Kämpferin 5');
    });

    test('Monster werden nicht als Charaktere gespeichert', () async {
      final scene = Scene();
      final goblin = scene.encounter.add(
        name: 'Goblin',
        armorClass: 13,
        maxHp: 7,
      );

      await scene.encounter.damage(goblin, 3);
      await scene.encounter.flush();

      expect(await scene.characters.all(), isEmpty);
    });
  });

  group('Geänderter Charakterbogen im laufenden Kampf', () {
    test('Der Kämpfer übernimmt Name, RK, maximale TP, Initiative-Bonus und '
        'Angriffe', () async {
      final scene = Scene();
      final aria = await scene.saveAria();
      final combatant = scene.encounter.addCharacter(aria);

      final changed = aria.withValues(
        name: 'Arya',
        armorClass: 19,
        maxHp: 50,
        abilityScores: {Ability.dexterity: 16},
        attacks: [longsword, scimitar],
      );
      scene.encounter.applyCharacter(changed);

      expect(combatant.name, 'Arya');
      expect(combatant.armorClass, 19);
      expect(combatant.maxHp, 50);
      expect(combatant.hp, 50);
      expect(combatant.initiativeBonus, 3);
      expect(combatant.attacks.map((a) => a.name), [
        'Langschwert',
        'Krummsäbel',
      ]);
    });

    test('Die Trefferpunkte aus dem Kampf bleiben, höchstens das neue '
        'Maximum', () async {
      final scene = Scene();
      final aria = await scene.saveAria();
      final combatant = scene.encounter.addCharacter(aria);
      await scene.encounter.damage(combatant, 10);

      // The sheet was opened before the damage, so it still shows 44 TP.
      scene.encounter.applyCharacter(aria.withValues(armorClass: 19));
      await scene.encounter.flush();

      expect(combatant.hp, 34);
      expect((await scene.stored(aria)).hp, 34);
    });

    test('Ein Charakter, der nicht im Kampf ist, ändert nichts', () async {
      final scene = Scene();
      final aria = await scene.saveAria();

      scene.encounter.applyCharacter(aria.withValues(name: 'Arya'));

      expect(scene.encounter.combatants, isEmpty);
    });

    test('Nach dem Löschen des Charakters bleibt der Kämpfer im Kampf, '
        'ist aber nicht mehr verknüpft', () async {
      final scene = Scene();
      final aria = await scene.saveAria();
      final combatant = scene.encounter.addCharacter(aria);

      await scene.characters.delete(aria.id!);
      scene.encounter.forgetCharacter(aria.id!);
      await scene.encounter.damage(combatant, 5);
      await scene.encounter.flush();

      expect(combatant.characterId, isNull);
      expect(scene.encounter.combatants, [combatant]);
      expect(await scene.characters.all(), isEmpty);
    });
  });

  group('Verknüpfung speichern', () {
    test('Die Verknüpfung zum Charakter übersteht den Neustart', () async {
      final scene = Scene();
      final aria = await scene.saveAria();
      scene.encounter.addCharacter(aria);
      await scene.encounter.flush();

      final restored = await Encounter.load(
        log: scene.log,
        store: scene.store,
        characters: scene.characters,
      );
      await restored.damage(restored.combatants.single, 4);
      await restored.flush();

      expect(restored.combatants.single.characterId, aria.id);
      expect(restored.hasCharacter(aria.id!), isTrue);
      expect((await scene.stored(aria)).hp, 40);
    });
  });

  group('Zustand nach einer Rast übernehmen', () {
    test('Der Kämpfer übernimmt TP, temporäre TP, Todesrettungswürfe, stabil '
        'und tot vom Charakter; der Log bleibt leer', () async {
      final scene = Scene();
      final aria = await scene.saveAria();
      final combatant = scene.encounter.addCharacter(aria);
      await scene.encounter.damage(combatant, 30);
      await scene.encounter.flush();
      final logBefore = (await scene.log.entries()).length;

      final rested = (await scene.stored(aria))
        ..hp = 44
        ..tempHp = 0;
      scene.encounter.takeCharacterState(rested);
      await scene.encounter.flush();

      expect(combatant.hp, 44);
      expect(combatant.tempHp, 0);
      expect(combatant.isDown, isFalse);
      expect(await scene.log.entries(), hasLength(logBefore));
    });

    test('Das Übernehmen behält die übrigen Werte des gespeicherten '
        'Charakters, z.B. ausgegebene Trefferwürfel', () async {
      final scene = Scene();
      final aria = await scene.saveAria();
      scene.encounter.addCharacter(aria);
      final rested = (await scene.stored(aria))
        ..hp = 40
        ..hitDiceSpent = 2;
      await scene.characters.save(rested);

      scene.encounter.takeCharacterState(rested);
      await scene.encounter.flush();

      final stored = await scene.stored(aria);
      expect(stored.hp, 40);
      expect(stored.hitDiceSpent, 2);
    });

    test('Ein Charakter, der nicht im Kampf ist, ändert nichts', () async {
      final scene = Scene();
      final aria = await scene.saveAria();
      final goblin = scene.encounter.add(
        name: 'Goblin',
        armorClass: 13,
        maxHp: 7,
      );

      scene.encounter.takeCharacterState(aria..hp = 1);

      expect(scene.encounter.combatants, [goblin]);
      expect(goblin.hp, 7);
    });
  });
}
