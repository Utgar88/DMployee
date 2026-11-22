import 'package:material_ui/material_ui.dart';

import '../characters/character.dart';
import '../characters/character_repository.dart';
import '../characters/exhaustion.dart';
import '../characters/rest.dart';
import '../characters/spell_slots.dart';
import '../combat/encounter.dart';
import '../log/log_event.dart';
import 'character_edit_screen.dart';
import 'exhaustion_dialog.dart';
import 'rest_screens.dart';
import 'spell_slots_dialog.dart';

/// All stored player characters: open their sheet, create new ones and send
/// them into the combat.
class CharactersScreen extends StatefulWidget {
  const CharactersScreen({
    super.key,
    required this.characters,
    required this.encounter,
    this.rests,
    this.spellSlots,
    this.exhaustion,
  });

  final CharacterRepository characters;
  final Encounter encounter;

  /// Short and long rests; without it there is no button for resting.
  final RestService? rests;

  /// Using spell slots; without it the list offers no button for them.
  final SpellSlotService? spellSlots;

  /// Changing exhaustion; without it the list offers no button for it.
  final ExhaustionService? exhaustion;

  @override
  State<CharactersScreen> createState() => _CharactersScreenState();
}

class _CharactersScreenState extends State<CharactersScreen> {
  List<Character>? _list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Changes from the combat may still be on their way to the storage.
    await widget.encounter.flush();
    final list = await widget.characters.all();
    if (mounted) setState(() => _list = list);
  }

  Future<void> _openExhaustion(
    ExhaustionService service,
    Character character,
  ) async {
    await showExhaustion(
      context,
      name: character.name,
      level: character.exhaustion,
      ruleset: service.ruleset,
      onChange: (level) async =>
          (await service.set(character, level)).exhaustion,
    );
    await _load();
  }

  Future<void> _open([Character? character]) async {
    await Navigator.push<Character>(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterEditScreen(
          characters: widget.characters,
          encounter: widget.encounter,
          character: character,
        ),
      ),
    );
    await _load();
  }

  void _toCombat(Character character) {
    setState(() => widget.encounter.addCharacter(character));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${character.name} ist jetzt im Kampf.')),
    );
  }

  Future<void> _rest(RestService rests, List<Character> list) async {
    final messenger = ScaffoldMessenger.of(context);
    if (widget.encounter.isRunning) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Während eines Kampfs ist keine Rast möglich.'),
        ),
      );
      return;
    }
    final choice = await showDialog<RestChoice>(
      context: context,
      builder: (_) => RestDialog(characters: list, rests: rests),
    );
    if (choice == null || !mounted) return;
    switch (choice.kind) {
      case RestKind.long:
        await rests.longRest(choice.characters);
        messenger.showSnackBar(
          const SnackBar(content: Text('Lange Rast beendet.')),
        );
      case RestKind.short:
        await rests.shortRest(choice.characters);
        if (!mounted) return;
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ShortRestScreen(characters: choice.characters, rests: rests),
          ),
        );
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    final rests = widget.rests;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Charaktere'),
        actions: [
          if (rests != null)
            IconButton(
              key: const Key('rest'),
              tooltip: 'Rasten',
              onPressed: list == null || list.isEmpty
                  ? null
                  : () => _rest(rests, list),
              icon: const Icon(Icons.bedtime_outlined),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-character'),
        onPressed: _open,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Charakter'),
      ),
      body: SafeArea(
        child: list == null
            ? const Center(child: CircularProgressIndicator())
            : list.isEmpty
            ? const Center(child: Text('Noch keine Charaktere'))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                children: [
                  for (final (index, character) in list.indexed)
                    _tile(context, index, character),
                ],
              ),
      ),
    );
  }

  Widget _tile(BuildContext context, int index, Character character) {
    final theme = Theme.of(context);
    final inCombat = widget.encounter.hasCharacter(character.id!);
    final details = [
      character.classAndLevel,
      if (character.player.isNotEmpty) character.player,
    ].join(' · ');
    final temp = character.tempHp > 0 ? ' (+${character.tempHp} temporär)' : '';

    return Card(
      child: InkWell(
        key: Key('character-$index'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(character),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          character.name,
                          key: Key('character-name-$index'),
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(details, key: Key('character-details-$index')),
                        Row(
                          children: [
                            Text(
                              'TP ${character.hp}/'
                              '${character.maxHpUnder(widget.encounter.ruleset)}'
                              '$temp · '
                              'RK ${character.armorClass}',
                              key: Key('character-stats-$index'),
                            ),
                            if (character.isDead) ...[
                              const SizedBox(width: 8),
                              Text(
                                'tot',
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          'Trefferwürfel ${character.hitDiceRemaining}/'
                          '${character.hitDiceTotal} (W${character.hitDie})',
                          key: Key('character-hit-dice-$index'),
                          style: theme.textTheme.bodySmall,
                        ),
                        if (character.exhaustion > 0)
                          Text(
                            'Erschöpfung: Stufe ${character.exhaustion}',
                            key: Key('character-exhaustion-$index'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.exhaustion case final service?)
                    IconButton(
                      key: Key('exhaustion-$index'),
                      tooltip: 'Erschöpfung',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _openExhaustion(service, character),
                      icon: const Icon(Icons.battery_alert_outlined),
                    ),
                  if (inCombat)
                    Chip(
                      key: Key('in-combat-$index'),
                      avatar: const Icon(Icons.shield_outlined, size: 16),
                      label: const Text('im Kampf'),
                      visualDensity: VisualDensity.compact,
                    )
                  else
                    TextButton(
                      key: Key('to-combat-$index'),
                      onPressed: () => _toCombat(character),
                      child: const Text('In den Kampf'),
                    ),
                ],
              ),
              if (spellSlotSummary(character) case final summary?)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        summary,
                        key: Key('character-slots-$index'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    if (widget.spellSlots case final service?)
                      IconButton(
                        key: Key('slots-$index'),
                        tooltip: 'Zauberplätze',
                        visualDensity: VisualDensity.compact,
                        onPressed: () async {
                          await showSpellSlots(context, service, character);
                          await _load();
                        },
                        icon: const Icon(Icons.auto_awesome_outlined),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
