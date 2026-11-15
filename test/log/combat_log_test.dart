import 'package:dmployee/dice/dice_roller.dart';
import 'package:dmployee/dice/modifier.dart';
import 'package:dmployee/log/log_event.dart';
import 'package:dmployee/log/log_formatter.dart';
import 'package:dmployee/log/roll_record.dart';
import 'package:flutter_test/flutter_test.dart';

RollRecord attackRoll(List<int> rolls, {RollMode mode = RollMode.normal}) =>
    RollRecord(
      count: 1,
      sides: 20,
      rolls: rolls,
      mode: mode,
      modifiers: [Modifier('Angriffsbonus', 5)],
    );

AttackEvent hitEvent({bool critical = false}) => AttackEvent(
  attackerName: 'Aria',
  targetName: 'Goblin',
  attackName: 'Langschwert',
  targetArmorClass: 13,
  attackRoll: attackRoll(
    critical ? [20] : [7, 15],
    mode: critical ? RollMode.normal : RollMode.advantage,
  ),
  hit: true,
  critical: critical,
  damageType: 'Hieb',
  damageRoll: RollRecord(
    count: 2,
    sides: 6,
    rolls: [4, 5],
    modifiers: [Modifier('Schadensbonus', 5)],
  ),
  damage: 14,
);

final missEvent = AttackEvent(
  attackerName: 'Aria',
  targetName: 'Goblin',
  attackName: 'Langschwert',
  targetArmorClass: 13,
  attackRoll: attackRoll([4]),
  hit: false,
  critical: false,
  damageType: 'Hieb',
);

