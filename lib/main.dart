import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'characters/character_repository.dart';
import 'characters/sqlite_character_repository.dart';
import 'combat/encounter.dart';
import 'combat/sqlite_encounter_store.dart';
import 'log/log_repository.dart';
import 'log/sqlite_log_repository.dart';
import 'settings/app_settings.dart';
import 'settings/sqlite_settings_repository.dart';
import 'storage/app_database.dart';
import 'ui/home_screen.dart';
import 'ui/startup_screen.dart';

/// Everything the app loads from the device before it can be used.
typedef AppData = ({
  LogRepository log,
  CharacterRepository characters,
  Encounter encounter,
  AppSettings settings,
});

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DMployeeApp.starting(load: _openStorage));
}

/// Opens the database, restores the combat of the last run and loads the
/// settings.
Future<AppData> _openStorage() async {
  final database = await openAppDatabase(
    path: p.join(await getDatabasesPath(), 'dmployee.db'),
  );
  final log = SqliteLogRepository(database);
  final characters = SqliteCharacterRepository(database);
  final settings = await AppSettings.load(SqliteSettingsRepository(database));
  final encounter = await Encounter.load(
    log: log,
    store: SqliteEncounterStore(database),
    characters: characters,
    settings: settings,
  );
  return (
    log: log,
    characters: characters,
    encounter: encounter,
    settings: settings,
  );
}

class DMployeeApp extends StatelessWidget {
  /// The app with data that is already loaded; opens the home screen
  /// directly.
  const DMployeeApp({
    super.key,
    required LogRepository this.log,
    this.characters,
    this.encounter,
    this.settings,
  }) : load = null,
       minimumSplash = Duration.zero;

  /// The app as it starts on the device: shows the loading screen while
  /// [load] runs, at least for [minimumSplash].
  const DMployeeApp.starting({
    super.key,
    required Future<AppData> Function() this.load,
    this.minimumSplash = const Duration(milliseconds: 1500),
  }) : log = null,
       characters = null,
       encounter = null,
       settings = null;

  final LogRepository? log;

  /// Stored player characters; kept in memory if omitted.
  final CharacterRepository? characters;

  /// The combat restored from the last run, if any.
  final Encounter? encounter;

  /// The app settings; defaults kept in memory if omitted.
  final AppSettings? settings;
  final Future<AppData> Function()? load;
  final Duration minimumSplash;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DMployee',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: load == null
          ? HomeScreen(
              log: log!,
              characters: characters,
              encounter: encounter,
              settings: settings,
            )
          : StartupScreen<AppData>(
              load: load!,
              minimumDuration: minimumSplash,
              builder: (context, data) => HomeScreen(
                log: data.log,
                characters: data.characters,
                encounter: data.encounter,
                settings: data.settings,
              ),
            ),
    );
  }
}
