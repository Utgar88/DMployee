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
}
