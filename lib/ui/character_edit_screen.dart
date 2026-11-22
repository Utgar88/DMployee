import 'package:material_ui/material_ui.dart';

import '../characters/ability.dart';
import '../characters/character.dart';
import '../characters/character_repository.dart';
import '../combat/attack.dart';
import '../combat/encounter.dart';
import 'form_widgets.dart';

/// The character sheet: create a character or change a stored one.
/// Modifiers, proficiency bonus, initiative and saving throws are shown as
/// the values are typed in. Closes with the saved character.
class CharacterEditScreen extends StatefulWidget {
  const CharacterEditScreen({
    super.key,
    required this.characters,
    required this.encounter,
    this.character,
  });

  final CharacterRepository characters;

  /// Changes apply at once to the character's combatant, if any.
  final Encounter encounter;

  /// The character to change; null for a new one.
  final Character? character;

  @override
  State<CharacterEditScreen> createState() => _CharacterEditScreenState();
}

class _CharacterEditScreenState extends State<CharacterEditScreen> {
  late final _original = widget.character;
  late final _name = TextEditingController(text: _original?.name);
  late final _player = TextEditingController(text: _original?.player);
  late final _class = TextEditingController(text: _original?.characterClass);
  late final _level = TextEditingController(text: '${_original?.level ?? 1}');
  late final _scores = {
    for (final ability in Ability.values)
      ability: TextEditingController(
        text: '${_original?.score(ability) ?? 10}',
      ),
  };
  late final _hp = TextEditingController(text: _original?.maxHp.toString());
  late final _armorClass = TextEditingController(
    text: _original?.armorClass.toString(),
  );
  late int _hitDie = _original?.hitDie ?? 8;
  late final _slots = {
    for (var level = 1; level <= 9; level++)
      level: TextEditingController(
        text: _blankIfZero(_original?.slotsTotal(level) ?? 0),
      ),
  };
  late final _pactSlots = TextEditingController(
    text: _blankIfZero(_original?.pactSlots ?? 0),
  );
  late final _pactLevel = TextEditingController(
    text: (_original?.pactSlots ?? 0) > 0 ? '${_original!.pactSlotLevel}' : '',
  );

  static String _blankIfZero(int value) => value == 0 ? '' : '$value';
  late final _saves = {...?_original?.saveProficiencies};
  late final _attacks = [...?_original?.attacks];
  String? _errorText;

