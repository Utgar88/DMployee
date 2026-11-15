import 'package:material_ui/material_ui.dart';

import 'ui/dice_screen.dart';

void main() {
  runApp(const DMployeeApp());
}

class DMployeeApp extends StatelessWidget {
  const DMployeeApp({super.key});

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
      home: DiceScreen(),
    );
  }
}
