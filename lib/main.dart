import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'log/log_repository.dart';
import 'log/sqlite_log_repository.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final log = await SqliteLogRepository.open(
    path: p.join(await getDatabasesPath(), 'dmployee.db'),
  );
  runApp(DMployeeApp(log: log));
}

class DMployeeApp extends StatelessWidget {
  const DMployeeApp({super.key, required this.log});

  final LogRepository log;

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
      home: HomeScreen(log: log),
    );
  }
}