  @override
  void initState() {
    super.initState();
    // Derived values follow what is typed.
    for (final controller in [_level, ..._scores.values]) {
      controller.addListener(_refresh);
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    for (final controller in [
      _name,
      _player,
      _class,
      _level,
      ..._scores.values,
      _hp,
      _armorClass,
      ..._slots.values,
      _pactSlots,
      _pactLevel,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// The typed level, 1 while it cannot be read.
  int get _typedLevel => int.tryParse(_level.text) ?? 1;

  /// The modifier of the typed score, 0 while it cannot be read.
  int _modifier(Ability ability) =>
      abilityModifier(int.tryParse(_scores[ability]!.text) ?? 10);

  int _saveBonus(Ability ability) =>
      _modifier(ability) +
      (_saves.contains(ability) ? proficiencyBonusFor(_typedLevel) : 0);

  void _fail(String message) => setState(() => _errorText = message);

  Future<void> _save() async {
    final maxHp = int.tryParse(_hp.text);
    final armorClass = int.tryParse(_armorClass.text);
    if (_name.text.trim().isEmpty ||
        maxHp == null ||
        maxHp < 1 ||
        armorClass == null) {
      return _fail('Name, Trefferpunkte und Rüstungsklasse sind Pflicht.');
    }
    final level = int.tryParse(_level.text);
    if (level == null || level < 1 || level > 20) {
      return _fail('Die Stufe liegt zwischen 1 und 20.');
    }
    final scores = <Ability, int>{};
    for (final MapEntry(key: ability, value: controller) in _scores.entries) {
      final score = int.tryParse(controller.text);
      if (score == null || score < 1 || score > 30) {
        return _fail('Attributwerte liegen zwischen 1 und 30.');
      }
      scores[ability] = score;
    }

    final spellSlots = <int, int>{};
    for (final MapEntry(key: level, value: controller) in _slots.entries) {
      final count = controller.text.isEmpty ? 0 : int.tryParse(controller.text);
      if (count == null || count > 9) {
        return _fail('Zauberplätze liegen zwischen 0 und 9 je Grad.');
      }
      if (count > 0) spellSlots[level] = count;
    }
    final pactSlots = _pactSlots.text.isEmpty
        ? 0
        : int.tryParse(_pactSlots.text);
    if (pactSlots == null || pactSlots > 9) {
      return _fail('Zauberplätze liegen zwischen 0 und 9 je Grad.');
    }
    var pactLevel = 1;
    if (pactSlots > 0) {
      final level = int.tryParse(_pactLevel.text);
      if (level == null || level < 1 || level > 5) {
        return _fail('Paktmagie braucht einen Grad zwischen 1 und 5.');
      }
      pactLevel = level;
    }

    final original = _original;
    final character = original == null
        ? Character(
            name: _name.text,
            player: _player.text,
            characterClass: _class.text,
            level: level,
            abilityScores: scores,
            maxHp: maxHp,
            armorClass: armorClass,
            saveProficiencies: _saves,
            attacks: _attacks,
            hitDie: _hitDie,
            spellSlots: spellSlots,
            pactSlots: pactSlots,
            pactSlotLevel: pactLevel,
          )
        : original.withValues(
            name: _name.text,
            player: _player.text,
            characterClass: _class.text,
            level: level,
            abilityScores: scores,
            maxHp: maxHp,
            armorClass: armorClass,
            saveProficiencies: _saves,
            attacks: _attacks,
            hitDie: _hitDie,
            spellSlots: spellSlots,
            pactSlots: pactSlots,
            pactSlotLevel: pactLevel,
          );
    await widget.characters.save(character);
    widget.encounter.applyCharacter(character);
    if (mounted) Navigator.pop(context, character);
  }

  Future<void> _addAttack() async {
    final name = _name.text.trim();
    final attack = await showDialog<Attack>(
      context: context,
      builder: (context) =>
          AttackDialog(owner: name.isEmpty ? 'den Charakter' : name),
    );
    if (attack != null) setState(() => _attacks.add(attack));
  }

  Future<void> _delete() async {
    final original = _original!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${original.name} löschen?'),
        content: const Text(
          'Der Charakter wird endgültig gelöscht. Ist er im Kampf, bleibt '
          'er dort als einfacher Kämpfer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const Key('confirm-delete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;
    await widget.characters.delete(original.id!);
    widget.encounter.forgetCharacter(original.id!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final proficiency = proficiencyBonusFor(_typedLevel);

    return Scaffold(
      appBar: AppBar(
        title: Text(_original?.name ?? 'Neuer Charakter'),
        actions: [
          if (_original != null)
            IconButton(
              key: const Key('character-delete'),
              tooltip: 'Charakter löschen',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          TextButton(
            key: const Key('character-save'),
            onPressed: _save,
            child: const Text('Speichern'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_errorText != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: formError(context, _errorText!),
              ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    inputField('character-name', 'Name', _name),
                    inputField(
                      'character-player',
                      'Spieler (optional)',
                      _player,
                    ),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: inputField(
                            'character-class',
                            'Klasse (optional)',
                            _class,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: inputField(
                            'character-level',
                            'Stufe',
                            _level,
                            formatters: digitsInput,
                            number: true,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: inputField(
                            'character-hp',
                            'Trefferpunkte (TP)',
                            _hp,
                            formatters: digitsInput,
                            number: true,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: inputField(
                            'character-ac',
                            'Rüstungsklasse (RK)',
                            _armorClass,
                            formatters: digitsInput,
                            number: true,
                          ),
                        ),
                      ],
                    ),
                    _hitDiceRow(context),
                    const SizedBox(height: 8),
                    Text(
                      'Übungsbonus ${formatModifier(proficiency)} · '
                      'Initiative ${formatModifier(_modifier(Ability.dexterity))}',
                      key: const Key('derived'),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    Text('Attribute', style: theme.textTheme.titleMedium),
                    Text(
                      'Haken = geübt im Rettungswurf',
                      style: theme.textTheme.bodySmall,
                    ),
                    for (final ability in Ability.values)
                      _abilityRow(context, ability),
                    const SizedBox(height: 16),
                    _spellSlotsSection(context),
                    const SizedBox(height: 16),
                    Text('Angriffe', style: theme.textTheme.titleMedium),
                    for (final (index, attack) in _attacks.indexed)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(attack.summary),
                        trailing: IconButton(
                          key: Key('character-remove-attack-$index'),
                          tooltip: 'Angriff entfernen',
                          onPressed: () =>
                              setState(() => _attacks.removeAt(index)),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    TextButton.icon(
                      key: const Key('character-add-attack'),
                      onPressed: _addAttack,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Angriff'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Score field, modifier, saving throw proficiency and saving throw bonus
  /// of one ability.
  Widget _spellSlotsSection(BuildContext context) {
    final theme = Theme.of(context);
    Widget slotField(int level) => Expanded(
      child: inputField(
        'slots-$level',
        '$level. Grad',
        _slots[level]!,
        formatters: digitsInput,
        number: true,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Zauberplätze', style: theme.textTheme.titleMedium),
        Text('Anzahl je Grad; leer = keine', style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        for (final row in [
          [1, 2, 3],
          [4, 5, 6],
          [7, 8, 9],
        ])
          Row(
            children: [
              slotField(row[0]),
              const SizedBox(width: 12),
              slotField(row[1]),
              const SizedBox(width: 12),
              slotField(row[2]),
            ],
          ),
        Row(
          children: [
            Expanded(
              child: inputField(
                'pact-slots',
                'Paktmagie: Plätze',
                _pactSlots,
                formatters: digitsInput,
                number: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: inputField(
                'pact-level',
                'Paktmagie: Grad',
                _pactLevel,
                formatters: digitsInput,
                number: true,
              ),
            ),
          ],
        ),
        Text(
          'Paktmagie (Hexenmeister) kommt bei der kurzen Rast zurück.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _hitDiceRow(BuildContext context) {
    final original = _original;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Trefferwürfel', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        SegmentedButton<int>(
          key: const Key('character-hit-die'),
          showSelectedIcon: false,
          segments: [
            for (final sides in Character.hitDieSizes)
              ButtonSegment(value: sides, label: Text('W$sides')),
          ],
          selected: {_hitDie},
          onSelectionChanged: (selection) =>
              setState(() => _hitDie = selection.single),
        ),
        if (original != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Trefferwürfel übrig: ${original.hitDiceRemaining} von '
              '${original.hitDiceTotal}',
              key: const Key('hit-dice-left'),
            ),
          ),
      ],
    );
  }

  Widget _abilityRow(BuildContext context, Ability ability) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          SizedBox(
            width: 128,
            child: Text(ability.label, style: theme.textTheme.bodyLarge),
          ),
          SizedBox(
            width: 56,
            child: TextField(
              key: Key('ability-${ability.name}'),
              controller: _scores[ability],
              keyboardType: TextInputType.number,
              inputFormatters: digitsInput,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(isDense: true),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              formatModifier(_modifier(ability)),
              key: Key('modifier-${ability.name}'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          const Spacer(),
          Checkbox(
            key: Key('save-${ability.name}'),
            value: _saves.contains(ability),
            onChanged: (checked) => setState(
              () => checked ?? false
                  ? _saves.add(ability)
                  : _saves.remove(ability),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              formatModifier(_saveBonus(ability)),
              key: Key('save-bonus-${ability.name}'),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