void main() {
  const formatter = LogFormatter();

  List<String> detailsOf(LogEvent event) =>
      formatter.format(event).spans.firstWhere((s) => s.hasDetails).details;

  group('Log-Zeile für einen Angriff', () {
    test('Ein Treffer nennt Angreifer, Ziel und Schaden', () {
      expect(
        formatter.format(hitEvent()).text,
        'Aria hat Goblin für 14 Schaden getroffen',
      );
    });

    test('Bei einem Treffer ist der Schaden antippbar', () {
      final tappable = formatter
          .format(hitEvent())
          .spans
          .where((span) => span.hasDetails);

      expect(tappable.single.text, '14');
    });

    test('Ein kritischer Treffer ist in der Zeile erkennbar', () {
      expect(
        formatter.format(hitEvent(critical: true)).text,
        'Aria hat Goblin für 14 Schaden kritisch getroffen',
      );
    });

    test('Ein Fehlschlag nennt den Angriffswurf, der antippbar ist', () {
      final line = formatter.format(missEvent);

      expect(line.text, 'Aria hat Goblin mit 9 verfehlt');
      expect(line.spans.where((s) => s.hasDetails).single.text, '9');
    });

    test('Ein Angriff ist kein freier Wurf', () {
      expect(formatter.format(hitEvent()).isFreeRoll, isFalse);
    });
  });

  group('Details eines Angriffs', () {
    test('Ein Treffer zeigt Angriff, Angriffswurf mit Vorteil und Bonus, '
        'das Ergebnis gegen die Rüstungsklasse und den Schadenswurf', () {
      expect(detailsOf(hitEvent()), [
        'Angriff: Langschwert',
        '1d20 mit Vorteil: 7 | 15 → 15',
        '+5 Angriffsbonus',
        'Summe: 20',
        'Treffer gegen RK 13',
        'Schaden (Hieb):',
        '2d6: 4 + 5 = 9',
        '+5 Schadensbonus',
        'Summe: 14',
      ]);
    });

    test('Ein kritischer Treffer wird in den Details benannt', () {
      final details = detailsOf(hitEvent(critical: true));

      expect(details, contains('Natürliche 20'));
      expect(details, contains('Kritischer Treffer gegen RK 13'));
    });

    test('Ein Fehlschlag zeigt den Angriffswurf und kein Schaden', () {
      expect(detailsOf(missEvent), [
        'Angriff: Langschwert',
        '1d20: 4',
        '+5 Angriffsbonus',
        'Summe: 9',
        'Verfehlt gegen RK 13',
      ]);
    });

    test('Von Hand eingetragene Würfe sind in den Details als solche '
        'gekennzeichnet', () {
      final event = AttackEvent(
        attackerName: 'Aria',
        targetName: 'Goblin',
        attackName: 'Langschwert',
        targetArmorClass: 13,
        attackRoll: RollRecord.manualD20(
          15,
          mode: RollMode.advantage,
          modifiers: [Modifier('Angriffsbonus', 5)],
        ),
        hit: true,
        critical: false,
        damageType: 'Hieb',
        damageRoll: RollRecord.manualDice(count: 2, sides: 6, sum: 9),
        damage: 9,
      );

      final details = detailsOf(event);

      expect(details, contains('1d20 mit Vorteil von Hand: 15'));
      expect(details, contains('2d6 von Hand: 9'));
    });
  });

  group('Log-Zeilen für Initiative, Runden und Kämpfer am Boden', () {
    final initiative = InitiativeEvent([
      InitiativeEntry(
        name: 'Aria',
        roll: RollRecord(
          count: 1,
          sides: 20,
          rolls: [15],
          modifiers: [Modifier('Initiative', 2)],
        ),
      ),
      InitiativeEntry(name: 'Goblin', roll: RollRecord.manualD20(12)),
    ]);

    test('Die Initiative nennt alle Kämpfer in Zugreihenfolge', () {
      expect(
        formatter.format(initiative).text,
        'Initiative: Aria 17, Goblin 12',
      );
    });

    test('Jeder Initiativewert ist einzeln antippbar und zeigt seinen '
        'eigenen Wurf', () {
      final tappable = formatter
          .format(initiative)
          .spans
          .where((span) => span.hasDetails)
          .toList();

      expect(tappable.map((span) => span.text), ['17', '12']);
      expect(tappable.first.details, [
        '1d20: 15',
        '+2 Initiative',
        'Summe: 17',
      ]);
      expect(tappable.last.details, ['1d20 von Hand: 12', 'Summe: 12']);
    });

    test('Eine neue Runde steht als eigene Zeile im Log', () {
      expect(formatter.format(const RoundEvent(2)).text, 'Runde 2 beginnt');
    });

    test('Ein Kämpfer am Boden steht als eigene Zeile im Log', () {
      expect(
        formatter.format(const CombatantDownEvent('Goblin')).text,
        'Goblin geht zu Boden',
      );
    });
  });

  group('Kampf-Ereignisse speichern und laden (JSON)', () {
    LogEvent reload(LogEvent event) =>
        LogEvent.fromJson(event.type, event.toJson());

    test('Ein Treffer kommt mit allen Angaben zurück', () {
      final loaded = reload(hitEvent()) as AttackEvent;

      expect(formatter.format(loaded).text, formatter.format(hitEvent()).text);
      expect(detailsOf(loaded), detailsOf(hitEvent()));
    });

    test('Ein Fehlschlag kommt ohne Schadenswurf zurück', () {
      final loaded = reload(missEvent) as AttackEvent;

      expect(loaded.hit, isFalse);
      expect(loaded.damageRoll, isNull);
    });

    test('Initiative, Runde und Kämpfer am Boden kommen unverändert '
        'zurück', () {
      final initiative = InitiativeEvent([
        InitiativeEntry(name: 'Aria', roll: RollRecord.manualD20(12)),
      ]);

      expect(formatter.format(reload(initiative)).text, 'Initiative: Aria 12');
      expect((reload(const RoundEvent(3)) as RoundEvent).round, 3);
      expect(
        (reload(const CombatantDownEvent('Goblin')) as CombatantDownEvent).name,
        'Goblin',
      );
    });
  });

  group('Log-Zeilen für direkt geänderte Trefferpunkte', () {
    const damage = HpChangeEvent(
      name: 'Goblin',
      amount: 5,
      healing: false,
      hpBefore: 7,
      hpAfter: 2,
      maxHp: 7,
    );
    const healing = HpChangeEvent(
      name: 'Aria',
      amount: 6,
      healing: true,
      hpBefore: 5,
      hpAfter: 11,
      maxHp: 20,
      source: 'Heiltrank',
    );

    test('Schaden nennt Kämpfer und Betrag', () {
      expect(formatter.format(damage).text, 'Goblin erleidet 5 Schaden');
    });

    test('Heilung nennt Kämpfer und Betrag', () {
      expect(
        formatter.format(healing).text,
        'Aria wird um 6 TP geheilt (Heiltrank)',
      );
    });

    test('Eine angegebene Quelle steht in Klammern hinter der Zeile', () {
      const fireball = HpChangeEvent(
        name: 'Goblin',
        amount: 5,
        healing: false,
        hpBefore: 7,
        hpAfter: 2,
        maxHp: 7,
        source: 'Feuerball',
      );

      expect(
        formatter.format(fireball).text,
        'Goblin erleidet 5 Schaden (Feuerball)',
      );
    });

    test('Der Betrag ist antippbar und zeigt die Trefferpunkte vorher und '
        'nachher', () {
      final tappable = formatter
          .format(damage)
          .spans
          .where((span) => span.hasDetails);

      expect(tappable.single.text, '5');
      expect(detailsOf(damage), ['Trefferpunkte: 7 → 2 (Maximum 7)']);
    });

    test('Die Details nennen die Quelle', () {
      expect(detailsOf(healing), [
        'Quelle: Heiltrank',
        'Trefferpunkte: 5 → 11 (Maximum 20)',
      ]);
    });

    test('Wirkt nur ein Teil des Betrags, nennen die Details den wirksamen '
        'Teil', () {
      const overkill = HpChangeEvent(
        name: 'Goblin',
        amount: 50,
        healing: false,
        hpBefore: 7,
        hpAfter: 0,
        maxHp: 7,
      );

      expect(detailsOf(overkill), [
        'Trefferpunkte: 7 → 0 (Maximum 7)',
        'Davon wirksam: 7',
      ]);
    });

    test('Eine Änderung der Trefferpunkte ist kein freier Wurf', () {
      expect(formatter.format(damage).isFreeRoll, isFalse);
    });

    test('Die Änderung kommt nach dem Speichern und Laden (JSON) mit allen '
        'Angaben zurück', () {
      final restored =
          LogEvent.fromJson(healing.type, healing.toJson()) as HpChangeEvent;

      expect(restored.name, 'Aria');
      expect(restored.amount, 6);
      expect(restored.healing, isTrue);
      expect(restored.hpBefore, 5);
      expect(restored.hpAfter, 11);
      expect(restored.maxHp, 20);
      expect(restored.source, 'Heiltrank');
    });

    test('Ohne Quelle kommt die Änderung ohne Quelle zurück', () {
      final restored =
          LogEvent.fromJson(damage.type, damage.toJson()) as HpChangeEvent;

      expect(restored.source, isNull);
      expect(restored.healing, isFalse);
    });
  });

  group('Log-Zeilen für Todesrettungswürfe', () {
    DeathSaveEvent save(int face, {int successes = 0, int failures = 0}) =>
        DeathSaveEvent(
          name: 'Aria',
          roll: RollRecord(count: 1, sides: 20, rolls: [face]),
          successes: successes,
          failures: failures,
        );

    test('Ein Erfolg nennt Wurf und Stand', () {
      expect(
        formatter.format(save(14, successes: 2, failures: 1)).text,
        'Todesrettungswurf von Aria: 14, Erfolg '
        '(Erfolge 2, Fehlschläge 1)',
      );
    });

    test('Ein Fehlschlag nennt Wurf und Stand', () {
      expect(
        formatter.format(save(7, failures: 1)).text,
        'Todesrettungswurf von Aria: 7, Fehlschlag '
        '(Erfolge 0, Fehlschläge 1)',
      );
    });

    test('Eine natürliche 1 steht als zwei Fehlschläge da', () {
      expect(
        formatter.format(save(1, failures: 2)).text,
        'Todesrettungswurf von Aria: 1, zwei Fehlschläge '
        '(Erfolge 0, Fehlschläge 2)',
      );
    });

    test('Eine natürliche 20 nennt die Rückkehr mit 1 Trefferpunkt', () {
      expect(
        formatter.format(save(20)).text,
        'Todesrettungswurf von Aria: 20, Aria kommt mit 1 TP wieder zu sich',
      );
    });

    test('Der Wurf ist antippbar und zeigt Würfel, Regel und Stand', () {
      final event = save(14, successes: 2, failures: 1);
      final tappable = formatter
          .format(event)
          .spans
          .where((span) => span.hasDetails);

      expect(tappable.single.text, '14');
      expect(detailsOf(event), [
        '1d20: 14',
        'Summe: 14',
        'Erfolg ab 10',
        'Erfolge: 2 von 3',
        'Fehlschläge: 1 von 3',
      ]);
    });

    test('Schaden bei 0 Trefferpunkten nennt die Fehlschläge', () {
      expect(
        formatter
            .format(
              const DyingDamageEvent(
                name: 'Aria',
                failuresAdded: 1,
                failures: 2,
              ),
            )
            .text,
        'Aria erleidet am Boden Schaden: 1 Fehlschlag bei den '
        'Todesrettungswürfen (Fehlschläge 2)',
      );
      expect(
        formatter
            .format(
              const DyingDamageEvent(
                name: 'Aria',
                failuresAdded: 2,
                failures: 2,
              ),
            )
            .text,
        'Aria erleidet am Boden Schaden: 2 Fehlschläge bei den '
        'Todesrettungswürfen (Fehlschläge 2)',
      );
    });

    test('Stabil und Tod stehen als eigene Zeilen im Log', () {
      expect(
        formatter.format(const CombatantStableEvent('Aria')).text,
        'Aria ist stabil',
      );
      expect(
        formatter.format(const CombatantDiedEvent('Aria')).text,
        'Aria stirbt',
      );
      expect(
        formatter
            .format(const CombatantDiedEvent('Aria', massiveDamage: true))
            .text,
        'Aria stirbt sofort (massiver Schaden)',
      );
    });

    test('Die Ereignisse kommen nach dem Speichern und Laden (JSON) '
        'unverändert zurück', () {
      LogEvent roundTrip(LogEvent event) =>
          LogEvent.fromJson(event.type, event.toJson());

      final restored =
          roundTrip(save(14, successes: 2, failures: 1)) as DeathSaveEvent;
      expect(restored.name, 'Aria');
      expect(restored.roll.total, 14);
      expect(restored.successes, 2);
      expect(restored.failures, 1);

      final damage = roundTrip(
        const DyingDamageEvent(name: 'Aria', failuresAdded: 2, failures: 3),
      ) as DyingDamageEvent;
      expect(damage.failuresAdded, 2);
      expect(damage.failures, 3);

      expect(
        (roundTrip(
          const CombatantStableEvent('Aria'),
        ) as CombatantStableEvent).name,
        'Aria',
      );
      final died = roundTrip(
        const CombatantDiedEvent('Aria', massiveDamage: true),
      ) as CombatantDiedEvent;
      expect(died.name, 'Aria');
      expect(died.massiveDamage, isTrue);
    });
  });
}
