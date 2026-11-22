import 'dart:io';

import 'package:dmployee/settings/settings_repository.dart';
import 'package:dmployee/settings/sqlite_settings_repository.dart';
import 'package:dmployee/storage/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The same expectations apply to every kind of storage for settings.
void repositoryContract(
  String name,
  Future<(SettingsRepository, Future<void> Function())> Function() create,
) {
  group('Einstellungs-Speicher ($name)', () {
    late SettingsRepository repository;
    late Future<void> Function() close;

    setUp(() async => (repository, close) = await create());
    tearDown(() => close());

    test('Eine nie gespeicherte Einstellung ist leer', () async {
      expect(await repository.read('ruleset'), isNull);
    });

    test('Eine gespeicherte Einstellung kommt unverändert zurück', () async {
      await repository.write('ruleset', '5e-2024');

      expect(await repository.read('ruleset'), '5e-2024');
    });

    test('Erneutes Speichern ersetzt den Wert', () async {
      await repository.write('ruleset', '5e-2024');
      await repository.write('ruleset', '5e-2014');

      expect(await repository.read('ruleset'), '5e-2014');
    });

    test('Einstellungen mit verschiedenen Namen stören sich nicht', () async {
      await repository.write('ruleset', '5e-2024');
      await repository.write('other', 'x');

      expect(await repository.read('ruleset'), '5e-2024');
      expect(await repository.read('other'), 'x');
    });
  });
}

void main() {
  sqfliteFfiInit();

  repositoryContract('Arbeitsspeicher', () async {
    return (InMemorySettingsRepository(), () async {});
  });

  repositoryContract('SQLite', () async {
    final database = await openAppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    return (SqliteSettingsRepository(database), database.close);
  });

  test('SQLite: Einstellungen überleben das Schließen und erneute Öffnen '
      'der Datenbank', () async {
    final directory = await Directory.systemTemp.createTemp('dmployee_set');
    final path = '${directory.path}/dmployee.db';
    addTearDown(() => directory.delete(recursive: true));

    final first = await openAppDatabase(
      factory: databaseFactoryFfi,
      path: path,
    );
    await SqliteSettingsRepository(first).write('ruleset', '5e-2024');
    await first.close();

    final second = await openAppDatabase(
      factory: databaseFactoryFfi,
      path: path,
    );
    addTearDown(second.close);
    expect(await SqliteSettingsRepository(second).read('ruleset'), '5e-2024');
  });
}
