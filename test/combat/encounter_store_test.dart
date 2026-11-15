import 'dart:io';

import 'package:dmployee/combat/encounter_store.dart';
import 'package:dmployee/combat/sqlite_encounter_store.dart';
import 'package:dmployee/storage/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const state = <String, Object?>{
  'round': 2,
  'current': 1,
  'combatants': [
    {'name': 'Aria', 'hp': 12},
    {'name': 'Goblin', 'hp': 0},
  ],
};

/// The same expectations apply to every kind of storage for the combat.
void storeContract(
  String name,
  Future<(EncounterStore, Future<void> Function())> Function() create,
) {
  group('Kampf-Speicher ($name)', () {
    late EncounterStore store;
    late Future<void> Function() close;

    setUp(() async => (store, close) = await create());
    tearDown(() => close());

    test('Ein neuer Speicher enthält keinen Kampfstand', () async {
      expect(await store.load(), isNull);
    });

    test('Ein gespeicherter Kampfstand kommt unverändert zurück', () async {
      await store.save(state);

      expect(await store.load(), state);
    });

    test('Erneutes Speichern ersetzt den bisherigen Stand', () async {
      await store.save(state);
      await store.save({'round': 0, 'combatants': <Object?>[]});

      expect(await store.load(), {'round': 0, 'combatants': <Object?>[]});
    });
  });
}

void main() {
  sqfliteFfiInit();

  storeContract(
    'Arbeitsspeicher',
    () async => (InMemoryEncounterStore(), () async {}),
  );

  storeContract('SQLite', () async {
    final database = await openAppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    return (SqliteEncounterStore(database), database.close);
  });

  group('Kampf-Speicher (SQLite): Dauerhaftigkeit', () {
    test('Der Kampfstand ist nach dem Schließen und erneuten Öffnen der '
        'Datenbank noch vorhanden', () async {
      final directory = await Directory.systemTemp.createTemp('dmployee_enc');
      final path = '${directory.path}/app.db';
      addTearDown(() => directory.delete(recursive: true));

      final first = await openAppDatabase(
        factory: databaseFactoryFfi,
        path: path,
      );
      await SqliteEncounterStore(first).save(state);
      await first.close();

      final reopened = await openAppDatabase(
        factory: databaseFactoryFfi,
        path: path,
      );
      addTearDown(reopened.close);

      expect(await SqliteEncounterStore(reopened).load(), state);
    });
  });
}
