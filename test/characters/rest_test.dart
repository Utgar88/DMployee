import 'package:dmployee/characters/ability.dart';
import 'package:dmployee/characters/character.dart';
import 'package:dmployee/characters/character_repository.dart';
import 'package:dmployee/characters/rest.dart';
import 'package:dmployee/combat/encounter.dart';
import 'package:dmployee/dice/dice_roller.dart';
import 'package:dmployee/dice/modifier.dart';
import 'package:dmployee/log/log_event.dart';
import 'package:dmployee/log/log_repository.dart';
import 'package:dmployee/rules/ruleset.dart';
import 'package:dmployee/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixed_random.dart';

/// Rests with dice showing [faces] under [ruleset]. Aria: Kämpferin 5,
/// KON 14 (+2), 44 TP, W10. Borin: Kleriker 4, KON 8 (-1), 24 TP, W8.
class Scene {
  Scene({List<int> faces = const [], Ruleset ruleset = Ruleset.dnd2014}) {
    settings = AppSettings();
    settings.setRuleset(ruleset);
    encounter = Encounter(log: log, characters: characters);
    rests = RestService(
      characters: characters,
      log: log,
      settings: settings,
      encounter: encounter,
      roller: DiceRoller(FixedRandom(faces)),
    );
  }

  final log = InMemoryLogRepository();
  final characters = InMemoryCharacterRepository();
  late final AppSettings settings;
  late final Encounter encounter;
  late final RestService rests;

  Future<Character> aria({
    int hp = 44,
    int tempHp = 0,
    int hitDiceSpent = 0,
    bool stable = false,
    bool dead = false,
  }) => characters.save(
    Character(
        name: 'Aria',
        level: 5,
        abilityScores: {Ability.constitution: 14},
        maxHp: 44,
        armorClass: 18,
        hitDie: 10,
        hp: hp,
      )
      ..tempHp = tempHp
      ..hitDiceSpent = hitDiceSpent
      ..isStable = stable
      ..isDead = dead,
  );

  Future<Character> borin({int hp = 24, int hitDiceSpent = 0}) =>
      characters.save(
        Character(
          name: 'Borin',
          level: 4,
          abilityScores: {Ability.constitution: 8},
          maxHp: 24,
          armorClass: 16,
          hp: hp,
        )..hitDiceSpent = hitDiceSpent,
      );

  Future<Character> stored(Character character) async =>
      (await characters.byId(character.id!))!;

  Future<List<LogEvent>> events() async => [
    for (final entry in (await log.entries()).reversed) entry.event,
  ];
}

