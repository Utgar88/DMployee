import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'combat/encounter.dart';
import 'combat/sqlite_encounter_store.dart';
import 'log/log_repository.dart';
import 'log/sqlite_log_repository.dart';
import 'storage/app_database.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = await openAppDatabase(
    path: p.join(await getDatabasesPath(), 'dmployee.db'),
  );
  final log = SqliteLogRepository(database);
  final encounter = await Encounter.load(
    log: log,
    store: SqliteEncounterStore(database),
  );
  runApp(DMployeeApp(log: log, encounter: encounter));
}

class DMployeeApp extends StatelessWidget {
  const DMployeeApp({super.key, required this.log, this.encounter});

  final LogRepository log;

  /// The combat restored from the last run, if any.
  final Encounter? encounter;

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
      home: HomeScreen(log: log, encounter: encounter),
    );
  }
}
