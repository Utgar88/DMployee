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
}
