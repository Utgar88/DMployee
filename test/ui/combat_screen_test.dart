import 'package:dmployee/combat/attack.dart';
import 'package:dmployee/combat/combatant.dart';
import 'package:dmployee/combat/encounter.dart';
import 'package:dmployee/combat/encounter_store.dart';
import 'package:dmployee/dice/dice_expression.dart';
import 'package:dmployee/dice/dice_roller.dart';
import 'package:dmployee/log/log_event.dart';
import 'package:dmployee/log/log_repository.dart';
import 'package:dmployee/ui/combat_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fixed_random.dart';

final longsword = Attack(
  name: 'Langschwert',
  attackBonus: 5,
  damage: DiceExpression.parse('1d8+3'),
  damageType: 'Hieb',
);

/// Combat screen with dice showing [faces] in order. With [prepared], Aria
/// (RK 16, 20 TP, Initiative +2, Langschwert) and a Goblin (RK 13, 7 TP,
/// Initiative +1) are already in the encounter.
class Scene {
  Scene(List<int> faces, {bool prepared = true}) {
    encounter = Encounter(
      log: log,
      store: store,
      roller: DiceRoller(FixedRandom(faces)),
    );
    if (prepared) {
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
  }

  final log = InMemoryLogRepository();
  final store = InMemoryEncounterStore();
  late final Encounter encounter;
  late final Combatant aria;
  late final Combatant goblin;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: CombatScreen(encounter: encounter)),
    );
    await tester.pumpAndSettle();
  }

  Future<List<LogEvent>> events() async =>
      (await log.entries()).reversed.map((entry) => entry.event).toList();

  /// The combat as the app finds it after a restart.
  Future<Encounter> reopen() async {
    await encounter.flush();
    return Encounter.load(log: log, store: store);
  }
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> type(WidgetTester tester, String key, String text) =>
    tester.enterText(find.byKey(Key(key)), text);

String textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

/// Starts the combat with Aria first (initiative 12) and the Goblin second
/// (initiative 6). Uses the first two dice of the scene.
Future<void> startCombat(WidgetTester tester) async {
  await tapKey(tester, 'roll-initiative');
  await tapKey(tester, 'initiative-confirm');
}

/// Aria (first tile) attacks the Goblin (second tile) with her first attack.
Future<void> openAttack(WidgetTester tester) => tapKey(tester, 'attack-0-0');