void main() {
  group('Lange Rast', () {
    test('Die TP gehen aufs Maximum, temporäre TP verfallen', () async {
      final scene = Scene();
      final aria = await scene.aria(hp: 12, tempHp: 5);

      await scene.rests.longRest([aria]);

      final stored = await scene.stored(aria);
      expect(stored.hp, 44);
      expect(stored.tempHp, 0);
    });

    test('2014: die Hälfte aller Trefferwürfel kommt zurück (Stufe 5: '
        '2)', () async {
      final scene = Scene();
      final aria = await scene.aria(hp: 12, hitDiceSpent: 4);

      await scene.rests.longRest([aria]);

      expect((await scene.stored(aria)).hitDiceRemaining, 3);
    });

    test('2014: es kommen nie mehr Trefferwürfel zurück als ausgegeben '
        'waren', () async {
      final scene = Scene();
      final aria = await scene.aria(hitDiceSpent: 1);

      await scene.rests.longRest([aria]);

      expect((await scene.stored(aria)).hitDiceSpent, 0);
    });

    test('2024: alle Trefferwürfel kommen zurück', () async {
      final scene = Scene(ruleset: Ruleset.dnd2024);
      final aria = await scene.aria(hp: 12, hitDiceSpent: 5);

      await scene.rests.longRest([aria]);

      expect((await scene.stored(aria)).hitDiceRemaining, 5);
    });

    test('Die lange Rast landet mit Regelwerk, TP und Trefferwürfeln vorher '
        'und nachher im Log', () async {
      final scene = Scene();
      final aria = await scene.aria(hp: 12, tempHp: 5, hitDiceSpent: 4);

      await scene.rests.longRest([aria]);

      final event = (await scene.events()).single as RestEvent;
      expect(event.kind, RestKind.long);
      expect(event.name, 'Aria');
      expect(event.ruleset, '5e-2014');
      expect(event.blocker, isNull);
      expect(event.hpBefore, 12);
      expect(event.hpAfter, 44);
      expect(event.maxHp, 44);
      expect(event.tempHpBefore, 5);
      expect(event.hitDiceBefore, 1);
      expect(event.hitDiceAfter, 3);
      expect(event.hitDiceTotal, 5);
    });

    test('Die ganze Gruppe rastet auf einmal, jeder mit eigenem '
        'Log-Eintrag', () async {
      final scene = Scene();
      final aria = await scene.aria(hp: 12);
      final borin = await scene.borin(hp: 3);

      await scene.rests.longRest([aria, borin]);

      expect((await scene.stored(aria)).hp, 44);
      expect((await scene.stored(borin)).hp, 24);
      expect(
        [for (final event in await scene.events()) (event as RestEvent).name],
        ['Aria', 'Borin'],
      );
    });

    test('Mit 0 TP bringt die lange Rast keinen Nutzen, auch stabil nicht; '
        'das steht im Log', () async {
      final scene = Scene();
      final aria = await scene.aria(hp: 0, stable: true, hitDiceSpent: 4);

      await scene.rests.longRest([aria]);

      final stored = await scene.stored(aria);
      expect(stored.hp, 0);
      expect(stored.hitDiceSpent, 4);
      expect(stored.isStable, isTrue);
      final event = (await scene.events()).single as RestEvent;
      expect(event.blocker, RestBlocker.tooFewHp);
    });

    test('Sterbende und tote Charaktere haben keinen Nutzen von der langen '
        'Rast', () async {
      final scene = Scene();
      final dying = await scene.aria(hp: 0);
      final dead = await scene.borin(hp: 0);
      await scene.characters.save(dead..isDead = true);

      await scene.rests.longRest([dying, dead]);

      expect((await scene.stored(dying)).hp, 0);
      expect((await scene.stored(dead)).hp, 0);
      expect(
        [
          for (final event in await scene.events())
            (event as RestEvent).blocker,
        ],
        [RestBlocker.dying, RestBlocker.dead],
      );
    });

    test('Ist der Charakter noch im Kampf, hat sein Kämpfer danach ebenfalls '
        'volle TP', () async {
      final scene = Scene();
      final aria = await scene.aria(hp: 12);
      final combatant = scene.encounter.addCharacter(aria);

      await scene.rests.longRest([aria]);
      await scene.encounter.flush();

      expect(combatant.hp, 44);
      expect((await scene.stored(aria)).hp, 44);
    });

    test('Während eines laufenden Kampfs ist keine Rast möglich', () async {
      final scene = Scene(faces: [10]);
      final aria = await scene.aria(hp: 12);
      scene.encounter.addCharacter(aria);
      await scene.encounter.rollInitiative();

      expect(() => scene.rests.longRest([aria]), throwsStateError);
      expect(() => scene.rests.shortRest([aria]), throwsStateError);
      expect(() => scene.rests.spendHitDie(aria), throwsStateError);
    });

    test('Die Rast nutzt das gerade eingestellte Regelwerk', () async {
      final scene = Scene();
      final aria = await scene.aria(hitDiceSpent: 5);
      await scene.settings.setRuleset(Ruleset.dnd2024);

      await scene.rests.longRest([aria]);

      expect((await scene.stored(aria)).hitDiceRemaining, 5);
    });
  });

  group('Kurze Rast', () {
    test('Die kurze Rast landet im Log und ändert noch nichts', () async {
      final scene = Scene();
      final aria = await scene.aria(hp: 12, hitDiceSpent: 1);

      await scene.rests.shortRest([aria]);

      final stored = await scene.stored(aria);
      expect(stored.hp, 12);
      expect(stored.hitDiceRemaining, 4);
      final event = (await scene.events()).single as RestEvent;
      expect(event.kind, RestKind.short);
      expect(event.blocker, isNull);
      expect(event.hitDiceAfter, 4);
    });

    test('2014: ein stabiler Charakter mit 0 TP kann kurz rasten', () async {
      final scene = Scene();
      final aria = await scene.aria(hp: 0, stable: true);

      await scene.rests.shortRest([aria]);

      expect(((await scene.events()).single as RestEvent).blocker, isNull);
      expect(scene.rests.blockerFor(aria, RestKind.short), isNull);
    });

    test('2024: mit 0 TP bringt auch die kurze Rast keinen Nutzen', () async {
      final scene = Scene(ruleset: Ruleset.dnd2024);
      final aria = await scene.aria(hp: 0, stable: true);

      await scene.rests.shortRest([aria]);

      expect(
        ((await scene.events()).single as RestEvent).blocker,
        RestBlocker.tooFewHp,
      );
    });

    test('Sterbende und tote Charaktere haben keinen Nutzen von der kurzen '
        'Rast', () async {
      final scene = Scene();
      final dying = await scene.aria(hp: 0);
      final dead = await scene.aria(hp: 0, dead: true);

      expect(scene.rests.blockerFor(dying, RestKind.short), RestBlocker.dying);
      expect(scene.rests.blockerFor(dead, RestKind.short), RestBlocker.dead);
    });
  });

  group('Trefferwürfel ausgeben', () {
    test('Ein Trefferwürfel heilt um Wurf plus KON-Modifikator und ist danach '
        'ausgegeben', () async {
      final scene = Scene(faces: [5]);
      final aria = await scene.aria(hp: 12);

      final after = await scene.rests.spendHitDie(aria);

      expect(after.hp, 19);
      expect(after.hitDiceRemaining, 4);
      final stored = await scene.stored(aria);
      expect(stored.hp, 19);
      expect(stored.hitDiceSpent, 1);
    });

    test('Gewürfelt wird mit dem Trefferwürfel des Charakters', () async {
      // FixedRandom rejects a 10 on anything smaller than a d10.
      final scene = Scene(faces: [10]);
      final aria = await scene.aria(hp: 12);

      final after = await scene.rests.spendHitDie(aria);

      expect(after.hp, 24);
    });

    test('Der Trefferwürfel landet mit Wurf, Heilung und übrigen '
        'Trefferwürfeln im Log', () async {
      final scene = Scene(faces: [5]);
      final aria = await scene.aria(hp: 12);

      await scene.rests.spendHitDie(aria);

      final event = (await scene.events()).single as HitDieEvent;
      expect(event.name, 'Aria');
      expect(event.ruleset, '5e-2014');
      expect(event.roll.dice, '1d10');
      expect(event.roll.rolls, [5]);
      expect(event.roll.modifiers, [const Modifier('Konstitution', 2)]);
      expect(event.healing, 7);
      expect(event.hpBefore, 12);
      expect(event.hpAfter, 19);
      expect(event.hitDiceLeft, 4);
      expect(event.hitDiceTotal, 5);
    });

    test(
      'Ein am Tisch gewürfelter Trefferwürfel lässt sich eintragen',
      () async {
        final scene = Scene();
        final aria = await scene.aria(hp: 12);

        final after = await scene.rests.spendHitDie(aria, manualFace: 8);

        expect(after.hp, 22);
        final event = (await scene.events()).single as HitDieEvent;
        expect(event.roll.manual, isTrue);
      },
    );

    test(
      'Ein unmöglicher Wert wird abgelehnt und nichts ändert sich',
      () async {
        final scene = Scene();
        final aria = await scene.aria(hp: 12);

        expect(
          () => scene.rests.spendHitDie(aria, manualFace: 11),
          throwsArgumentError,
        );
        expect(
          () => scene.rests.spendHitDie(aria, manualFace: 0),
          throwsArgumentError,
        );
        expect((await scene.stored(aria)).hitDiceSpent, 0);
        expect(await scene.events(), isEmpty);
      },
    );

    test('2014: ein negativer Gesamtwert heilt nicht, verbraucht den '
        'Trefferwürfel aber', () async {
      final scene = Scene(faces: [1]);
      final borin = await scene.borin(hp: 10);

      final after = await scene.rests.spendHitDie(borin);

      expect(after.hp, 10);
      expect(after.hitDiceSpent, 1);
      expect(((await scene.events()).single as HitDieEvent).healing, 0);
    });

    test('2024: ein Trefferwürfel heilt mindestens um 1', () async {
      final scene = Scene(faces: [1], ruleset: Ruleset.dnd2024);
      final borin = await scene.borin(hp: 10);

      final after = await scene.rests.spendHitDie(borin);

      expect(after.hp, 11);
    });

    test('Die Heilung endet beim Maximum', () async {
      final scene = Scene(faces: [10]);
      final aria = await scene.aria(hp: 40);

      final after = await scene.rests.spendHitDie(aria);

      expect(after.hp, 44);
    });

    test('Ohne übrige Trefferwürfel oder mit vollen TP wird nichts '
        'ausgegeben', () async {
      final scene = Scene(faces: [5]);
      final spent = await scene.aria(hp: 12, hitDiceSpent: 5);
      final unhurt = await scene.borin();

      expect(() => scene.rests.spendHitDie(spent), throwsStateError);
      expect(() => scene.rests.spendHitDie(unhurt), throwsStateError);
      expect(await scene.events(), isEmpty);
    });

    test('2014: ein stabiler Charakter mit 0 TP kommt durch einen '
        'Trefferwürfel wieder auf die Beine', () async {
      final scene = Scene(faces: [5]);
      final aria = await scene.aria(hp: 0, stable: true);
      await scene.characters.save(aria..deathSaveSuccesses = 3);

      final after = await scene.rests.spendHitDie(aria);

      expect(after.hp, 7);
      expect(after.isStable, isFalse);
      expect(after.deathSaveSuccesses, 0);
    });

    test('2024: mit 0 TP lässt sich kein Trefferwürfel ausgeben', () async {
      final scene = Scene(faces: [5], ruleset: Ruleset.dnd2024);
      final aria = await scene.aria(hp: 0, stable: true);

      expect(() => scene.rests.spendHitDie(aria), throwsStateError);
    });

    test('Sterbende und tote Charaktere können keine Trefferwürfel '
        'ausgeben', () async {
      final scene = Scene(faces: [5]);
      final dying = await scene.aria(hp: 0);
      final dead = await scene.borin(hp: 0);
      await scene.characters.save(dead..isDead = true);

      expect(() => scene.rests.spendHitDie(dying), throwsStateError);
      expect(() => scene.rests.spendHitDie(dead), throwsStateError);
    });

    test('Ist der Charakter noch im Kampf, bekommt sein Kämpfer die TP '
        'ebenfalls', () async {
      final scene = Scene(faces: [5]);
      final aria = await scene.aria(hp: 12);
      final combatant = scene.encounter.addCharacter(aria);

      await scene.rests.spendHitDie(aria);
      await scene.encounter.flush();

      expect(combatant.hp, 19);
      expect((await scene.stored(aria)).hitDiceSpent, 1);
    });
  });
}
