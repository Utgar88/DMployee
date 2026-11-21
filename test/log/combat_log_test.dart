import 'package:dmployee/combat/damage.dart';
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

  group('Log-Zeilen für Resistenz, Anfälligkeit und Immunität', () {
    AttackEvent hitWith(DamageEffect effect, int damage) => AttackEvent(
      attackerName: 'Aria',
      targetName: 'Oger',
      attackName: 'Langschwert',
      targetArmorClass: 11,
      attackRoll: attackRoll([15]),
      hit: true,
      critical: false,
      damageType: 'Hieb',
      damageRoll: RollRecord(
        count: 1,
        sides: 8,
        rolls: [6],
        modifiers: [Modifier('Schadensbonus', 3)],
      ),
      damage: damage,
      damageEffect: effect,
    );

    test('Die Zeile nennt den wirksamen Schaden und die Resistenz', () {
      expect(
        formatter.format(hitWith(DamageEffect.resistance, 4)).text,
        'Aria hat Oger für 4 Schaden getroffen (Resistenz)',
      );
    });

    test('Anfälligkeit und Immunität stehen ebenso in der Zeile', () {
      expect(
        formatter.format(hitWith(DamageEffect.vulnerability, 18)).text,
        'Aria hat Oger für 18 Schaden getroffen (Anfälligkeit)',
      );
      expect(
        formatter.format(hitWith(DamageEffect.immunity, 0)).text,
        'Aria hat Oger für 0 Schaden getroffen (Immunität)',
      );
    });

    test('Die Details zeigen, wie aus dem gewürfelten der wirksame Schaden '
        'wird', () {
      expect(
        detailsOf(hitWith(DamageEffect.resistance, 4)).last,
        'Resistenz gegen Hieb: 9 → 4',
      );
      expect(
        detailsOf(hitWith(DamageEffect.vulnerability, 18)).last,
        'Anfälligkeit gegen Hieb: 9 → 18',
      );
      expect(
        detailsOf(hitWith(DamageEffect.immunity, 0)).last,
        'Immunität gegen Hieb: 9 → 0',
      );
    });

    test('Die Resistenz eines Angriffs bleibt beim Speichern und Laden '
        '(JSON) erhalten', () {
      final event = hitWith(DamageEffect.resistance, 4);
      final restored =
          LogEvent.fromJson(event.type, event.toJson()) as AttackEvent;

      expect(restored.damageEffect, DamageEffect.resistance);
      expect(restored.damage, 4);
    });

    const fire = HpChangeEvent(
      name: 'Oger',
      amount: 15,
      healing: false,
      hpBefore: 59,
      hpAfter: 52,
      maxHp: 59,
      source: 'Feuerball',
      damageType: 'Feuer',
      damageEffect: DamageEffect.resistance,
    );

    test('Direkter Schaden nennt den wirksamen Schaden, Quelle und '
        'Resistenz', () {
      expect(
        formatter.format(fire).text,
        'Oger erleidet 7 Schaden (Feuerball, Resistenz)',
      );
    });

    test('Die Details von direktem Schaden nennen Schadensart, Resistenz '
        'und Trefferpunkte', () {
      expect(detailsOf(fire), [
        'Quelle: Feuerball',
        'Schadensart: Feuer',
        'Resistenz gegen Feuer: 15 → 7',
        'Trefferpunkte: 59 → 52 (Maximum 59)',
      ]);
    });

    test('Direkter Schaden mit Schadensart, aber ohne Resistenz, nennt nur '
        'die Schadensart', () {
      const plain = HpChangeEvent(
        name: 'Oger',
        amount: 15,
        healing: false,
        hpBefore: 59,
        hpAfter: 44,
        maxHp: 59,
        damageType: 'Feuer',
      );

      expect(formatter.format(plain).text, 'Oger erleidet 15 Schaden');
      expect(detailsOf(plain), [
        'Schadensart: Feuer',
        'Trefferpunkte: 59 → 44 (Maximum 59)',
      ]);
    });

    test('Schadensart und Resistenz von direktem Schaden bleiben beim '
        'Speichern und Laden (JSON) erhalten', () {
      final restored =
          LogEvent.fromJson(fire.type, fire.toJson()) as HpChangeEvent;

      expect(restored.damageType, 'Feuer');
      expect(restored.damageEffect, DamageEffect.resistance);
    });
  });

  group('Log-Zeilen für Zustände', () {
    ConditionEvent event(EffectChange change, {int? rounds}) => ConditionEvent(
      name: 'Oger',
      condition: 'poisoned',
      change: change,
      rounds: rounds,
    );

    test('Ein vergebener Zustand steht mit Kämpfer und Zustand da', () {
      expect(
        formatter.format(event(EffectChange.added)).text,
        'Oger ist jetzt vergiftet',
      );
    });

    test('Eine Dauer steht in Klammern dahinter', () {
      expect(
        formatter.format(event(EffectChange.added, rounds: 3)).text,
        'Oger ist jetzt vergiftet (3 Runden)',
      );
      expect(
        formatter.format(event(EffectChange.added, rounds: 1)).text,
        'Oger ist jetzt vergiftet (1 Runde)',
      );
    });

    test('Entfernen und Ablaufen sind unterscheidbar', () {
      expect(
        formatter.format(event(EffectChange.removed)).text,
        'Oger ist nicht mehr vergiftet',
      );
      expect(
        formatter.format(event(EffectChange.expired)).text,
        'Oger ist nicht mehr vergiftet (Dauer abgelaufen)',
      );
    });

    test('Ein Zustand kommt nach dem Speichern und Laden (JSON) unverändert '
        'zurück', () {
      final original = event(EffectChange.added, rounds: 3);
      final restored =
          LogEvent.fromJson(original.type, original.toJson()) as ConditionEvent;

      expect(restored.name, 'Oger');
      expect(restored.condition, 'poisoned');
      expect(restored.change, EffectChange.added);
      expect(restored.rounds, 3);
    });

    AttackEvent attackWith(
      List<ConditionEffect> effects, {
      RollMode chosen = RollMode.normal,
      required List<int> rolls,
      required RollMode mode,
    }) => AttackEvent(
      attackerName: 'Aria',
      targetName: 'Oger',
      attackName: 'Langschwert',
      targetArmorClass: 11,
      attackRoll: attackRoll(rolls, mode: mode),
      hit: false,
      critical: false,
      damageType: 'Hieb',
      conditionEffects: effects,
      chosenMode: chosen,
    );

    const poisoned = ConditionEffect(
      onAttacker: true,
      condition: 'poisoned',
      advantage: false,
    );
    const restrained = ConditionEffect(
      onAttacker: false,
      condition: 'restrained',
      advantage: true,
    );

    test('Die Details eines Angriffs nennen den Zustand, der zum Nachteil '
        'geführt hat', () {
      final details = detailsOf(
        attackWith([poisoned], rolls: [4, 2], mode: RollMode.disadvantage),
      );

      expect(details, contains('Nachteil: Aria ist vergiftet'));
    });

    test('Die Details nennen den Zustand des Ziels, der zum Vorteil geführt '
        'hat', () {
      final details = detailsOf(
        attackWith([restrained], rolls: [4, 2], mode: RollMode.advantage),
      );

      expect(details, contains('Vorteil: Oger ist festgesetzt'));
    });

    test('Heben sich Vorteil und Nachteil auf, steht das in den Details', () {
      final details = detailsOf(
        attackWith([poisoned, restrained], rolls: [4], mode: RollMode.normal),
      );

      expect(
        details,
        containsAllInOrder([
          'Nachteil: Aria ist vergiftet',
          'Vorteil: Oger ist festgesetzt',
          'Vorteil und Nachteil heben sich auf',
        ]),
      );
    });

    test('Ein von der Spielleitung gewählter Vorteil steht neben dem '
        'Zustand in den Details', () {
      final details = detailsOf(
        attackWith(
          [poisoned],
          chosen: RollMode.advantage,
          rolls: [4],
          mode: RollMode.normal,
        ),
      );

      expect(
        details,
        containsAllInOrder([
          'Vorteil: von der Spielleitung gewählt',
          'Nachteil: Aria ist vergiftet',
          'Vorteil und Nachteil heben sich auf',
        ]),
      );
    });

    test('Die Zustände eines Angriffs bleiben beim Speichern und Laden '
        '(JSON) erhalten', () {
      final original = attackWith(
        [poisoned, restrained],
        chosen: RollMode.advantage,
        rolls: [4],
        mode: RollMode.normal,
      );
      final restored =
          LogEvent.fromJson(original.type, original.toJson()) as AttackEvent;

      expect(restored.chosenMode, RollMode.advantage);
      expect(restored.conditionEffects, hasLength(2));
      expect(restored.conditionEffects.first.condition, 'poisoned');
      expect(restored.conditionEffects.first.onAttacker, isTrue);
      expect(restored.conditionEffects.last.advantage, isTrue);
    });

    test('Ein älterer Angriff ohne diese Angaben lässt sich weiter laden', () {
      final json = missEvent.toJson()
        ..remove('conditionEffects')
        ..remove('chosenMode');

      final restored = LogEvent.fromJson(missEvent.type, json) as AttackEvent;

      expect(restored.conditionEffects, isEmpty);
      expect(restored.chosenMode, RollMode.normal);
    });
  });

  group('Log-Zeilen für Effekte', () {
    BuffEvent event(
      EffectChange change, {
      String? attackBonus,
      int armorClassBonus = 0,
      int? rounds,
    }) => BuffEvent(
      name: 'Aria',
      buff: 'Segen',
      change: change,
      attackBonus: attackBonus,
      armorClassBonus: armorClassBonus,
      rounds: rounds,
    );

    test('Ein vergebener Effekt nennt Kämpfer, Namen, Wirkung und Dauer', () {
      expect(
        formatter
            .format(event(EffectChange.added, attackBonus: '+1d4', rounds: 10))
            .text,
        'Aria erhält Segen (Angriff +1d4, 10 Runden)',
      );
    });

    test('Ein Bonus auf die Rüstungsklasse steht als RK da', () {
      expect(
        formatter.format(event(EffectChange.added, armorClassBonus: 2)).text,
        'Aria erhält Segen (RK +2)',
      );
      expect(
        formatter.format(event(EffectChange.added, armorClassBonus: -2)).text,
        'Aria erhält Segen (RK -2)',
      );
    });

    test('Ein Effekt ohne Werte steht ohne Klammer da', () {
      expect(
        formatter.format(event(EffectChange.added)).text,
        'Aria erhält Segen',
      );
    });

    test('Entfernen und Ablaufen sind unterscheidbar', () {
      expect(
        formatter.format(event(EffectChange.removed)).text,
        'Segen endet bei Aria',
      );
      expect(
        formatter.format(event(EffectChange.expired)).text,
        'Segen endet bei Aria (Dauer abgelaufen)',
      );
    });

    test('Ein Effekt kommt nach dem Speichern und Laden (JSON) unverändert '
        'zurück', () {
      final original = event(
        EffectChange.added,
        attackBonus: '+1d4',
        armorClassBonus: 1,
        rounds: 10,
      );
      final restored =
          LogEvent.fromJson(original.type, original.toJson()) as BuffEvent;

      expect(restored.name, 'Aria');
      expect(restored.buff, 'Segen');
      expect(restored.change, EffectChange.added);
      expect(restored.attackBonus, '+1d4');
      expect(restored.armorClassBonus, 1);
      expect(restored.rounds, 10);
    });

    final shielded = AttackEvent(
      attackerName: 'Aria',
      targetName: 'Oger',
      attackName: 'Langschwert',
      targetArmorClass: 13,
      attackRoll: attackRoll([7]),
      hit: false,
      critical: false,
      damageType: 'Hieb',
      armorClassModifiers: [Modifier('Schild des Glaubens', 2)],
    );

    test('Die Details eines Angriffs zeigen, woraus sich die '
        'Rüstungsklasse des Ziels zusammensetzt', () {
      expect(
        detailsOf(shielded),
        containsAllInOrder([
          'Rüstungsklasse: 11 +2 Schild des Glaubens = 13',
          'Verfehlt gegen RK 13',
        ]),
      );
    });

    test('Ohne Effekt auf die Rüstungsklasse fehlt diese Zeile', () {
      expect(
        detailsOf(missEvent).where((line) => line.startsWith('Rüstungsklasse')),
        isEmpty,
      );
    });

    test('Die Zusammensetzung der Rüstungsklasse bleibt beim Speichern und '
        'Laden (JSON) erhalten', () {
      final restored =
          LogEvent.fromJson(shielded.type, shielded.toJson()) as AttackEvent;

      expect(restored.armorClassModifiers, [
        Modifier('Schild des Glaubens', 2),
      ]);
    });
  });

  group('Log-Zeilen für Bonusschaden aus Effekten', () {
    AttackEvent hexed({DamageEffect? necroticEffect, int damage = 12}) =>
        AttackEvent(
          attackerName: 'Aria',
          targetName: 'Oger',
          attackName: 'Langschwert',
          targetArmorClass: 11,
          attackRoll: attackRoll([15]),
          hit: true,
          critical: false,
          damageType: 'Hieb',
          damageRoll: RollRecord(
            count: 1,
            sides: 8,
            rolls: [4],
            modifiers: [
              Modifier('Schadensbonus', 3),
              Modifier('Mal des Jägers (1d6)', 2),
            ],
          ),
          extraDamage: [
            ExtraDamage(
              damageType: 'Nekrotisch',
              modifiers: [Modifier('Verhexen (1d6)', 5)],
              damageEffect: necroticEffect,
            ),
          ],
          damage: damage,
        );

    test('Die Zeile nennt den gesamten Schaden', () {
      expect(
        formatter.format(hexed(damage: 14)).text,
        'Aria hat Oger für 14 Schaden getroffen',
      );
    });

    test('Die Details zeigen den Bonus gleicher Schadensart beim '
        'Waffenschaden und den Bonus eigener Schadensart getrennt mit '
        'Gesamtschaden', () {
      expect(
        detailsOf(hexed(damage: 14)),
        containsAllInOrder([
          'Schaden (Hieb):',
          '1d8: 4',
          '+3 Schadensbonus',
          '+2 Mal des Jägers (1d6)',
          'Summe: 9',
          'Schaden (Nekrotisch):',
          '+5 Verhexen (1d6)',
          'Summe: 5',
          'Gesamtschaden: 14',
        ]),
      );
    });

    test('Eine Resistenz gegen den Bonusschaden steht in Zeile und '
        'Details', () {
      final event = hexed(necroticEffect: DamageEffect.resistance, damage: 11);

      expect(
        formatter.format(event).text,
        'Aria hat Oger für 11 Schaden getroffen (Resistenz)',
      );
      expect(
        detailsOf(event),
        containsAllInOrder([
          'Resistenz gegen Nekrotisch: 5 → 2',
          'Gesamtschaden: 11',
        ]),
      );
    });

    test('Ohne Bonusschaden eigener Art fehlt die Zeile Gesamtschaden', () {
      expect(
        detailsOf(hitEvent()).where((l) => l.startsWith('Gesamtschaden')),
        isEmpty,
      );
    });

    test('Der Bonusschaden bleibt beim Speichern und Laden (JSON) '
        'erhalten', () {
      final event = hexed(necroticEffect: DamageEffect.resistance);
      final restored =
          LogEvent.fromJson(event.type, event.toJson()) as AttackEvent;

      final extra = restored.extraDamage.single;
      expect(extra.damageType, 'Nekrotisch');
      expect(extra.modifiers, [Modifier('Verhexen (1d6)', 5)]);
      expect(extra.damageEffect, DamageEffect.resistance);
      expect(extra.damage, 2);
    });

    test('Effekte mit Schadens- und Rettungswurfbonus stehen mit ihrer '
        'Wirkung im Log', () {
      const hex = BuffEvent(
        name: 'Aria',
        buff: 'Verhexen',
        change: EffectChange.added,
        damageBonus: '+1d6',
        damageType: 'Nekrotisch',
      );
      const bless = BuffEvent(
        name: 'Aria',
        buff: 'Segen',
        change: EffectChange.added,
        attackBonus: '+1d4',
        saveBonus: '+1d4',
      );

      expect(
        formatter.format(hex).text,
        'Aria erhält Verhexen (Schaden +1d6 Nekrotisch)',
      );
      expect(
        formatter.format(bless).text,
        'Aria erhält Segen (Angriff +1d4, Rettungswurf +1d4)',
      );
    });

    test('Schadens- und Rettungswurfbonus eines Effekts bleiben beim '
        'Speichern und Laden (JSON) erhalten', () {
      const original = BuffEvent(
        name: 'Aria',
        buff: 'Verhexen',
        change: EffectChange.added,
        damageBonus: '+1d6',
        damageType: 'Nekrotisch',
        saveBonus: '+1',
      );
      final restored =
          LogEvent.fromJson(original.type, original.toJson()) as BuffEvent;

      expect(restored.damageBonus, '+1d6');
      expect(restored.damageType, 'Nekrotisch');
      expect(restored.saveBonus, '+1');
    });
  });
}
