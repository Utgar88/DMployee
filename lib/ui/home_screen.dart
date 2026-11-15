import 'package:material_ui/material_ui.dart';

import '../log/log_repository.dart';
import 'dice_screen.dart';
import 'log_screen.dart';

/// Root screen: switches between the app's areas with a bottom bar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.log});

  final LogRepository log;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  /// Counts openings of the log tab so it reloads its entries each time.
  int _logVisits = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          DiceScreen(log: widget.log),
          LogScreen(key: ValueKey(_logVisits), log: widget.log),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() {
          _index = index;
          if (index == 1) _logVisits++;
        }),
        destinations: const [
          NavigationDestination(
            key: Key('nav-dice'),
            icon: Icon(Icons.casino_outlined),
            label: 'Würfler',
          ),
          NavigationDestination(
            key: Key('nav-log'),
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Log',
          ),
        ],
      ),
    );
  }
}
