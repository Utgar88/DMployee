import 'dart:io';

import 'package:dmployee/dice/dice_roller.dart';
import 'package:dmployee/dice/modifier.dart';
import 'package:dmployee/log/log_event.dart';
import 'package:dmployee/log/log_repository.dart';
import 'package:dmployee/log/roll_record.dart';
import 'package:dmployee/log/sqlite_log_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/fixed_random.dart';

FreeRollEvent rollEvent(int face) => FreeRollEvent(
  roll: RollRecord.fromD20(DiceRoller(FixedRandom([face])).rollD20()),
);

/// A clock for tests: starts at a fixed moment and advances one minute on
/// every reading.
DateTime Function() tickingClock() {
  var current = DateTime(2026, 11, 15, 20, 0);
  return () {
    final now = current;
    current = current.add(const Duration(minutes: 1));
    return now;
  };
}

/// The same expectations apply to every kind of log storage.
void repositoryContract(
  String name,
  Future<LogRepository> Function(DateTime Function() now) create,
) {
  group('Log-Speicher ($name)', () {
    late LogRepository log;

    setUp(() async => log = await create(tickingClock()));
    tearDown(() => log.close());

    test('Ein neuer Speicher enthält keine Einträge', () async {
      expect(await log.entries(), isEmpty);
    });

    test('Ohne gestartete Session wird beim ersten Eintrag automatisch eine '
        'Session mit dem Tagesdatum angelegt', () async {
      final entry = await log.add(rollEvent(10));

      final sessions = await log.sessions();
      expect(sessions, hasLength(1));
      expect(sessions.single.name, 'Session 15.11.2026');
      expect(entry.sessionId, sessions.single.id);
    });

    test('Ein Eintrag erhält Zeitstempel und fortlaufende Nummer', () async {
      final first = await log.add(rollEvent(10));
      final second = await log.add(rollEvent(11));

      expect(second.id, greaterThan(first.id));
      expect(second.timestamp.isAfter(first.timestamp), isTrue);
    });

    test('Einträge werden mit dem neuesten zuerst geliefert', () async {
      await log.add(rollEvent(3));
      await log.add(rollEvent(18));

      final entries = await log.entries();

      expect(
        entries.map((entry) => (entry.event as FreeRollEvent).roll.total),
        [18, 3],
      );
    });

    test('Ein gespeichertes Ereignis kommt mit allen Details zurück', () async {
      await log.add(
        FreeRollEvent(
          roll: RollRecord.fromD20(
            DiceRoller(FixedRandom([7, 15])).rollD20(
              mode: RollMode.advantage,
              modifiers: [Modifier('Stärke', 5)],
            ),
          ),
          dc: 18,
        ),
      );

      final event = (await log.entries()).single.event as FreeRollEvent;

      expect(event.roll.rolls, [7, 15]);
      expect(event.roll.mode, RollMode.advantage);
      expect(event.roll.modifiers, [Modifier('Stärke', 5)]);
      expect(event.roll.total, 20);
      expect(event.dc, 18);
    });

    test('Neue Einträge landen in der zuletzt gestarteten Session', () async {
      final first = await log.startSession('Abend 1');
      await log.add(rollEvent(5));
      final second = await log.startSession('Abend 2');
      final entry = await log.add(rollEvent(6));

      expect(entry.sessionId, second.id);
      expect(entry.sessionId, isNot(first.id));
      expect((await log.activeSession()).name, 'Abend 2');
    });

    test('Sessions werden mit der neuesten zuerst geliefert', () async {
      await log.startSession('Abend 1');
      await log.startSession('Abend 2');

      expect((await log.sessions()).map((s) => s.name), ['Abend 2', 'Abend 1']);
    });

    test('Einträge lassen sich nach Session filtern', () async {
      final first = await log.startSession('Abend 1');
      await log.add(rollEvent(5));
      await log.add(rollEvent(6));
      final second = await log.startSession('Abend 2');
      await log.add(rollEvent(7));

      expect(await log.entries(sessionId: first.id), hasLength(2));
      expect(await log.entries(sessionId: second.id), hasLength(1));
      expect(await log.entries(), hasLength(3));
    });
  });
}

void main() {
  sqfliteFfiInit();

  repositoryContract(
    'Arbeitsspeicher',
    (now) async => InMemoryLogRepository(now: now),
  );

  repositoryContract(
    'SQLite',
    (now) => SqliteLogRepository.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
      now: now,
    ),
  );

  group('Log-Speicher (SQLite): Dauerhaftigkeit', () {
    test('Einträge und Sessions sind nach dem Schließen und erneuten Öffnen '
        'der Datenbank noch vorhanden', () async {
      final directory = await Directory.systemTemp.createTemp('dmployee_log');
      final path = '${directory.path}/log.db';
      addTearDown(() => directory.delete(recursive: true));

      final first = await SqliteLogRepository.open(
        factory: databaseFactoryFfi,
        path: path,
        now: tickingClock(),
      );
      await first.startSession('Abend 1');
      await first.add(rollEvent(17));
      await first.close();

      final reopened = await SqliteLogRepository.open(
        factory: databaseFactoryFfi,
        path: path,
        now: tickingClock(),
      );
      addTearDown(reopened.close);

      final entries = await reopened.entries();
      expect((await reopened.sessions()).single.name, 'Abend 1');
      expect(entries, hasLength(1));
      expect((entries.single.event as FreeRollEvent).roll.total, 17);
    });
  });
}
