import 'package:dmployee/characters/character.dart';
import 'package:dmployee/characters/character_repository.dart';
import 'package:dmployee/characters/exhaustion.dart';
import 'package:dmployee/combat/encounter.dart';
import 'package:dmployee/log/log_event.dart';
import 'package:dmployee/log/log_repository.dart';
import 'package:dmployee/rules/ruleset.dart';
import 'package:dmployee/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exhaustion of stored characters under [ruleset]. Aria: 40 TP.
class Scene {
  Scene({Ruleset ruleset = Ruleset.dnd2014}) {
    settings.setRuleset(ruleset);
    encounter = Encounter(log: log, characters: characters, settings: settings);
    exhaustion = ExhaustionService(
      characters: characters,
      log: log,
      settings: settings,
      encounter: encounter,
    );
  }

  final log = InMemoryLogRepository();
  final characters = InMemoryCharacterRepository();
  final settings = AppSettings();
  late final Encounter encounter;
  late final ExhaustionService exhaustion;

  Future<Character> aria({int? hp}) => characters.save(
    Character(name: 'Aria', maxHp: 40, armorClass: 16, hp: hp),
  );

  Future<Character> stored(Character character) async =>
      (await characters.byId(character.id!))!;

  Future<List<LogEvent>> events() async => [
    for (final entry in (await log.entries()).reversed) entry.event,
  ];
}

void main() {
  group('Erschöpfung außerhalb des Kampfs', () {
    test('Die Stufe wird gespeichert und mit Regelwerk geloggt', () async {
      final scene = Scene(ruleset: Ruleset.dnd2024);
      final aria = await scene.aria();

      final changed = await scene.exhaustion.set(aria, 2);

      expect(changed.exhaustion, 2);
      expect((await scene.stored(aria)).exhaustion, 2);
      final event = (await scene.events()).single as ExhaustionEvent;
      expect(event.before, 0);
      expect(event.after, 2);
      expect(event.ruleset, '5e-2024');
    });

    test('Dieselbe Stufe noch einmal schreibt nichts in den Log', () async {
      final scene = Scene();
      final aria = await scene.aria();
      await scene.exhaustion.set(aria, 1);

      await scene.exhaustion.set(aria, 1);

      expect(await scene.events(), hasLength(1));
    });

    test('Stufen außerhalb 0 bis 6 werden abgelehnt', () async {
      final scene = Scene();
      final aria = await scene.aria();

      expect(() => scene.exhaustion.set(aria, 7), throwsArgumentError);
      expect(() => scene.exhaustion.set(aria, -1), throwsArgumentError);
    });

    test('Stufe 6 tötet; der Log nennt die Erschöpfung als Ursache', () async {
      final scene = Scene();
      final aria = await scene.aria();

      await scene.exhaustion.set(aria, 6);

      final stored = await scene.stored(aria);
      expect(stored.isDead, isTrue);
      expect(stored.hp, 0);
      expect(
        (await scene.events()).last,
        isA<CombatantDiedEvent>().having(
          (e) => e.exhaustion,
          'exhaustion',
          true,
        ),
      );
    });

    test('Senken der Stufe belebt nicht wieder', () async {
      final scene = Scene();
      final aria = await scene.aria();
      await scene.exhaustion.set(aria, 6);

      await scene.exhaustion.set(aria, 5);

      expect((await scene.stored(aria)).isDead, isTrue);
    });

    test(
      '2014: Ab Stufe 4 sinken höhere TP auf das halbierte Maximum',
      () async {
        final scene = Scene();
        final aria = await scene.aria(hp: 30);

        await scene.exhaustion.set(aria, 4);

        expect((await scene.stored(aria)).hp, 20);
      },
    );

    test('2024: Die TP bleiben', () async {
      final scene = Scene(ruleset: Ruleset.dnd2024);
      final aria = await scene.aria(hp: 30);

      await scene.exhaustion.set(aria, 4);

      expect((await scene.stored(aria)).hp, 30);
    });
  });

  group('Erschöpfung eines Charakters im Kampf', () {
    test('Der Kämpfer ändert sich mit, der Charakter auch; nur ein '
        'Log-Eintrag', () async {
      final scene = Scene();
      final aria = await scene.aria();
      final combatant = scene.encounter.addCharacter(aria);

      final changed = await scene.exhaustion.set(aria, 3);

      expect(combatant.exhaustion, 3);
      expect(changed.exhaustion, 3);
      expect((await scene.stored(aria)).exhaustion, 3);
      expect(await scene.events(), hasLength(1));
    });

    test('Die TP aus dem Kampf bleiben erhalten', () async {
      final scene = Scene();
      final aria = await scene.aria();
      final combatant = scene.encounter.addCharacter(aria);
      await scene.encounter.damage(combatant, 15);

      final changed = await scene.exhaustion.set(aria, 1);

      expect(changed.hp, 25);
    });
  });
}
