import 'dart:io';

import 'package:dmployee/characters/character.dart';
import 'package:dmployee/characters/sqlite_character_repository.dart';
import 'package:dmployee/combat/sqlite_encounter_store.dart';
import 'package:dmployee/log/log_event.dart';
import 'package:dmployee/log/sqlite_log_repository.dart';
import 'package:dmployee/storage/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Creates a database as the first app version (log only) left it on the
/// device, with one session and one log entry.
Future<void> createVersion1Database(String path) async {
  final database = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      singleInstance: false,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            started_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE log_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL REFERENCES sessions (id),
            timestamp INTEGER NOT NULL,
            type TEXT NOT NULL,
            payload TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX log_entries_session ON log_entries (session_id, id)',
        );
      },
    ),
  );
  final session = await database.insert('sessions', {
    'name': 'Abend 1',
    'started_at': 1000,
  });
  await database.insert('log_entries', {
    'session_id': session,
    'timestamp': 2000,
    'type': 'round',
    'payload': '{"round":3}',
  });
  await database.close();
}

void main() {
  sqfliteFfiInit();

  group('App-Datenbank', () {
    test('Log und Kampfstand liegen in derselben Datenbank', () async {
      final database = await openAppDatabase(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      addTearDown(database.close);
      final log = SqliteLogRepository(database);
      final store = SqliteEncounterStore(database);

      await log.add(const RoundEvent(1));
      await store.save({'round': 1});

      expect(await log.entries(), hasLength(1));
      expect(await store.load(), {'round': 1});
    });

    test('Eine Datenbank der ersten App-Version (nur Log) wird beim Öffnen '
        'erweitert: der Log bleibt erhalten, der Kampfstand lässt sich '
        'speichern', () async {
      final directory = await Directory.systemTemp.createTemp('dmployee_db');
      final path = '${directory.path}/dmployee.db';
      addTearDown(() => directory.delete(recursive: true));
      await createVersion1Database(path);

      final database = await openAppDatabase(
        factory: databaseFactoryFfi,
        path: path,
      );
      addTearDown(database.close);
      final log = SqliteLogRepository(database);
      final store = SqliteEncounterStore(database);

      expect((await log.sessions()).single.name, 'Abend 1');
      expect(((await log.entries()).single.event as RoundEvent).round, 3);
      expect(await store.load(), isNull);
      await store.save({'round': 2});
      expect(await store.load(), {'round': 2});
    });
    test('Eine Datenbank der zweiten App-Version (Log und Kampfstand) wird '
        'um die Charaktere erweitert; Log und Kampfstand bleiben '
        'erhalten', () async {
      final directory = await Directory.systemTemp.createTemp('dmployee_db');
      final path = '${directory.path}/dmployee.db';
      addTearDown(() => directory.delete(recursive: true));
      await createVersion1Database(path);
      final version2 = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          singleInstance: false,
          onUpgrade: (db, oldVersion, newVersion) => db.execute('''
            CREATE TABLE encounter_state (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              payload TEXT NOT NULL
            )
          '''),
        ),
      );
      await SqliteEncounterStore(version2).save({'round': 4});
      await version2.close();

      final database = await openAppDatabase(
        factory: databaseFactoryFfi,
        path: path,
      );
      addTearDown(database.close);
      final characters = SqliteCharacterRepository(database);

      expect(
        ((await SqliteLogRepository(database).entries()).single.event
                as RoundEvent)
            .round,
        3,
      );
      expect(await SqliteEncounterStore(database).load(), {'round': 4});
      expect(await characters.all(), isEmpty);
      await characters.save(Character(name: 'Aria', maxHp: 20, armorClass: 16));
      expect((await characters.all()).single.name, 'Aria');
    });
  });
}
