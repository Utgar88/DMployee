import 'package:dmployee/combat/attack.dart';
import 'package:dmployee/combat/buff.dart';
import 'package:dmployee/combat/combatant.dart';
import 'package:dmployee/combat/condition.dart';
import 'package:dmployee/combat/damage.dart';
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

  group('Kampf-Bildschirm: Resistenzen', () {
    testWidgets('Über "Resistenzen" lässt sich je Schadensart durch '
        'Antippen Resistenz, Anfälligkeit oder Immunität einstellen', (
      tester,
    ) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'traits-1');
      await tapKey(tester, 'trait-Feuer');
      expect(scene.goblin.damageTraits, {'Feuer': DamageEffect.resistance});

      await tapKey(tester, 'trait-Feuer');
      expect(scene.goblin.damageTraits, {'Feuer': DamageEffect.vulnerability});

      await tapKey(tester, 'trait-Feuer');
      expect(scene.goblin.damageTraits, {'Feuer': DamageEffect.immunity});

      await tapKey(tester, 'trait-Feuer');
      expect(scene.goblin.damageTraits, isEmpty);
    });

    testWidgets('Eingestellte Resistenzen stehen beim Kämpfer', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);
      expect(find.byKey(const Key('traits-text-1')), findsNothing);

      await tapKey(tester, 'traits-1');
      await tapKey(tester, 'trait-Feuer');
      await tapKey(tester, 'trait-Gift');
      await tapKey(tester, 'trait-Gift');
      await tapKey(tester, 'trait-Gift');
      await tapKey(tester, 'traits-done');

      expect(
        textOf(tester, 'traits-text-1'),
        'Resistenz: Feuer · Immunität: Gift',
      );
    });

    testWidgets('Ein Angriff gegen ein Ziel mit Resistenz zieht nur den '
        'halben Schaden ab', (tester) async {
      // Attack 15 hits, damage 4 + 3 = 7, halved to 3.
      final scene = Scene([15, 4]);
      scene.encounter.setDamageTrait(
        scene.goblin,
        'Hieb',
        DamageEffect.resistance,
      );
      await scene.pump(tester);

      await openAttack(tester);
      await tapKey(tester, 'target-1');

      expect(textOf(tester, 'stats-1'), 'RK 13 · TP 4/7');
      expect(
        textOf(tester, 'last-action'),
        'Aria hat Goblin für 3 Schaden getroffen (Resistenz)',
      );
    });

    testWidgets('Bei "TP ändern" lässt sich eine Schadensart angeben, '
        'gegen die die Resistenz wirkt', (tester) async {
      final scene = Scene([]);
      scene.encounter.setDamageTrait(
        scene.goblin,
        'Feuer',
        DamageEffect.resistance,
      );
      await scene.pump(tester);

      await tapKey(tester, 'hp-1');
      await type(tester, 'hp-amount', '6');
      await type(tester, 'hp-damage-type', 'Feuer');
      await tapKey(tester, 'hp-damage');

      expect(textOf(tester, 'stats-1'), 'RK 13 · TP 4/7');
    });
  });

  group('Kampf-Bildschirm: Zustände', () {
    testWidgets('Über "Zustand" lässt sich ein Zustand mit einem Tipp '
        'vergeben; er steht danach beim Kämpfer', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'add-condition-1');
      await tapKey(tester, 'condition-option-poisoned');

      expect(scene.goblin.hasCondition(Condition.poisoned), isTrue);
      expect(
        find.descendant(
          of: find.byKey(const Key('condition-1-poisoned')),
          matching: find.text('Vergiftet'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Mit Dauer vergeben zeigt der Zustand die verbleibenden '
        'Runden', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'add-condition-1');
      await type(tester, 'condition-rounds', '3');
      await tapKey(tester, 'condition-option-poisoned');

      expect(scene.goblin.conditions.single.roundsLeft, 3);
      expect(find.text('Vergiftet (3)'), findsOneWidget);
    });

    testWidgets('Eine Dauer von 0 Runden wird abgelehnt', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'add-condition-1');
      await type(tester, 'condition-rounds', '0');
      await tapKey(tester, 'condition-option-poisoned');

      expect(find.byKey(const Key('form-error')), findsOneWidget);
      expect(scene.goblin.conditions, isEmpty);
    });

    testWidgets('Ein Zustand lässt sich am Kämpfer wieder entfernen', (
      tester,
    ) async {
      final scene = Scene([]);
      await scene.encounter.addCondition(scene.goblin, Condition.poisoned);
      await scene.pump(tester);

      await tapKey(tester, 'remove-condition-1-poisoned');

      expect(scene.goblin.conditions, isEmpty);
      expect(find.byKey(const Key('condition-1-poisoned')), findsNothing);
    });

    testWidgets('Ein Angriff berücksichtigt Zustände von selbst: gegen ein '
        'festgesetztes Ziel wird mit Vorteil gewürfelt', (tester) async {
      // Two d20 (4 and 15), then the damage die.
      final scene = Scene([4, 15, 1]);
      await scene.encounter.addCondition(scene.goblin, Condition.restrained);
      await scene.pump(tester);

      await openAttack(tester);
      await tapKey(tester, 'target-1');

      final attack = (await scene.events()).whereType<AttackEvent>().single;
      expect(attack.attackRoll.mode, RollMode.advantage);
      expect(attack.hit, isTrue);
    });

    testWidgets('Im Angriffsfenster lässt sich abschalten, dass Zustände '
        'berücksichtigt werden', (tester) async {
      final scene = Scene([15, 1]);
      await scene.encounter.addCondition(scene.goblin, Condition.restrained);
      await scene.pump(tester);

      await openAttack(tester);
      await tapKey(tester, 'attack-conditions');
      await tapKey(tester, 'target-1');

      final attack = (await scene.events()).whereType<AttackEvent>().single;
      expect(attack.attackRoll.mode, RollMode.normal);
    });

    testWidgets('Ohne Zustände im Kampf fehlt der Schalter im '
        'Angriffsfenster', (tester) async {
      await Scene([]).pump(tester);

      await openAttack(tester);

      expect(find.byKey(const Key('attack-conditions')), findsNothing);
    });

    testWidgets('Das Angriffsfenster zeigt die Zustände des Angreifers und '
        'des Ziels', (tester) async {
      final scene = Scene([]);
      await scene.encounter.addCondition(scene.aria, Condition.poisoned);
      await scene.encounter.addCondition(scene.goblin, Condition.prone);
      await scene.pump(tester);

      await openAttack(tester);

      expect(
        find.textContaining('Aria ist vergiftet: Nachteil'),
        findsOneWidget,
      );
      expect(find.textContaining('Liegend'), findsWidgets);
    });
  });

  group('Kampf-Bildschirm: Effekte', () {
    testWidgets('Über "Effekt" lässt sich ein Effekt mit Namen, Bonus auf '
        'den Angriffswurf und Dauer vergeben; er steht danach beim '
        'Kämpfer', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'add-buff-0');
      await type(tester, 'buff-name', 'Segen');
      await type(tester, 'buff-attack', '1d4');
      await type(tester, 'buff-rounds', '10');
      await tapKey(tester, 'buff-save');

      final buff = scene.aria.buffs.single;
      expect(buff.name, 'Segen');
      expect('${buff.attackBonus}', '+1d4');
      expect(buff.roundsLeft, 10);
      expect(find.text('Segen: Angriff +1d4 (10)'), findsOneWidget);
    });

    testWidgets('Ein Bonus auf die Rüstungsklasse steht bei den Werten des '
        'Kämpfers', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'add-buff-1');
      await type(tester, 'buff-name', 'Schild des Glaubens');
      await type(tester, 'buff-ac', '2');
      await tapKey(tester, 'buff-save');

      expect(textOf(tester, 'stats-1'), 'RK 15 (13 +2) · TP 7/7');
      expect(find.text('Schild des Glaubens: RK +2'), findsOneWidget);
    });

    testWidgets('Ohne Namen wird kein Effekt angelegt und eine Meldung '
        'erscheint', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'add-buff-0');
      await type(tester, 'buff-attack', '1d4');
      await tapKey(tester, 'buff-save');

      expect(find.byKey(const Key('form-error')), findsOneWidget);
      expect(scene.aria.buffs, isEmpty);
    });

    testWidgets('Ein unlesbarer Bonus auf den Angriffswurf wird mit einer '
        'Meldung abgelehnt', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'add-buff-0');
      await type(tester, 'buff-name', 'Segen');
      await type(tester, 'buff-attack', 'viel');
      await tapKey(tester, 'buff-save');

      expect(find.byKey(const Key('form-error')), findsOneWidget);
      expect(scene.aria.buffs, isEmpty);
    });

    testWidgets('Ein Effekt lässt sich am Kämpfer wieder entfernen', (
      tester,
    ) async {
      final scene = Scene([]);
      await scene.encounter.addBuff(
        scene.goblin,
        name: 'Schild des Glaubens',
        armorClassBonus: 2,
      );
      await scene.pump(tester);

      await tapKey(tester, 'remove-buff-1-0');

      expect(scene.goblin.buffs, isEmpty);
      expect(textOf(tester, 'stats-1'), 'RK 13 · TP 7/7');
    });

    testWidgets('Ein Angriff rechnet den Bonuswürfel des Angreifers von '
        'selbst ein', (tester) async {
      // Bonus die 4, d20 4: 4 + 5 + 4 = 13 hits RK 13; damage die 1.
      final scene = Scene([4, 4, 1]);
      await scene.encounter.addBuff(
        scene.aria,
        name: 'Segen',
        attackBonus: Bonus.parse('1d4'),
      );
      await scene.pump(tester);

      await openAttack(tester);
      await tapKey(tester, 'target-1');

      final attack = (await scene.events()).whereType<AttackEvent>().single;
      expect(attack.attackRoll.total, 13);
      expect(attack.hit, isTrue);
    });

    testWidgets('Im Angriffsfenster lässt sich der Bonuswürfel von Hand '
        'eintragen', (tester) async {
      final scene = Scene([]);
      await scene.encounter.addBuff(
        scene.aria,
        name: 'Segen',
        attackBonus: Bonus.parse('1d4'),
      );
      await scene.pump(tester);

      await openAttack(tester);
      await type(tester, 'manual-attack', '2');
      await type(tester, 'manual-buff-0', '3');
      await tapKey(tester, 'target-1');

      final attack = (await scene.events()).whereType<AttackEvent>().single;
      expect(attack.attackRoll.total, 10);
      expect(attack.attackRoll.modifiers.last.label, 'Segen (1d4 von Hand)');
    });

    testWidgets('Ohne Bonuswürfel beim Angreifer fehlt das Feld im '
        'Angriffsfenster', (tester) async {
      await Scene([]).pump(tester);

      await openAttack(tester);

      expect(find.byKey(const Key('manual-buff-0')), findsNothing);
    });

    testWidgets('Die Zielauswahl zeigt die wirksame Rüstungsklasse', (
      tester,
    ) async {
      final scene = Scene([]);
      await scene.encounter.addBuff(
        scene.goblin,
        name: 'Schild des Glaubens',
        armorClassBonus: 2,
      );
      await scene.pump(tester);

      await openAttack(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('target-1')),
          matching: find.textContaining('RK 15'),
        ),
        findsOneWidget,
      );
    });
  });

  group('Kampf-Bildschirm: Effekte auf Schaden und Rettungswürfe', () {
    Future<Buff> huntersMark(Scene scene) => scene.encounter.addBuff(
      scene.aria,
      name: 'Mal des Jägers',
      damageBonus: Bonus.parse('1d6'),
    );

    testWidgets('Ein Effekt lässt sich mit Schadensbonus und eigener '
        'Schadensart aus der Liste vergeben', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'add-buff-0');
      await type(tester, 'buff-name', 'Verhexen');
      await type(tester, 'buff-damage', '1d6');
      await tapKey(tester, 'buff-damage-type');
      await tester.tap(find.text('Nekrotisch').last);
      await tester.pumpAndSettle();
      await tapKey(tester, 'buff-save');

      final buff = scene.aria.buffs.single;
      expect('${buff.damageBonus}', '+1d6');
      expect(buff.damageType, 'Nekrotisch');
      expect(find.text('Verhexen: Schaden +1d6 Nekrotisch'), findsOneWidget);
    });

    testWidgets('Ohne gewählte Schadensart hat der Schadensbonus die '
        'Schadensart des Angriffs', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'add-buff-0');
      await type(tester, 'buff-name', 'Mal des Jägers');
      await type(tester, 'buff-damage', '1d6');
      await tapKey(tester, 'buff-save');

      expect(scene.aria.buffs.single.damageType, isNull);
      expect(find.text('Mal des Jägers: Schaden +1d6'), findsOneWidget);
    });

    testWidgets('Ein Effekt lässt sich mit Bonus auf Rettungswürfe '
        'vergeben', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'add-buff-0');
      await type(tester, 'buff-name', 'Segen');
      await type(tester, 'buff-attack', '1d4');
      await type(tester, 'buff-saving-throw', '1d4');
      await tapKey(tester, 'buff-save');

      expect('${scene.aria.buffs.single.saveBonus}', '+1d4');
      expect(
        find.text('Segen: Angriff +1d4, Rettungswurf +1d4'),
        findsOneWidget,
      );
    });

    testWidgets('Ein unlesbarer Schadens- oder Rettungswurfbonus wird mit '
        'einer Meldung abgelehnt', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'add-buff-0');
      await type(tester, 'buff-name', 'Verhexen');
      await type(tester, 'buff-damage', 'viel');
      await tapKey(tester, 'buff-save');
      expect(find.byKey(const Key('form-error')), findsOneWidget);

      await type(tester, 'buff-damage', '');
      await type(tester, 'buff-saving-throw', 'viel');
      await tapKey(tester, 'buff-save');
      expect(find.byKey(const Key('form-error')), findsOneWidget);
      expect(scene.aria.buffs, isEmpty);
    });

    testWidgets('Ein Angriff rechnet den Schadensbonus des Angreifers von '
        'selbst ein', (tester) async {
      // d20 10 hits; d8 4 + 3, bonus d6 5 = 12.
      final scene = Scene([10, 4, 5]);
      await huntersMark(scene);
      await scene.pump(tester);

      await openAttack(tester);
      await tapKey(tester, 'target-1');

      final attack = (await scene.events()).whereType<AttackEvent>().single;
      expect(attack.damage, 12);
    });

    testWidgets('Im Angriffsfenster lässt sich der Bonuswürfel für den '
        'Schaden von Hand eintragen', (tester) async {
      final scene = Scene([]);
      await huntersMark(scene);
      await scene.pump(tester);

      await openAttack(tester);
      await type(tester, 'manual-attack', '15');
      await type(tester, 'manual-damage', '4');
      await type(tester, 'manual-buff-damage-0', '6');
      await tapKey(tester, 'target-1');

      final attack = (await scene.events()).whereType<AttackEvent>().single;
      expect(attack.damage, 13);
      expect(
        attack.damageRoll!.modifiers.last.label,
        'Mal des Jägers (1d6 von Hand)',
      );
    });

    testWidgets('Im Angriffsfenster lässt sich ein Effekt für diesen Angriff '
        'abwählen; sein Feld für den Würfel verschwindet', (tester) async {
      final scene = Scene([10, 4]);
      await huntersMark(scene);
      await scene.pump(tester);

      await openAttack(tester);
      expect(find.byKey(const Key('manual-buff-damage-0')), findsOneWidget);
      await tapKey(tester, 'attack-buff-0');
      expect(find.byKey(const Key('manual-buff-damage-0')), findsNothing);
      await tapKey(tester, 'target-1');

      final attack = (await scene.events()).whereType<AttackEvent>().single;
      expect(attack.damage, 7);
      expect(scene.aria.buffs, hasLength(1));
    });

    testWidgets('Ohne Effekte beim Angreifer gibt es nichts abzuwählen', (
      tester,
    ) async {
      await Scene([]).pump(tester);

      await openAttack(tester);

      expect(find.byKey(const Key('attack-buff-0')), findsNothing);
    });

    testWidgets('Der Todesrettungswurf rechnet den Rettungswurfbonus ein; der '
        'Bonuswürfel lässt sich von Hand eintragen', (tester) async {
      final scene = Scene([]);
      scene.aria
        ..isPlayer = true
        ..hp = 0;
      await scene.encounter.addBuff(
        scene.aria,
        name: 'Segen',
        saveBonus: Bonus.parse('1d4'),
      );
      await scene.pump(tester);

      await tapKey(tester, 'death-save-0');
      await type(tester, 'manual-death-save', '8');
      await type(tester, 'manual-death-save-buff-0', '2');
      await tapKey(tester, 'death-save-confirm');

      final save = (await scene.events()).whereType<DeathSaveEvent>().single;
      expect(save.roll.total, 10);
      expect(scene.aria.deathSaveSuccesses, 1);
    });

    testWidgets('Ein unmöglicher Bonuswürfel beim Todesrettungswurf wird mit '
        'einer Meldung abgelehnt', (tester) async {
      final scene = Scene([]);
      scene.aria
        ..isPlayer = true
        ..hp = 0;
      await scene.encounter.addBuff(
        scene.aria,
        name: 'Segen',
        saveBonus: Bonus.parse('1d4'),
      );
      await scene.pump(tester);

      await tapKey(tester, 'death-save-0');
      await type(tester, 'manual-death-save', '8');
      await type(tester, 'manual-death-save-buff-0', '5');
      await tapKey(tester, 'death-save-confirm');

      expect(find.byKey(const Key('form-error')), findsOneWidget);
      expect(scene.aria.deathSaveSuccesses, 0);
    });
  });

  group('Kampf-Bildschirm: Kämpfer bearbeiten', () {
    String fieldText(WidgetTester tester, String key) =>
        tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

    testWidgets('Das Fenster zum Bearbeiten zeigt die aktuellen Werte', (
      tester,
    ) async {
      await Scene([]).pump(tester);

      await tapKey(tester, 'edit-0');

      expect(fieldText(tester, 'combatant-name'), 'Aria');
      expect(fieldText(tester, 'combatant-ac'), '16');
      expect(fieldText(tester, 'combatant-hp'), '20');
      expect(fieldText(tester, 'combatant-init'), '2');
      expect(find.text('Kämpfer bearbeiten'), findsOneWidget);
    });

    testWidgets('Geänderte Werte werden übernommen und angezeigt', (
      tester,
    ) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'edit-1');
      await type(tester, 'combatant-name', 'Goblin-Boss');
      await type(tester, 'combatant-ac', '15');
      await type(tester, 'combatant-hp', '21');
      await tapKey(tester, 'combatant-player');
      await tapKey(tester, 'combatant-save');

      expect(scene.goblin.name, 'Goblin-Boss');
      expect(scene.goblin.isPlayer, isTrue);
      expect(textOf(tester, 'name-1'), 'Goblin-Boss');
      expect(textOf(tester, 'stats-1'), 'RK 15 · TP 21/21');
    });

    testWidgets('Ein hinterlegter Angriff lässt sich beim Bearbeiten '
        'entfernen; erst Speichern übernimmt das', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'edit-0');
      await tapKey(tester, 'edit-remove-attack-0');
      expect(scene.aria.attacks, hasLength(1));
      await tapKey(tester, 'combatant-save');

      expect(scene.aria.attacks, isEmpty);
      expect(find.byKey(const Key('attack-0-0')), findsNothing);
    });

    testWidgets('Abbrechen ändert nichts', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'edit-0');
      await type(tester, 'combatant-name', 'Arya');
      await tapKey(tester, 'edit-remove-attack-0');
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      expect(scene.aria.name, 'Aria');
      expect(scene.aria.attacks, hasLength(1));
    });

    testWidgets('Ohne Namen wird nichts geändert und eine Meldung '
        'erscheint', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'edit-0');
      await type(tester, 'combatant-name', '');
      await tapKey(tester, 'combatant-save');

      expect(find.byKey(const Key('form-error')), findsOneWidget);
      expect(scene.aria.name, 'Aria');
    });

    testWidgets('Auch im laufenden Kampf lässt sich ein Kämpfer '
        'bearbeiten', (tester) async {
      final scene = Scene([10, 5]);
      await scene.pump(tester);
      await startCombat(tester);

      await tapKey(tester, 'edit-0');
      await type(tester, 'combatant-ac', '18');
      await tapKey(tester, 'combatant-save');

      expect(scene.aria.armorClass, 18);
      expect(scene.encounter.isRunning, isTrue);
    });
  });

  group('Kampf-Bildschirm: Temporäre Trefferpunkte', () {
    testWidgets('Über "TP ändern" lassen sich temporäre Trefferpunkte mit '
        'Quelle vergeben; sie stehen bei den Werten des Kämpfers', (
      tester,
    ) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'hp-0');
      await type(tester, 'hp-amount', '8');
      await type(tester, 'hp-source', 'Falsches Leben');
      await tapKey(tester, 'hp-temp');

      expect(scene.aria.tempHp, 8);
      expect(textOf(tester, 'stats-0'), 'RK 16 · TP 20/20 (+8 temporär)');
      final event = (await scene.events()).whereType<TempHpEvent>().single;
      expect(event.source, 'Falsches Leben');
    });

    testWidgets('Ohne Betrag werden keine temporären Trefferpunkte '
        'vergeben', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'hp-0');
      await tapKey(tester, 'hp-temp');

      expect(find.byKey(const Key('form-error')), findsOneWidget);
      expect(scene.aria.tempHp, 0);
    });

    testWidgets('Schaden zieht zuerst die temporären Trefferpunkte ab', (
      tester,
    ) async {
      final scene = Scene([]);
      await scene.encounter.grantTempHp(scene.aria, 8);
      await scene.pump(tester);

      await tapKey(tester, 'hp-0');
      await type(tester, 'hp-amount', '10');
      await tapKey(tester, 'hp-damage');

      expect(textOf(tester, 'stats-0'), 'RK 16 · TP 18/20');
    });

    testWidgets('Temporäre Trefferpunkte lassen sich entfernen; ohne sie '
        'fehlt der Knopf', (tester) async {
      final scene = Scene([]);
      await scene.encounter.grantTempHp(scene.aria, 8);
      await scene.pump(tester);

      await tapKey(tester, 'hp-0');
      await tapKey(tester, 'hp-temp-remove');

      expect(scene.aria.tempHp, 0);
      await tapKey(tester, 'hp-0');
      expect(find.byKey(const Key('hp-temp-remove')), findsNothing);
    });
  });

  group('Kampf-Bildschirm: Auswahl der Schadensart', () {
    String fieldText(WidgetTester tester, String key) =>
        tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

    testWidgets('Beim Anlegen eines Angriffs schlägt das Feld Schadensart die '
        'Schadensarten der Regeln vor; ein Tipp übernimmt sie', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'add-attack-1');
      await tapKey(tester, 'attack-type');
      // The list scrolls; the first entries are visible right away.
      expect(find.byKey(const Key('attack-type-option-Blitz')), findsOneWidget);
      expect(find.byKey(const Key('attack-type-option-Feuer')), findsOneWidget);
      await tapKey(tester, 'attack-type-option-Feuer');

      expect(fieldText(tester, 'attack-type'), 'Feuer');
      expect(find.byKey(const Key('attack-type-option-Blitz')), findsNothing);
    });

    testWidgets('Getippte Buchstaben grenzen die Vorschläge ein', (
      tester,
    ) async {
      await Scene([]).pump(tester);

      await tapKey(tester, 'add-attack-1');
      await tapKey(tester, 'attack-type');
      await tester.enterText(find.byKey(const Key('attack-type')), 'gl');
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('attack-type-option-Gleißend')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('attack-type-option-Hieb')), findsNothing);
    });

    testWidgets('Eine eigene Schadensart bleibt möglich', (tester) async {
      final scene = Scene([]);
      await scene.pump(tester);

      await tapKey(tester, 'add-attack-1');
      await type(tester, 'attack-name', 'Biss');
      await type(tester, 'attack-damage', '1d6');
      await type(tester, 'attack-type', 'Magisch');
      await tapKey(tester, 'attack-save');

      expect(scene.goblin.attacks.single.damageType, 'Magisch');
    });

    testWidgets('Auch bei "TP ändern" wird die Schadensart '
        'vorgeschlagen', (tester) async {
      final scene = Scene([]);
      scene.encounter.setDamageTrait(
        scene.aria,
        'Feuer',
        DamageEffect.resistance,
      );
      await scene.pump(tester);

      await tapKey(tester, 'hp-0');
      await type(tester, 'hp-amount', '10');
      await tapKey(tester, 'hp-damage-type');
      await tapKey(tester, 'hp-damage-type-option-Feuer');
      await tapKey(tester, 'hp-damage');

      expect(scene.aria.hp, 15);
    });
  });
}
