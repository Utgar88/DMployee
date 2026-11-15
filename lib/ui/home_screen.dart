import 'package:material_ui/material_ui.dart';

import '../combat/encounter.dart';
import '../log/log_repository.dart';
import 'combat_screen.dart';
import 'dice_screen.dart';
import 'log_screen.dart';

/// Root screen: switches between the app's areas with a bottom bar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.log, this.encounter});

  final LogRepository log;

  /// The combat loaded at app start; a new empty one if omitted.
  final Encounter? encounter;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _logTab = 2;

  /// The running encounter. Kept here so it survives switching tabs.
  late final _encounter = widget.encounter ?? Encounter(log: widget.log);

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
          CombatScreen(encounter: _encounter),
          LogScreen(key: ValueKey(_logVisits), log: widget.log),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() {
          _index = index;
          if (index == _logTab) _logVisits++;
        }),
        destinations: const [
          NavigationDestination(
            key: Key('nav-dice'),
            icon: Icon(Icons.casino_outlined),
            label: 'Würfler',
          ),
          NavigationDestination(
            key: Key('nav-combat'),
            icon: Icon(Icons.shield_outlined),
            label: 'Kampf',
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
