import 'dart:io';

import 'package:dmployee/characters/ability.dart';
import 'package:dmployee/characters/character.dart';
import 'package:dmployee/characters/character_repository.dart';
import 'package:dmployee/characters/sqlite_character_repository.dart';
import 'package:dmployee/storage/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Character character(String name, {int maxHp = 20}) => Character(
  name: name,
  characterClass: 'Kämpferin',
  level: 3,
  abilityScores: {Ability.strength: 16},
  maxHp: maxHp,
  armorClass: 16,
);

/// The same expectations apply to every kind of storage for characters.
void repositoryContract(
  String name,
  Future<(CharacterRepository, Future<void> Function())> Function() create,
) {
  group('Charakter-Speicher ($name)', () {
    late CharacterRepository repository;
    late Future<void> Function() close;

    setUp(() async => (repository, close) = await create());
    tearDown(() => close());

    test('Ein neuer Speicher enthält keine Charaktere', () async {
      expect(await repository.all(), isEmpty);
    });

    test('Ein neuer Charakter bekommt beim Speichern eine Kennung', () async {
      final aria = await repository.save(character('Aria'));
      final borin = await repository.save(character('Borin'));

      expect(aria.id, isNotNull);
      expect(borin.id, isNot(aria.id));
    });

    test('Ein gespeicherter Charakter kommt mit allen Werten zurück', () async {
      final saved = await repository.save(character('Aria')..hp = 7);

      final loaded = (await repository.byId(saved.id!))!;

      expect(loaded.name, 'Aria');
      expect(loaded.classAndLevel, 'Kämpferin 3');
      expect(loaded.score(Ability.strength), 16);
      expect(loaded.hp, 7);
    });

    test('Erneutes Speichern ersetzt den Charakter, statt einen weiteren '
        'anzulegen', () async {
      final saved = await repository.save(character('Aria'));

      await repository.save(saved.withValues(name: 'Arya')..hp = 3);

      final all = await repository.all();
      expect(all, hasLength(1));
      expect(all.single.name, 'Arya');
      expect(all.single.hp, 3);
    });

    test('Alle Charaktere kommen nach Namen sortiert, ohne Rücksicht auf '
        'Groß- und Kleinschreibung', () async {
      await repository.save(character('borin'));
      await repository.save(character('Cael'));
      await repository.save(character('Aria'));

      expect((await repository.all()).map((c) => c.name), [
        'Aria',
        'borin',
        'Cael',
      ]);
    });

    test('Ein Charakter lässt sich löschen', () async {
      final aria = await repository.save(character('Aria'));
      await repository.save(character('Borin'));

      await repository.delete(aria.id!);

      expect(await repository.byId(aria.id!), isNull);
      expect((await repository.all()).single.name, 'Borin');
    });

    test('Eine unbekannte Kennung liefert keinen Charakter', () async {
      expect(await repository.byId(99), isNull);
    });
  });
}

void main() {
  sqfliteFfiInit();

  repositoryContract(
    'Arbeitsspeicher',
    () async => (InMemoryCharacterRepository(), () async {}),
  );

  repositoryContract('SQLite', () async {
    final database = await openAppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    return (SqliteCharacterRepository(database), database.close);
  });

  group('Charakter-Speicher (SQLite): Dauerhaftigkeit', () {
    test('Charaktere sind nach dem Schließen und erneuten Öffnen der '
        'Datenbank noch vorhanden', () async {
      final directory = await Directory.systemTemp.createTemp('dmployee_chr');
      final path = '${directory.path}/app.db';
      addTearDown(() => directory.delete(recursive: true));

      final first = await openAppDatabase(
        factory: databaseFactoryFfi,
        path: path,
      );
      await SqliteCharacterRepository(first).save(character('Aria'));
      await first.close();

      final reopened = await openAppDatabase(
        factory: databaseFactoryFfi,
        path: path,
      );
      addTearDown(reopened.close);

      expect(
        (await SqliteCharacterRepository(reopened).all()).single.name,
        'Aria',
      );
    });
  });
}
