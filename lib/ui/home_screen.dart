import 'package:material_ui/material_ui.dart';

import '../characters/character_repository.dart';
import '../combat/encounter.dart';
import '../log/log_repository.dart';
import 'characters_screen.dart';
import 'combat_screen.dart';
import 'dice_screen.dart';
import 'log_screen.dart';

/// Root screen. The bottom bar switches between what is needed all the
/// time during play (Würfler, Kampf, Log); the menu on the left opens the
/// areas for preparation (Charaktere, later Compendium and settings).
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.log,
    this.characters,
    this.encounter,
  });

  final LogRepository log;

  /// Stored player characters; kept in memory if omitted.
  final CharacterRepository? characters;

  /// The combat loaded at app start; a new empty one if omitted.
  final Encounter? encounter;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _logTab = 2;

  final _scaffold = GlobalKey<ScaffoldState>();

  late final CharacterRepository _characters =
      widget.characters ?? InMemoryCharacterRepository();

  /// The running encounter. Kept here so it survives switching tabs.
  late final _encounter =
      widget.encounter ?? Encounter(log: widget.log, characters: _characters);

  int _index = 0;

  /// Counts openings of the log tab so it reloads its entries each time.
  int _logVisits = 0;

  void _openMenu() => _scaffold.currentState?.openDrawer();

  Future<void> _openCharacters() async {
    Navigator.pop(context);
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CharactersScreen(characters: _characters, encounter: _encounter),
      ),
    );
    // Characters may have joined the combat meanwhile.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffold,
      drawer: NavigationDrawer(
        onDestinationSelected: (_) => _openCharacters(),
        selectedIndex: null,
        children: const [
          Padding(
            padding: EdgeInsets.fromLTRB(28, 16, 16, 10),
            child: Text('DMployee'),
          ),
          NavigationDrawerDestination(
            key: Key('drawer-characters'),
            icon: Icon(Icons.people_outline),
            label: Text('Charaktere'),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          DiceScreen(log: widget.log, onOpenMenu: _openMenu),
          CombatScreen(
            encounter: _encounter,
            characters: _characters,
            onOpenMenu: _openMenu,
          ),
          LogScreen(
            key: ValueKey(_logVisits),
            log: widget.log,
            onOpenMenu: _openMenu,
          ),
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