void main() {
  group('Kampf-Bildschirm: Kämpfer anlegen', () {
    testWidgets('Ohne Kämpfer steht ein Hinweis da', (tester) async {
      await Scene([], prepared: false).pump(tester);

      expect(find.text('Noch keine Kämpfer'), findsOneWidget);
    });

    testWidgets('Ein Kämpfer mit Name, Rüstungsklasse, Trefferpunkten und '
        'hinterlegtem Angriff lässt sich anlegen', (tester) async {
      final scene = Scene([], prepared: false);
      await scene.pump(tester);

      await tapKey(tester, 'add-combatant');
      await type(tester, 'combatant-name', 'Aria');
      await type(tester, 'combatant-ac', '16');
      await type(tester, 'combatant-hp', '20');
      await type(tester, 'combatant-init', '2');
      await type(tester, 'attack-name', 'Langschwert');
      await type(tester, 'attack-bonus', '5');
      await type(tester, 'attack-damage', '1d8+3');
      await type(tester, 'attack-type', 'Hieb');
      await tapKey(tester, 'combatant-save');

      final aria = scene.encounter.combatants.single;
      expect(aria.name, 'Aria');
      expect(aria.armorClass, 16);
      expect(aria.maxHp, 20);
      expect(aria.initiativeBonus, 2);
      expect(aria.attacks.single.summary, 'Langschwert +5, 1d8+3 Hieb');
      expect(textOf(tester, 'name-0'), 'Aria');
      expect(textOf(tester, 'stats-0'), 'RK 16 · TP 20/20');
    });

    testWidgets('Ein Kämpfer ohne Angriff ist erlaubt', (tester) async {
      final scene = Scene([], prepared: false);
      await scene.pump(tester);

      await tapKey(tester, 'add-combatant');
      await type(tester, 'combatant-name', 'Dorfbewohner');
      await type(tester, 'combatant-ac', '10');
      await type(tester, 'combatant-hp', '4');
      await tapKey(tester, 'combatant-save');

      expect(scene.encounter.combatants.single.attacks, isEmpty);
    });

    testWidgets('Fehlt der Name oder ein Pflichtwert, wird nichts angelegt '
        'und ein Hinweis erscheint', (tester) async {
      final scene = Scene([], prepared: false);
      await scene.pump(tester);

      await tapKey(tester, 'add-combatant');
      await type(tester, 'combatant-ac', '16');
      await tapKey(tester, 'combatant-save');

      expect(scene.encounter.combatants, isEmpty);
      expect(find.byKey(const Key('form-error')), findsOneWidget);
    });

    testWidgets('Ein Schadenswert, der kein Würfelausdruck ist, wird '
        'abgelehnt', (tester) async {
      final scene = Scene([], prepared: false);
      await scene.pump(tester);

      await tapKey(tester, 'add-combatant');
      await type(tester, 'combatant-name', 'Aria');
      await type(tester, 'combatant-ac', '16');
      await type(tester, 'combatant-hp', '20');
      await type(tester, 'attack-name', 'Langschwert');
      await type(tester, 'attack-damage', 'viel');
      await tapKey(tester, 'combatant-save');

      expect(scene.encounter.combatants, isEmpty);
      expect(find.byKey(const Key('form-error')), findsOneWidget);
    });

    testWidgets('Einem vorhandenen Kämpfer lässt sich ein weiterer Angriff '
        'hinterlegen', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'add-attack-1');
      await type(tester, 'attack-name', 'Krummsäbel');
      await type(tester, 'attack-bonus', '4');
      await type(tester, 'attack-damage', '1d6+2');
      await type(tester, 'attack-type', 'Hieb');
      await tapKey(tester, 'attack-save');

      expect(scene.goblin.attacks.single.summary, 'Krummsäbel +4, 1d6+2 Hieb');
      expect(find.byKey(const Key('attack-1-0')), findsOneWidget);
    });

    testWidgets('Ein Kämpfer lässt sich vor dem Kampf wieder entfernen', (
      tester,
    ) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'remove-1');

      expect(scene.encounter.combatants, [scene.aria]);
      expect(find.text('Goblin'), findsNothing);
    });
  });

  group('Kampf-Bildschirm: Initiative und Züge', () {
    testWidgets('Nach dem Initiativewurf stehen die Kämpfer in Zugfolge, '
        'Runde 1 läuft und der Erste ist am Zug', (tester) async {
      // Aria 3 + 2 = 5, Goblin 15 + 1 = 16.
      final scene = Scene([3, 15]);
      await scene.pump(tester);

      await startCombat(tester);

      expect(textOf(tester, 'round'), 'Runde 1');
      expect(textOf(tester, 'name-0'), 'Goblin');
      expect(textOf(tester, 'name-1'), 'Aria');
      expect(textOf(tester, 'initiative-0'), 'Initiative 16');
      expect(
        find.descendant(
          of: find.byKey(const Key('combatant-0')),
          matching: find.text('am Zug'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Ein von Hand eingetragener Initiativewurf wird übernommen', (
      tester,
    ) async {
      final scene = Scene([5]);
      await scene.pump(tester);

      await tapKey(tester, 'roll-initiative');
      await type(tester, 'manual-init-0', '18');
      await tapKey(tester, 'initiative-confirm');

      expect(scene.aria.initiative, 20);
      expect(scene.goblin.initiative, 6);
    });

    testWidgets('"Nächster Zug" gibt weiter, nach dem Letzten beginnt '
        'Runde 2', (tester) async {
      final scene = Scene([10, 5]);
      await scene.pump(tester);
      await startCombat(tester);

      await tapKey(tester, 'next-turn');
      expect(scene.encounter.current, scene.goblin);
      expect(
        find.descendant(
          of: find.byKey(const Key('combatant-1')),
          matching: find.text('am Zug'),
        ),
        findsOneWidget,
      );

      await tapKey(tester, 'next-turn');
      expect(textOf(tester, 'round'), 'Runde 2');
    });

    testWidgets('"Kampf beenden" führt zurück zur Vorbereitung', (
      tester,
    ) async {
      final scene = Scene([10, 5]);
      await scene.pump(tester);
      await startCombat(tester);

      await tapKey(tester, 'end-combat');

      expect(scene.encounter.isRunning, isFalse);
      expect(find.byKey(const Key('roll-initiative')), findsOneWidget);
      expect(find.byKey(const Key('round')), findsNothing);
    });
  });

  group('Kampf-Bildschirm: Angriff', () {
    testWidgets('Angriff antippen und Ziel wählen genügt: ein Treffer zieht '
        'dem Ziel die Trefferpunkte ab und wird angezeigt', (tester) async {
      final scene = Scene([15, 2]);
      await scene.pump(tester);

      await openAttack(tester);
      await tapKey(tester, 'target-1');

      expect(scene.goblin.hp, 2);
      expect(textOf(tester, 'stats-1'), 'RK 13 · TP 2/7');
      expect(
        textOf(tester, 'last-action'),
        'Aria hat Goblin für 5 Schaden getroffen',
      );
    });

    testWidgets('Der Angreifer selbst steht nicht als Ziel zur Wahl', (
      tester,
    ) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await openAttack(tester);

      expect(find.byKey(const Key('target-0')), findsNothing);
      expect(find.byKey(const Key('target-1')), findsOneWidget);
    });

    testWidgets('Ein Fehlschlag lässt die Trefferpunkte unverändert', (
      tester,
    ) async {
      final scene = Scene([2]);
      await scene.pump(tester);

      await openAttack(tester);
      await tapKey(tester, 'target-1');

      expect(scene.goblin.hp, 7);
      expect(textOf(tester, 'last-action'), 'Aria hat Goblin mit 7 verfehlt');
    });

    testWidgets('Vorteil lässt sich vor der Zielwahl einstellen', (
      tester,
    ) async {
      final scene = Scene([3, 15, 2]);
      await scene.pump(tester);

      await openAttack(tester);
      await tapKey(tester, 'attack-mode-advantage');
      await tapKey(tester, 'target-1');

      final event = (await scene.events()).first as AttackEvent;
      expect(event.attackRoll.mode, RollMode.advantage);
      expect(event.attackRoll.rolls, [3, 15]);
      expect(event.hit, isTrue);
    });

    testWidgets('Angriffswurf und Schadenswürfel lassen sich von Hand '
        'eintragen', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await openAttack(tester);
      await type(tester, 'manual-attack', '12');
      await type(tester, 'manual-damage', '4');
      await tapKey(tester, 'target-1');

      final event = (await scene.events()).first as AttackEvent;
      expect(event.attackRoll.manual, isTrue);
      expect(event.damageRoll!.manual, isTrue);
      expect(scene.goblin.hp, 0);
    });

    testWidgets('Ein unmöglicher eingetragener Wert wird abgelehnt: das '
        'Fenster bleibt offen und nichts ändert sich', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await openAttack(tester);
      await type(tester, 'manual-attack', '25');
      await tapKey(tester, 'target-1');

      expect(find.byKey(const Key('form-error')), findsOneWidget);
      expect(scene.goblin.hp, 7);
      expect(await scene.events(), isEmpty);
    });

    testWidgets('Ein Kämpfer mit 0 Trefferpunkten ist als "am Boden" '
        'markiert', (tester) async {
      final scene = Scene([15, 8]);
      await scene.pump(tester);

      await openAttack(tester);
      await tapKey(tester, 'target-1');

      expect(textOf(tester, 'stats-1'), 'RK 13 · TP 0/7');
      expect(
        find.descendant(
          of: find.byKey(const Key('combatant-1')),
          matching: find.text('am Boden'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Jeder Angriff steht im Log', (tester) async {
      final scene = Scene([15, 8]);
      await scene.pump(tester);

      await openAttack(tester);
      await tapKey(tester, 'target-1');

      final events = await scene.events();
      expect(events.first, isA<AttackEvent>());
      expect(events.last, isA<CombatantDownEvent>());
    });
  });

  group('Kampf-Bildschirm: Trefferpunkte direkt ändern', () {
    testWidgets('Über "TP ändern" lässt sich Schaden eintragen, die '
        'Trefferpunkte sinken und die Änderung wird angezeigt', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'hp-1');
      await type(tester, 'hp-amount', '3');
      await tapKey(tester, 'hp-damage');

      expect(textOf(tester, 'stats-1'), 'RK 13 · TP 4/7');
      expect(textOf(tester, 'last-action'), 'Goblin erleidet 3 Schaden');
    });

    testWidgets('Über "TP ändern" lässt sich Heilung eintragen, die '
        'Trefferpunkte steigen', (tester) async {
      final scene = Scene([]);
      scene.aria.hp = 5;
      await scene.pump(tester);

      await tapKey(tester, 'hp-0');
      await type(tester, 'hp-amount', '4');
      await tapKey(tester, 'hp-heal');

      expect(textOf(tester, 'stats-0'), 'RK 16 · TP 9/20');
      expect(textOf(tester, 'last-action'), 'Aria wird um 4 TP geheilt');
    });

    testWidgets('Eine eingetragene Quelle landet im Log', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'hp-1');
      await type(tester, 'hp-amount', '3');
      await type(tester, 'hp-source', 'Feuerball');
      await tapKey(tester, 'hp-damage');

      final event = (await scene.events()).single as HpChangeEvent;
      expect(event.source, 'Feuerball');
      expect(event.amount, 3);
    });

    testWidgets('Ohne Betrag bleibt das Fenster offen, es erscheint eine '
        'Meldung und nichts ändert sich', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'hp-1');
      await tapKey(tester, 'hp-damage');

      expect(find.byKey(const Key('form-error')), findsOneWidget);
      expect(scene.goblin.hp, 7);
      expect(await scene.events(), isEmpty);
    });

    testWidgets('Ein Betrag von 0 wird abgelehnt', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'hp-1');
      await type(tester, 'hp-amount', '0');
      await tapKey(tester, 'hp-heal');

      expect(find.byKey(const Key('form-error')), findsOneWidget);
      expect(await scene.events(), isEmpty);
    });

    testWidgets('Schaden bis 0 markiert den Kämpfer als "am Boden", Heilung '
        'hebt die Markierung wieder auf', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);
      final downBadge = find.descendant(
        of: find.byKey(const Key('combatant-1')),
        matching: find.text('am Boden'),
      );

      await tapKey(tester, 'hp-1');
      await type(tester, 'hp-amount', '7');
      await tapKey(tester, 'hp-damage');
      expect(downBadge, findsOneWidget);

      await tapKey(tester, 'hp-1');
      await type(tester, 'hp-amount', '2');
      await tapKey(tester, 'hp-heal');
      expect(downBadge, findsNothing);
      expect(textOf(tester, 'stats-1'), 'RK 13 · TP 2/7');
    });

    testWidgets('Die Trefferpunkte lassen sich auch im laufenden Kampf '
        'ändern', (tester) async {
      final scene = Scene([10, 5]);
      await scene.pump(tester);
      await startCombat(tester);

      await tapKey(tester, 'hp-1');
      await type(tester, 'hp-amount', '2');
      await tapKey(tester, 'hp-damage');

      expect(textOf(tester, 'stats-1'), 'RK 13 · TP 5/7');
    });
  });

  group('Kampf-Bildschirm: Kampfstand speichern', () {
    testWidgets('Ein über das Fenster angelegter Kämpfer ist nach dem '
        'Neustart noch da', (tester) async {
      final scene = Scene([], prepared: false);
      await scene.pump(tester);

      await tapKey(tester, 'add-combatant');
      await type(tester, 'combatant-name', 'Aria');
      await type(tester, 'combatant-ac', '16');
      await type(tester, 'combatant-hp', '20');
      await tapKey(tester, 'combatant-save');

      final restored = await scene.reopen();
      expect(restored.combatants.single.name, 'Aria');
    });

    testWidgets('Ein über das Fenster hinterlegter Angriff ist nach dem '
        'Neustart noch da', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'add-attack-1');
      await type(tester, 'attack-name', 'Krummsäbel');
      await type(tester, 'attack-bonus', '4');
      await type(tester, 'attack-damage', '1d6+2');
      await tapKey(tester, 'attack-save');

      final restored = await scene.reopen();
      expect(restored.combatants.last.attacks.single.name, 'Krummsäbel');
    });

    testWidgets('Über "TP ändern" eingetragener Schaden ist nach dem '
        'Neustart noch da', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'hp-1');
      await type(tester, 'hp-amount', '3');
      await tapKey(tester, 'hp-damage');

      final restored = await scene.reopen();
      expect(restored.combatants.last.hp, 4);
    });

    testWidgets('Ein laufender Kampf ist nach dem Neustart noch in '
        'derselben Runde', (tester) async {
      final scene = Scene([10, 5]);
      await scene.pump(tester);
      await startCombat(tester);
      await tapKey(tester, 'next-turn');
      await tapKey(tester, 'next-turn');

      final restored = await scene.reopen();
      expect(restored.round, 2);
      expect(restored.current!.name, 'Aria');
    });
  });

  group('Kampf-Bildschirm: Todesrettungswürfe', () {
    /// Aria is a player character at 0 hit points.
    Scene dyingAria(List<int> faces) {
      final scene = Scene(faces);
      scene.aria
        ..isPlayer = true
        ..hp = 0;
      return scene;
    }

    final saveButton = find.byKey(const Key('death-save-0'));

    testWidgets('Beim Anlegen lässt sich ein Kämpfer als Spielercharakter '
        'kennzeichnen', (tester) async {
      final scene = Scene([], prepared: false);
      await scene.pump(tester);

      await tapKey(tester, 'add-combatant');
      await type(tester, 'combatant-name', 'Aria');
      await type(tester, 'combatant-ac', '16');
      await type(tester, 'combatant-hp', '20');
      await tapKey(tester, 'combatant-player');
      await tapKey(tester, 'combatant-save');

      expect(scene.encounter.combatants.single.isPlayer, isTrue);
    });

    testWidgets('Ohne Kennzeichnung ist ein neuer Kämpfer kein '
        'Spielercharakter', (tester) async {
      final scene = Scene([], prepared: false);
      await scene.pump(tester);

      await tapKey(tester, 'add-combatant');
      await type(tester, 'combatant-name', 'Goblin');
      await type(tester, 'combatant-ac', '13');
      await type(tester, 'combatant-hp', '7');
      await tapKey(tester, 'combatant-save');

      expect(scene.encounter.combatants.single.isPlayer, isFalse);
    });

    testWidgets('Ein sterbender Spielercharakter zeigt den Stand der '
        'Todesrettungswürfe und einen Knopf für den Wurf', (tester) async {
      await dyingAria([]).pump(tester);

      expect(
        textOf(tester, 'death-saves-0'),
        'Todesrettungswürfe: Erfolge 0 · Fehlschläge 0',
      );
      expect(saveButton, findsOneWidget);
    });

    testWidgets('Ein Monster am Boden und ein Charakter mit Trefferpunkten '
        'haben keinen Knopf für den Todesrettungswurf', (tester) async {
      final scene = Scene([]);
      scene.aria.isPlayer = true;
      scene.goblin.hp = 0;
      await scene.pump(tester);

      expect(saveButton, findsNothing);
      expect(find.byKey(const Key('death-save-1')), findsNothing);
    });

    testWidgets('Der Wurf wird gewürfelt, gezählt und angezeigt', (
      tester,
    ) async {
      final scene = dyingAria([12]);
      await scene.pump(tester);

      await tapKey(tester, 'death-save-0');
      await tapKey(tester, 'death-save-confirm');

      expect(
        textOf(tester, 'death-saves-0'),
        'Todesrettungswürfe: Erfolge 1 · Fehlschläge 0',
      );
      expect(
        textOf(tester, 'last-action'),
        'Todesrettungswurf von Aria: 12, Erfolg (Erfolge 1, Fehlschläge 0)',
      );
    });

    testWidgets('Ein am Tisch gewürfelter Wurf lässt sich von Hand '
        'eintragen', (tester) async {
      final scene = dyingAria([]);
      await scene.pump(tester);

      await tapKey(tester, 'death-save-0');
      await type(tester, 'manual-death-save', '6');
      await tapKey(tester, 'death-save-confirm');

      final event = (await scene.events()).single as DeathSaveEvent;
      expect(event.roll.manual, isTrue);
      expect(scene.aria.deathSaveFailures, 1);
    });

    testWidgets('Ein unmöglicher eingetragener Wurf wird abgelehnt: das '
        'Fenster bleibt offen und nichts ändert sich', (tester) async {
      final scene = dyingAria([]);
      await scene.pump(tester);

      await tapKey(tester, 'death-save-0');
      await type(tester, 'manual-death-save', '30');
      await tapKey(tester, 'death-save-confirm');

      expect(find.byKey(const Key('form-error')), findsOneWidget);
      expect(await scene.events(), isEmpty);
    });

    testWidgets('Nach drei Erfolgen ist der Charakter als "stabil" markiert '
        'und der Knopf verschwindet', (tester) async {
      final scene = dyingAria([10, 10, 10]);
      await scene.pump(tester);

      for (var i = 0; i < 3; i++) {
        await tapKey(tester, 'death-save-0');
        await tapKey(tester, 'death-save-confirm');
      }

      expect(
        find.descendant(
          of: find.byKey(const Key('combatant-0')),
          matching: find.text('stabil'),
        ),
        findsOneWidget,
      );
      expect(saveButton, findsNothing);
    });

    testWidgets('Nach drei Fehlschlägen ist der Charakter als "tot" '
        'markiert und der Knopf verschwindet', (tester) async {
      final scene = dyingAria([2, 2, 2]);
      await scene.pump(tester);

      for (var i = 0; i < 3; i++) {
        await tapKey(tester, 'death-save-0');
        await tapKey(tester, 'death-save-confirm');
      }

      final card = find.byKey(const Key('combatant-0'));
      expect(
        find.descendant(of: card, matching: find.text('tot')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('am Boden')),
        findsNothing,
      );
      expect(saveButton, findsNothing);
    });

    testWidgets('Heilung für einen toten Charakter wird mit einer Meldung '
        'abgelehnt', (tester) async {
      final scene = dyingAria([]);
      scene.aria.isDead = true;
      await scene.pump(tester);

      await tapKey(tester, 'hp-0');
      await type(tester, 'hp-amount', '5');
      await tapKey(tester, 'hp-heal');

      expect(find.byKey(const Key('form-error')), findsOneWidget);
      expect(scene.aria.hp, 0);
      expect(await scene.events(), isEmpty);
    });
  });
}
