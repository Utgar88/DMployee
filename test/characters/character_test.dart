import 'package:dmployee/characters/ability.dart';
import 'package:dmployee/characters/character.dart';
import 'package:dmployee/combat/attack.dart';
import 'package:dmployee/dice/dice_expression.dart';
import 'package:flutter_test/flutter_test.dart';

final longsword = Attack(
  name: 'Langschwert',
  attackBonus: 5,
  damage: DiceExpression.parse('1d8+3'),
  damageType: 'Hieb',
);

/// Aria, Kämpferin der Stufe 5: ST 16, GE 14, KO 15, IN 8, WE 12, CH 10,
/// 44 TP, RK 18, geübt in Rettungswürfen auf Stärke und Konstitution.
Character aria() => Character(
  name: 'Aria',
  player: 'Dirk',
  characterClass: 'Kämpferin',
  level: 5,
  abilityScores: {
    Ability.strength: 16,
    Ability.dexterity: 14,
    Ability.constitution: 15,
    Ability.intelligence: 8,
    Ability.wisdom: 12,
    Ability.charisma: 10,
  },
  maxHp: 44,
  armorClass: 18,
  saveProficiencies: {Ability.strength, Ability.constitution},
  attacks: [longsword],
);

void main() {
  group('Attribute', () {
    test('Die sechs Attribute haben deutsche Namen und Kürzel', () {
      expect(Ability.values.map((a) => a.label), [
        'Stärke',
        'Geschicklichkeit',
        'Konstitution',
        'Intelligenz',
        'Weisheit',
        'Charisma',
      ]);
      expect(Ability.values.map((a) => a.short), [
        'ST',
        'GE',
        'KO',
        'IN',
        'WE',
        'CH',
      ]);
    });

    test('Der Modifikator ist (Wert - 10) / 2, abgerundet', () {
      expect(abilityModifier(10), 0);
      expect(abilityModifier(11), 0);
      expect(abilityModifier(16), 3);
      expect(abilityModifier(15), 2);
      expect(abilityModifier(9), -1);
      expect(abilityModifier(8), -1);
      expect(abilityModifier(1), -5);
      expect(abilityModifier(30), 10);
    });

    test('Ein Modifikator wird mit Vorzeichen angezeigt', () {
      expect(formatModifier(3), '+3');
      expect(formatModifier(0), '+0');
      expect(formatModifier(-1), '-1');
    });
  });

  group('Übungsbonus', () {
    test('Der Übungsbonus steigt alle vier Stufen um 1, von +2 bis +6', () {
      expect(proficiencyBonusFor(1), 2);
      expect(proficiencyBonusFor(4), 2);
      expect(proficiencyBonusFor(5), 3);
      expect(proficiencyBonusFor(8), 3);
      expect(proficiencyBonusFor(9), 4);
      expect(proficiencyBonusFor(13), 5);
      expect(proficiencyBonusFor(17), 6);
      expect(proficiencyBonusFor(20), 6);
    });
  });

  group('Charakter: Werte', () {
    test('Ein neuer Charakter hat volle Trefferpunkte', () {
      final character = aria();

      expect(character.hp, 44);
      expect(character.tempHp, 0);
      expect(character.isDead, isFalse);
    });

    test('Nicht angegebene Attribute haben den Wert 10', () {
      final character = Character(name: 'Borin', maxHp: 12, armorClass: 15);

      expect(character.score(Ability.wisdom), 10);
      expect(character.modifier(Ability.wisdom), 0);
      expect(character.level, 1);
    });

    test('Modifikatoren, Übungsbonus und Initiative werden aus den Werten '
        'berechnet', () {
      final character = aria();

      expect(character.modifier(Ability.strength), 3);
      expect(character.modifier(Ability.intelligence), -1);
      expect(character.proficiencyBonus, 3);
      expect(character.initiativeBonus, 2);
    });

    test('Rettungswürfe: Modifikator plus Übungsbonus, wenn geübt', () {
      final character = aria();

      expect(character.savingThrow(Ability.strength), 6);
      expect(character.savingThrow(Ability.constitution), 5);
      expect(character.savingThrow(Ability.dexterity), 2);
      expect(character.savingThrow(Ability.intelligence), -1);
    });

    test('Klasse und Stufe ergeben eine Kurzform', () {
      expect(aria().classAndLevel, 'Kämpferin 5');
      expect(
        Character(name: 'Borin', maxHp: 12, armorClass: 15).classAndLevel,
        'Stufe 1',
      );
    });

    test('Ungültige Werte werden abgelehnt', () {
      Character make({
        String name = 'Borin',
        int level = 1,
        int maxHp = 12,
        int armorClass = 15,
        int strength = 10,
      }) => Character(
        name: name,
        level: level,
        maxHp: maxHp,
        armorClass: armorClass,
        abilityScores: {Ability.strength: strength},
      );

      expect(() => make(name: ' '), throwsArgumentError);
      expect(() => make(level: 0), throwsArgumentError);
      expect(() => make(level: 21), throwsArgumentError);
      expect(() => make(maxHp: 0), throwsArgumentError);
      expect(() => make(armorClass: -1), throwsArgumentError);
      expect(() => make(strength: 0), throwsArgumentError);
      expect(() => make(strength: 31), throwsArgumentError);
    });

    test('Name, Spieler und Klasse werden ohne Leerzeichen am Rand '
        'gespeichert', () {
      final character = Character(
        name: ' Borin ',
        player: ' Anna ',
        characterClass: ' Kleriker ',
        maxHp: 12,
        armorClass: 15,
      );

      expect(character.name, 'Borin');
      expect(character.player, 'Anna');
      expect(character.characterClass, 'Kleriker');
    });
  });

  group('Charakter: Werte ändern', () {
    test('Ein unverletzter Charakter hat mit neuem Maximum wieder volle '
        'Trefferpunkte', () {
      final changed = aria().withValues(maxHp: 52);

      expect(changed.maxHp, 52);
      expect(changed.hp, 52);
    });

    test('Ein verletzter Charakter behält seine Trefferpunkte, höchstens '
        'das neue Maximum', () {
      final hurt = aria()..hp = 30;

      expect(hurt.withValues(maxHp: 52).hp, 30);
      expect(hurt.withValues(maxHp: 20).hp, 20);
    });

    test('Beim Ändern bleiben Kennung und Zustand erhalten', () {
      final original = aria()
        ..id = 7
        ..hp = 0
        ..deathSaveFailures = 2;

      final changed = original.withValues(name: 'Arya', armorClass: 19);

      expect(changed.id, 7);
      expect(changed.name, 'Arya');
      expect(changed.armorClass, 19);
      expect(changed.level, 5);
      expect(changed.hp, 0);
      expect(changed.deathSaveFailures, 2);
    });
  });

  group('Charakter: Speichern und Laden (JSON)', () {
    test('Alle Werte und der Zustand kommen unverändert zurück', () {
      final original = aria()
        ..id = 3
        ..hp = 20
        ..tempHp = 5
        ..deathSaveSuccesses = 1
        ..deathSaveFailures = 2
        ..isStable = true;

      final restored = Character.fromJson(original.toJson());

      expect(restored.id, 3);
      expect(restored.name, 'Aria');
      expect(restored.player, 'Dirk');
      expect(restored.characterClass, 'Kämpferin');
      expect(restored.level, 5);
      expect(restored.score(Ability.strength), 16);
      expect(restored.score(Ability.intelligence), 8);
      expect(restored.maxHp, 44);
      expect(restored.armorClass, 18);
      expect(restored.saveProficiencies, {
        Ability.strength,
        Ability.constitution,
      });
      expect(restored.attacks.single.summary, longsword.summary);
      expect(restored.hp, 20);
      expect(restored.tempHp, 5);
      expect(restored.deathSaveSuccesses, 1);
      expect(restored.deathSaveFailures, 2);
      expect(restored.isStable, isTrue);
      expect(restored.isDead, isFalse);
    });
  });

  group('Charakter: Trefferwürfel', () {
    test('Ein neuer Charakter hat W8 als Trefferwürfel und so viele '
        'Trefferwürfel wie Stufen, alle übrig', () {
      final aria = Character(name: 'Aria', level: 5, maxHp: 30, armorClass: 15);

      expect(aria.hitDie, 8);
      expect(aria.hitDiceTotal, 5);
      expect(aria.hitDiceSpent, 0);
      expect(aria.hitDiceRemaining, 5);
    });

    test('Als Trefferwürfel sind W6, W8, W10 und W12 möglich', () {
      expect(Character.hitDieSizes, [6, 8, 10, 12]);
      for (final size in Character.hitDieSizes) {
        expect(
          Character(name: 'A', maxHp: 10, armorClass: 10, hitDie: size).hitDie,
          size,
        );
      }
    });

    test('Ein anderer Trefferwürfel als W6, W8, W10 oder W12 wird '
        'abgelehnt', () {
      expect(
        () => Character(name: 'A', maxHp: 10, armorClass: 10, hitDie: 4),
        throwsArgumentError,
      );
      expect(
        () => Character(name: 'A', maxHp: 10, armorClass: 10, hitDie: 20),
        throwsArgumentError,
      );
    });

    test('Ausgegebene Trefferwürfel verringern die übrigen', () {
      final aria = Character(name: 'Aria', level: 5, maxHp: 30, armorClass: 15)
        ..hitDiceSpent = 2;

      expect(aria.hitDiceRemaining, 3);
    });

    test('Der Trefferwürfel lässt sich über den Bogen ändern; ausgegebene '
        'Trefferwürfel bleiben', () {
      final aria = Character(name: 'Aria', level: 5, maxHp: 30, armorClass: 15)
        ..hitDiceSpent = 2;

      final changed = aria.withValues(hitDie: 10);

      expect(changed.hitDie, 10);
      expect(changed.hitDiceSpent, 2);
    });

    test('Sinkt die Stufe, sind höchstens so viele Trefferwürfel ausgegeben, '
        'wie der Charakter noch hat', () {
      final aria = Character(name: 'Aria', level: 5, maxHp: 30, armorClass: 15)
        ..hitDiceSpent = 4;

      final lower = aria.withValues(level: 3);

      expect(lower.hitDiceSpent, 3);
      expect(lower.hitDiceRemaining, 0);
    });

    test('Trefferwürfel und ausgegebene Trefferwürfel werden gespeichert', () {
      final aria = Character(
        name: 'Aria',
        level: 5,
        maxHp: 30,
        armorClass: 15,
        hitDie: 10,
      )..hitDiceSpent = 2;

      final restored = Character.fromJson(aria.toJson());

      expect(restored.hitDie, 10);
      expect(restored.hitDiceSpent, 2);
    });

    test('Ein früher gespeicherter Charakter ohne Trefferwürfel bekommt W8, '
        'alle Trefferwürfel übrig', () {
      final json =
          Character(name: 'Aria', level: 4, maxHp: 30, armorClass: 15).toJson()
            ..remove('hitDie')
            ..remove('hitDiceSpent');

      final restored = Character.fromJson(json);

      expect(restored.hitDie, 8);
      expect(restored.hitDiceRemaining, 4);
    });
  });

  group('Charakter: Zauberplätze', () {
    Character caster() => Character(
      name: 'Mira',
      level: 5,
      maxHp: 28,
      armorClass: 12,
      spellSlots: {1: 4, 2: 3, 3: 2},
    );

    test('Ein neuer Charakter hat keine Zauberplätze und keine '
        'Paktmagie', () {
      final aria = Character(name: 'Aria', maxHp: 30, armorClass: 15);

      expect(aria.hasSpellSlots, isFalse);
      for (var level = 1; level <= 9; level++) {
        expect(aria.slotsTotal(level), 0);
      }
      expect(aria.pactSlots, 0);
    });

    test('Zauberplätze werden je Grad 1 bis 9 angegeben; nicht angegebene '
        'Grade haben keine', () {
      final mira = caster();

      expect(mira.hasSpellSlots, isTrue);
      expect(mira.slotsTotal(1), 4);
      expect(mira.slotsTotal(3), 2);
      expect(mira.slotsTotal(4), 0);
      expect(mira.slotLevels, [1, 2, 3]);
    });

    test('Verbrauchte Zauberplätze verringern die übrigen', () {
      final mira = caster()..slotsUsed[1] = 3;

      expect(mira.slotsRemaining(1), 1);
      expect(mira.slotsRemaining(2), 3);
    });

    test('Paktmagie hat eine Anzahl und einen gemeinsamen Grad', () {
      final hex = Character(
        name: 'Hex',
        level: 5,
        maxHp: 30,
        armorClass: 13,
        pactSlots: 2,
        pactSlotLevel: 3,
      )..pactSlotsUsed = 1;

      expect(hex.hasSpellSlots, isTrue);
      expect(hex.pactSlots, 2);
      expect(hex.pactSlotLevel, 3);
      expect(hex.pactSlotsRemaining, 1);
    });

    test('Ungültige Angaben werden abgelehnt: Grad außerhalb 1 bis 9, '
        'Anzahl unter 0 oder über 9, Paktgrad außerhalb 1 bis 5', () {
      Character make({
        Map<int, int> slots = const {},
        int pact = 0,
        int pactLevel = 1,
      }) => Character(
        name: 'A',
        maxHp: 10,
        armorClass: 10,
        spellSlots: slots,
        pactSlots: pact,
        pactSlotLevel: pactLevel,
      );

      expect(() => make(slots: {0: 1}), throwsArgumentError);
      expect(() => make(slots: {10: 1}), throwsArgumentError);
      expect(() => make(slots: {1: -1}), throwsArgumentError);
      expect(() => make(slots: {1: 10}), throwsArgumentError);
      expect(() => make(pact: -1), throwsArgumentError);
      expect(() => make(pact: 10), throwsArgumentError);
      expect(() => make(pact: 2, pactLevel: 0), throwsArgumentError);
      expect(() => make(pact: 2, pactLevel: 6), throwsArgumentError);
    });

    test('Ein Grad mit 0 Plätzen zählt nicht als vorhanden', () {
      final mira = Character(
        name: 'Mira',
        maxHp: 10,
        armorClass: 10,
        spellSlots: {1: 0, 2: 2},
      );

      expect(mira.slotLevels, [2]);
    });

    test('Zauberplätze lassen sich über den Bogen ändern; verbrauchte '
        'bleiben, höchstens so viele wie es noch gibt', () {
      final mira = caster()
        ..slotsUsed[1] = 2
        ..slotsUsed[3] = 2;

      final changed = mira.withValues(spellSlots: {1: 4, 2: 3, 3: 1});

      expect(changed.slotsTotal(3), 1);
      expect(changed.slotsUsed[1], 2);
      expect(changed.slotsRemaining(3), 0);
      expect(changed.slotsUsed[3], 1);
    });

    test('Weniger Paktmagie-Plätze begrenzen die verbrauchten', () {
      final hex = Character(
        name: 'Hex',
        maxHp: 30,
        armorClass: 13,
        pactSlots: 2,
        pactSlotLevel: 3,
      )..pactSlotsUsed = 2;

      final changed = hex.withValues(pactSlots: 1, pactSlotLevel: 2);

      expect(changed.pactSlots, 1);
      expect(changed.pactSlotLevel, 2);
      expect(changed.pactSlotsUsed, 1);
    });

    test('Zauberplätze, Paktmagie und Verbrauch werden gespeichert', () {
      final mira =
          Character(
              name: 'Mira',
              maxHp: 28,
              armorClass: 12,
              spellSlots: {1: 4, 3: 2},
              pactSlots: 2,
              pactSlotLevel: 4,
            )
            ..slotsUsed[1] = 1
            ..slotsUsed[3] = 2
            ..pactSlotsUsed = 1;

      final restored = Character.fromJson(mira.toJson());

      expect(restored.slotsTotal(1), 4);
      expect(restored.slotsTotal(3), 2);
      expect(restored.slotsRemaining(1), 3);
      expect(restored.slotsRemaining(3), 0);
      expect(restored.pactSlots, 2);
      expect(restored.pactSlotLevel, 4);
      expect(restored.pactSlotsRemaining, 1);
    });

    test('Ein früher gespeicherter Charakter ohne Angaben hat keine '
        'Zauberplätze', () {
      final json = Character(name: 'Aria', maxHp: 30, armorClass: 15).toJson()
        ..remove('spellSlots')
        ..remove('slotsUsed')
        ..remove('pactSlots')
        ..remove('pactSlotLevel')
        ..remove('pactSlotsUsed');

      final restored = Character.fromJson(json);

      expect(restored.hasSpellSlots, isFalse);
      expect(restored.pactSlotsRemaining, 0);
    });
  });
}
