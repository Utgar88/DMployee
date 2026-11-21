import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../combat/attack.dart';
import '../combat/buff.dart';
import '../combat/combatant.dart';
import '../combat/condition.dart';
import '../combat/damage.dart';
import '../combat/encounter.dart';
import '../dice/dice_expression.dart';
import '../dice/dice_roller.dart';
import '../log/log_event.dart';
import '../log/log_formatter.dart';

/// Combat screen: set up combatants, roll initiative, step through turns and
/// resolve attacks. All rules live in [Encounter]; this is only the surface.
class CombatScreen extends StatefulWidget {
  const CombatScreen({
    super.key,
    required this.encounter,
    this.formatter = const LogFormatter(),
  });

  final Encounter encounter;
  final LogFormatter formatter;

  @override
  State<CombatScreen> createState() => _CombatScreenState();
}

class _CombatScreenState extends State<CombatScreen> {
  /// Text of the most recent attack, shown above the list.
  String? _lastAction;

  Encounter get _encounter => widget.encounter;

  Future<void> _addCombatant() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (context) => _CombatantDialog(encounter: _encounter),
    );
    if (added ?? false) setState(() {});
  }

  Future<void> _editCombatant(Combatant combatant) async {
    final edited = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _CombatantDialog(encounter: _encounter, combatant: combatant),
    );
    if (edited ?? false) setState(() {});
  }

  Future<void> _addAttack(Combatant combatant) async {
    final attack = await showDialog<Attack>(
      context: context,
      builder: (context) => _AttackDialog(combatant: combatant),
    );
    if (attack != null) {
      setState(() => _encounter.addAttack(combatant, attack));
    }
  }

  Future<void> _rollInitiative() async {
    final manual = await showDialog<Map<Combatant, int>>(
      context: context,
      builder: (context) => _InitiativeDialog(encounter: _encounter),
    );
    if (manual == null) return;
    await _encounter.rollInitiative(manual: manual);
    if (mounted) setState(() {});
  }

  Future<void> _nextTurn() async {
    await _encounter.nextTurn();
    if (mounted) setState(() {});
  }

  Future<void> _attack(Combatant attacker, Attack attack) async {
    final result = await showDialog<_AttackResult>(
      context: context,
      builder: (context) => _TargetDialog(
        encounter: _encounter,
        attacker: attacker,
        attack: attack,
      ),
    );
    if (result == null || !mounted) return;

    final line = widget.formatter.format(result.outcome.event);
    setState(() => _lastAction = line.text);
  }

  Future<void> _changeHp(Combatant combatant) async {
    final event = await showDialog<LogEvent>(
      context: context,
      builder: (context) =>
          _HpDialog(encounter: _encounter, combatant: combatant),
    );
    if (event == null || !mounted) return;
    setState(() => _lastAction = widget.formatter.format(event).text);
  }

  Future<void> _editTraits(Combatant combatant) async {
    await showDialog<void>(
      context: context,
      builder: (context) =>
          _TraitsDialog(encounter: _encounter, combatant: combatant),
    );
    if (mounted) setState(() {});
  }

  /// `13`, or `15 (13 +2)` while effects change the armor class.
  static String _armorClassText(Combatant combatant) {
    final bonus = combatant.effectiveArmorClass - combatant.armorClass;
    if (bonus == 0) return '${combatant.armorClass}';
    return '${combatant.effectiveArmorClass} '
        '(${combatant.armorClass} ${bonus > 0 ? '+' : ''}$bonus)';
  }

  /// `Resistenz: Feuer, Kälte · Immunität: Gift`, or null without entries.
  static String? _traitsText(Combatant combatant) {
    final groups = [
      for (final effect in DamageEffect.values)
        if (combatant.damageTraits.entries
                .where((entry) => entry.value == effect)
                .map((entry) => entry.key)
                .toList()
            case final types when types.isNotEmpty)
          '${effect.label}: ${types.join(', ')}',
    ];
    return groups.isEmpty ? null : groups.join(' · ');
  }

  Future<void> _addCondition(Combatant combatant) async {
    await showDialog<void>(
      context: context,
      builder: (context) =>
          _ConditionDialog(encounter: _encounter, combatant: combatant),
    );
    if (mounted) setState(() {});
  }

  Future<void> _removeCondition(
    Combatant combatant,
    Condition condition,
  ) async {
    await _encounter.removeCondition(combatant, condition);
    if (mounted) setState(() {});
  }

  Future<void> _addBuff(Combatant combatant) async {
    await showDialog<void>(
      context: context,
      builder: (context) =>
          _BuffDialog(encounter: _encounter, combatant: combatant),
    );
    if (mounted) setState(() {});
  }

  Future<void> _removeBuff(Combatant combatant, Buff buff) async {
    await _encounter.removeBuff(combatant, buff);
    if (mounted) setState(() {});
  }

  Future<void> _revive(Combatant combatant) async {
    final event = await showDialog<LogEvent>(
      context: context,
      builder: (context) =>
          _ReviveDialog(encounter: _encounter, combatant: combatant),
    );
    if (event == null || !mounted) return;
    setState(() => _lastAction = widget.formatter.format(event).text);
  }

  Future<void> _deathSave(Combatant combatant) async {
    final event = await showDialog<DeathSaveEvent>(
      context: context,
      builder: (context) =>
          _DeathSaveDialog(encounter: _encounter, combatant: combatant),
    );
    if (event == null || !mounted) return;
    setState(() => _lastAction = widget.formatter.format(event).text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final combatants = _encounter.combatants;
    final running = _encounter.isRunning;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kampf'),
        actions: [
          IconButton(
            key: const Key('add-combatant'),
            tooltip: 'Kämpfer hinzufügen',
            onPressed: _addCombatant,
            icon: const Icon(Icons.person_add_alt),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (combatants.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: Text('Noch keine Kämpfer')),
              ),
            if (running)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Runde ${_encounter.round}',
                      key: const Key('round'),
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  TextButton(
                    key: const Key('end-combat'),
                    onPressed: () => setState(_encounter.end),
                    child: const Text('Kampf beenden'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('next-turn'),
                    onPressed: _nextTurn,
                    child: const Text('Nächster Zug'),
                  ),
                ],
              )
            else if (combatants.isNotEmpty)
              FilledButton(
                key: const Key('roll-initiative'),
                onPressed: _rollInitiative,
                child: const Text('Initiative würfeln'),
              ),
            if (_lastAction != null)
              Card(
                margin: const EdgeInsets.only(top: 12),
                color: theme.colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_lastAction!, key: const Key('last-action')),
                ),
              ),
            const SizedBox(height: 12),
            for (final (index, combatant) in combatants.indexed)
              _buildCombatant(context, index, combatant),
          ],
        ),
      ),
    );
  }

  Widget _buildCombatant(BuildContext context, int index, Combatant combatant) {
    final theme = Theme.of(context);
    final isCurrent = _encounter.current == combatant;
    final running = _encounter.isRunning;

    return Card(
      key: Key('combatant-$index'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isCurrent
            ? BorderSide(color: theme.colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    combatant.name,
                    key: Key('name-$index'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      decoration: combatant.isDown
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
                if (isCurrent) const _Badge('am Zug'),
                if (combatant.isDead)
                  const _Badge('tot')
                else if (combatant.isDown)
                  const _Badge('am Boden'),
                if (combatant.isStable) const _Badge('stabil'),
                IconButton(
                  key: Key('edit-$index'),
                  tooltip: 'Kämpfer bearbeiten',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _editCombatant(combatant),
                  icon: const Icon(Icons.edit_outlined),
                ),
                if (!running)
                  IconButton(
                    key: Key('remove-$index'),
                    tooltip: 'Kämpfer entfernen',
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        setState(() => _encounter.remove(combatant)),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'RK ${_armorClassText(combatant)} · '
                    '${_hpText(combatant)}',
                    key: Key('stats-$index'),
                  ),
                ),
                TextButton.icon(
                  key: Key('hp-$index'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _changeHp(combatant),
                  icon: const Icon(Icons.favorite_border, size: 18),
                  label: const Text('TP ändern'),
                ),
              ],
            ),
            if (_traitsText(combatant) case final traits?)
              Text(
                traits,
                key: Key('traits-text-$index'),
                style: theme.textTheme.bodySmall,
              ),
            if (combatant.isDying)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Todesrettungswürfe: '
                      'Erfolge ${combatant.deathSaveSuccesses} · '
                      'Fehlschläge ${combatant.deathSaveFailures}',
                      key: Key('death-saves-$index'),
                    ),
                  ),
                  FilledButton.tonal(
                    key: Key('death-save-$index'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _deathSave(combatant),
                    child: const Text('Todesrettungswurf'),
                  ),
                ],
              ),
            if (combatant.isDead)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  key: Key('revive-$index'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _revive(combatant),
                  child: const Text('Wiederbeleben'),
                ),
              ),
            if (combatant.initiative != null)
              Text(
                'Initiative ${combatant.initiative}',
                key: Key('initiative-$index'),
                style: theme.textTheme.bodySmall,
              ),
            if (combatant.conditions.isNotEmpty || combatant.buffs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final (buffIndex, buff) in combatant.buffs.indexed)
                      InputChip(
                        key: Key('buff-$index-$buffIndex'),
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.auto_awesome, size: 16),
                        label: Text(buff.summary),
                        deleteButtonTooltipMessage: 'Effekt entfernen',
                        deleteIcon: Icon(
                          Icons.close,
                          key: Key('remove-buff-$index-$buffIndex'),
                          size: 18,
                        ),
                        onDeleted: () => _removeBuff(combatant, buff),
                      ),
                    for (final active in combatant.conditions)
                      InputChip(
                        key: Key('condition-$index-${active.condition.name}'),
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          active.roundsLeft == null
                              ? active.condition.label
                              : '${active.condition.label} '
                                    '(${active.roundsLeft})',
                        ),
                        deleteButtonTooltipMessage: 'Zustand entfernen',
                        deleteIcon: Icon(
                          Icons.close,
                          key: Key(
                            'remove-condition-$index-${active.condition.name}',
                          ),
                          size: 18,
                        ),
                        onDeleted: () =>
                            _removeCondition(combatant, active.condition),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final (attackIndex, attack) in combatant.attacks.indexed)
                  ActionChip(
                    key: Key('attack-$index-$attackIndex'),
                    avatar: const Icon(Icons.gavel, size: 18),
                    label: Text(attack.summary),
                    onPressed: () => _attack(combatant, attack),
                  ),
                TextButton.icon(
                  key: Key('add-attack-$index'),
                  onPressed: () => _addAttack(combatant),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Angriff'),
                ),
                TextButton.icon(
                  key: Key('add-condition-$index'),
                  onPressed: () => _addCondition(combatant),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Zustand'),
                ),
                TextButton.icon(
                  key: Key('add-buff-$index'),
                  onPressed: () => _addBuff(combatant),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Effekt'),
                ),
                TextButton.icon(
                  key: Key('traits-$index'),
                  onPressed: () => _editTraits(combatant),
                  icon: const Icon(Icons.shield_outlined, size: 18),
                  label: const Text('Resistenzen'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(color: scheme.onPrimaryContainer)),
    );
  }
}

final _digits = [FilteringTextInputFormatter.digitsOnly];
final _signedDigits = [FilteringTextInputFormatter.allow(RegExp(r'[-+0-9]'))];

Widget _field(
  String key,
  String label,
  TextEditingController controller, {
  List<TextInputFormatter>? formatters,
  bool number = false,
  String? helper,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      key: Key(key),
      controller: controller,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      inputFormatters: formatters,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        isDense: true,
      ),
    ),
  );
}

/// Text field for a damage type that suggests the damage types of the
/// rules while it has focus. Any other text is allowed as well.
class _DamageTypeField extends StatefulWidget {
  const _DamageTypeField({
    required this.fieldKey,
    required this.label,
    required this.controller,
    this.helper,
  });

  /// Key of the text field; suggestions get `<fieldKey>-option-<type>`.
  final String fieldKey;
  final String label;
  final TextEditingController controller;
  final String? helper;

  @override
  State<_DamageTypeField> createState() => _DamageTypeFieldState();
}

class _DamageTypeFieldState extends State<_DamageTypeField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Damage types containing the typed text; none once it is complete.
  Iterable<String> _options(TextEditingValue value) {
    final typed = normalizeDamageType(value.text);
    if (damageTypes.any((type) => normalizeDamageType(type) == typed)) {
      return const [];
    }
    return damageTypes.where((type) => type.toLowerCase().contains(typed));
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: _options,
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              key: Key(widget.fieldKey),
              controller: controller,
              focusNode: focusNode,
              onSubmitted: (_) => onSubmitted(),
              decoration: InputDecoration(
                labelText: widget.label,
                helperText: widget.helper,
                isDense: true,
              ),
            ),
          ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 240),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final option in options)
                  ListTile(
                    key: Key('${widget.fieldKey}-option-$option'),
                    dense: true,
                    title: Text(option),
                    onTap: () => onSelected(option),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _error(BuildContext context, String message) => Padding(
  padding: const EdgeInsets.only(top: 8),
  child: Text(
    message,
    key: const Key('form-error'),
    style: TextStyle(color: Theme.of(context).colorScheme.error),
  ),
);

/// Input fields for one attack. Used when creating a combatant and when
/// adding a further attack.
class _AttackFields {
  final name = TextEditingController();
  final bonus = TextEditingController();
  final damage = TextEditingController();
  final type = TextEditingController();

  bool get isEmpty => name.text.trim().isEmpty && damage.text.trim().isEmpty;

  /// The entered attack, or an error message if the input is invalid.
  (Attack?, String?) read() {
    if (name.text.trim().isEmpty) {
      return (null, 'Der Angriff braucht einen Namen.');
    }
    final DiceExpression expression;
    try {
      expression = DiceExpression.parse(damage.text);
    } on FormatException {
      return (null, 'Schaden bitte als Würfelausdruck angeben, z. B. 1d8+3.');
    }
    return (
      Attack(
        name: name.text.trim(),
        attackBonus: int.tryParse(bonus.text) ?? 0,
        damage: expression,
        damageType: type.text.trim().isEmpty ? 'Schaden' : type.text.trim(),
      ),
      null,
    );
  }

  List<Widget> build() => [
    _field('attack-name', 'Angriff (z. B. Langschwert)', name),
    _field(
      'attack-bonus',
      'Angriffsbonus',
      bonus,
      formatters: _signedDigits,
      number: true,
    ),
    _field('attack-damage', 'Schaden (z. B. 1d8+3)', damage),
    _DamageTypeField(
      fieldKey: 'attack-type',
      label: 'Schadensart (z. B. Hieb)',
      controller: type,
    ),
  ];

  void dispose() {
    name.dispose();
    bonus.dispose();
    damage.dispose();
    type.dispose();
  }
}

/// Adds a combatant, or with [combatant] edits an existing one.
class _CombatantDialog extends StatefulWidget {
  const _CombatantDialog({required this.encounter, this.combatant});

  final Encounter encounter;

  /// The combatant to edit; null to add a new one.
  final Combatant? combatant;

  @override
  State<_CombatantDialog> createState() => _CombatantDialogState();
}

class _CombatantDialogState extends State<_CombatantDialog> {
  late final _editing = widget.combatant;
  late final _name = TextEditingController(text: _editing?.name);
  late final _armorClass = TextEditingController(
    text: _editing?.armorClass.toString(),
  );
  late final _hp = TextEditingController(text: _editing?.maxHp.toString());
  late final _initiative = TextEditingController(
    text: _editing?.initiativeBonus.toString(),
  );
  final _attack = _AttackFields();
  late bool _isPlayer = _editing?.isPlayer ?? false;

  /// Stored attacks marked for removal; removed when saving.
  final _removedAttacks = <Attack>{};
  String? _errorText;

  @override
  void dispose() {
    _name.dispose();
    _armorClass.dispose();
    _hp.dispose();
    _initiative.dispose();
    _attack.dispose();
    super.dispose();
  }

  void _save() {
    final armorClass = int.tryParse(_armorClass.text);
    final hp = int.tryParse(_hp.text);
    if (_name.text.trim().isEmpty ||
        armorClass == null ||
        hp == null ||
        hp < 1) {
      setState(
        () =>
            _errorText = 'Name, Rüstungsklasse und Trefferpunkte sind Pflicht.',
      );
      return;
    }

    if (_editing case final combatant?) {
      widget.encounter.edit(
        combatant,
        name: _name.text,
        armorClass: armorClass,
        maxHp: hp,
        initiativeBonus: int.tryParse(_initiative.text) ?? 0,
        isPlayer: _isPlayer,
      );
      for (final attack in _removedAttacks) {
        widget.encounter.removeAttack(combatant, attack);
      }
      Navigator.pop(context, true);
      return;
    }

    Attack? attack;
    if (!_attack.isEmpty) {
      final (parsed, message) = _attack.read();
      if (parsed == null) {
        setState(() => _errorText = message);
        return;
      }
      attack = parsed;
    }

    widget.encounter.add(
      name: _name.text.trim(),
      armorClass: armorClass,
      maxHp: hp,
      initiativeBonus: int.tryParse(_initiative.text) ?? 0,
      isPlayer: _isPlayer,
      attacks: [?attack],
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _editing == null ? 'Kämpfer hinzufügen' : 'Kämpfer bearbeiten',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field('combatant-name', 'Name', _name),
            _field(
              'combatant-ac',
              'Rüstungsklasse (RK)',
              _armorClass,
              formatters: _digits,
              number: true,
            ),
            _field(
              'combatant-hp',
              'Trefferpunkte (TP)',
              _hp,
              formatters: _digits,
              number: true,
            ),
            _field(
              'combatant-init',
              'Initiative-Bonus',
              _initiative,
              formatters: _signedDigits,
              number: true,
            ),
            SwitchListTile(
              key: const Key('combatant-player'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Spielercharakter'),
              subtitle: const Text('Macht bei 0 TP Todesrettungswürfe'),
              value: _isPlayer,
              onChanged: (value) => setState(() => _isPlayer = value),
            ),
            const SizedBox(height: 8),
            if (_editing case final combatant?) ...[
              if (combatant.attacks.isNotEmpty)
                Text('Angriffe', style: Theme.of(context).textTheme.titleSmall),
              for (final (index, attack) in combatant.attacks.indexed)
                if (!_removedAttacks.contains(attack))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(attack.summary),
                    trailing: IconButton(
                      key: Key('edit-remove-attack-$index'),
                      tooltip: 'Angriff entfernen',
                      onPressed: () =>
                          setState(() => _removedAttacks.add(attack)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
            ] else ...[
              Text(
                'Angriff (optional)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              ..._attack.build(),
            ],
            if (_errorText != null) _error(context, _errorText!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const Key('combatant-save'),
          onPressed: _save,
          child: Text(_editing == null ? 'Hinzufügen' : 'Speichern'),
        ),
      ],
    );
  }
}

class _AttackDialog extends StatefulWidget {
  const _AttackDialog({required this.combatant});

  final Combatant combatant;

  @override
  State<_AttackDialog> createState() => _AttackDialogState();
}

class _AttackDialogState extends State<_AttackDialog> {
  final _attack = _AttackFields();
  String? _errorText;

  @override
  void dispose() {
    _attack.dispose();
    super.dispose();
  }

  void _save() {
    final (attack, message) = _attack.read();
    if (attack == null) {
      setState(() => _errorText = message);
      return;
    }
    Navigator.pop(context, attack);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Angriff für ${widget.combatant.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ..._attack.build(),
            if (_errorText != null) _error(context, _errorText!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const Key('attack-save'),
          onPressed: _save,
          child: const Text('Hinterlegen'),
        ),
      ],
    );
  }
}

class _InitiativeDialog extends StatefulWidget {
  const _InitiativeDialog({required this.encounter});

  final Encounter encounter;

  @override
  State<_InitiativeDialog> createState() => _InitiativeDialogState();
}

class _InitiativeDialogState extends State<_InitiativeDialog> {
  late final _controllers = {
    for (final combatant in widget.encounter.combatants)
      combatant: TextEditingController(),
  };
  String? _errorText;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _confirm() {
    final manual = <Combatant, int>{};
    for (final MapEntry(key: combatant, value: controller)
        in _controllers.entries) {
      if (controller.text.isEmpty) continue;
      final face = int.tryParse(controller.text);
      if (face == null || face < 1 || face > 20) {
        setState(
          () => _errorText = 'Ein d20 zeigt 1 bis 20 (${combatant.name}).',
        );
        return;
      }
      manual[combatant] = face;
    }
    Navigator.pop(context, manual);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Initiative würfeln'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Leere Felder würfelt die App. Am Tisch gewürfelte d20 hier '
              'eintragen, der Bonus kommt automatisch dazu.',
            ),
            const SizedBox(height: 8),
            for (final (index, combatant)
                in widget.encounter.combatants.indexed)
              _field(
                'manual-init-$index',
                '${combatant.name} (d20)',
                _controllers[combatant]!,
                formatters: _digits,
                number: true,
              ),
            if (_errorText != null) _error(context, _errorText!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const Key('initiative-confirm'),
          onPressed: _confirm,
          child: const Text('Würfeln'),
        ),
      ],
    );
  }
}

String _modeWord(RollMode mode) => switch (mode) {
  RollMode.advantage => 'Vorteil',
  RollMode.disadvantage => 'Nachteil',
  RollMode.normal => 'normal',
};

/// What [condition] means for attacks made by its bearer.
String _attackerNote(Condition condition) {
  final effect = condition.attackerEffect;
  if (effect != null) return _modeWord(effect);
  return condition.attackerHint ?? 'keine Wirkung auf den Angriff';
}

/// What [condition] means for attacks against its bearer.
String _targetNote(Condition condition) {
  final effect = condition.targetEffect;
  final hint = condition.targetHint;
  if (effect != null) {
    final word = '${_modeWord(effect)} für den Angreifer';
    return hint == null ? word : '$word; $hint';
  }
  return hint ?? 'keine Wirkung auf den Angriff';
}

class _AttackResult {
  const _AttackResult(this.target, this.outcome);

  final Combatant target;
  final AttackOutcome outcome;
}

/// Second step of an attack: optional settings, then a tap on the target
/// resolves the attack.
class _TargetDialog extends StatefulWidget {
  const _TargetDialog({
    required this.encounter,
    required this.attacker,
    required this.attack,
  });

  final Encounter encounter;
  final Combatant attacker;
  final Attack attack;

  @override
  State<_TargetDialog> createState() => _TargetDialogState();
}

class _TargetDialogState extends State<_TargetDialog> {
  final _manualAttack = TextEditingController();
  final _manualDamage = TextEditingController();

  /// The attacker's effects with bonus dice on the attack roll, each with a
  /// field for the dice rolled at the table.
  late final _buffDice = {
    for (final buff in widget.attacker.buffs)
      if (buff.attackBonus?.isDice ?? false) buff: TextEditingController(),
  };

  /// The same for bonus dice on the damage.
  late final _buffDamageDice = {
    for (final buff in widget.attacker.buffs)
      if (buff.damageBonus?.isDice ?? false) buff: TextEditingController(),
  };

  /// The attacker's effects that change this attack and can be deselected.
  late final _attackBuffs = [
    for (final buff in widget.attacker.buffs)
      if (buff.attackBonus != null || buff.damageBonus != null) buff,
  ];

  /// Effects the game master deselected for this attack.
  final _ignoredBuffs = <Buff>{};
  RollMode _mode = RollMode.normal;
  bool _applyConditions = true;
  String? _errorText;

  @override
  void dispose() {
    _manualAttack.dispose();
    _manualDamage.dispose();
    for (final controller in [..._buffDice.values, ..._buffDamageDice.values]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _attackTarget(Combatant target) async {
    try {
      final outcome = await widget.encounter.attack(
        attacker: widget.attacker,
        target: target,
        attack: widget.attack,
        mode: _mode,
        manualAttackRoll: int.tryParse(_manualAttack.text),
        manualDamage: int.tryParse(_manualDamage.text),
        manualBuffRolls: {
          for (final MapEntry(key: buff, value: controller)
              in _buffDice.entries)
            buff: ?int.tryParse(controller.text),
        },
        manualBuffDamage: {
          for (final MapEntry(key: buff, value: controller)
              in _buffDamageDice.entries)
            buff: ?int.tryParse(controller.text),
        },
        ignoredBuffs: _ignoredBuffs,
        applyConditions: _applyConditions,
      );
      if (mounted) Navigator.pop(context, _AttackResult(target, outcome));
    } on ArgumentError {
      setState(
        () => _errorText =
            'Ein eingetragener Wert ist mit diesen Würfeln nicht möglich.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final combatants = widget.encounter.combatants;
    final attacker = widget.attacker;
    final anyConditions = combatants.any((c) => c.conditions.isNotEmpty);

    return AlertDialog(
      title: Text('${widget.attacker.name}: ${widget.attack.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<RollMode>(
              segments: const [
                ButtonSegment(
                  value: RollMode.normal,
                  label: Text('Normal', key: Key('attack-mode-normal')),
                ),
                ButtonSegment(
                  value: RollMode.advantage,
                  label: Text('Vorteil', key: Key('attack-mode-advantage')),
                ),
                ButtonSegment(
                  value: RollMode.disadvantage,
                  label: Text('Nachteil', key: Key('attack-mode-disadvantage')),
                ),
              ],
              showSelectedIcon: false,
              selected: {_mode},
              onSelectionChanged: (selection) =>
                  setState(() => _mode = selection.first),
            ),
            if (anyConditions)
              SwitchListTile(
                key: const Key('attack-conditions'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Zustände berücksichtigen'),
                subtitle: const Text(
                  'Vorteil und Nachteil aus Zuständen kommen von selbst dazu',
                ),
                value: _applyConditions,
                onChanged: (value) => setState(() => _applyConditions = value),
              ),
            for (final active in attacker.conditions)
              Text(
                '${attacker.name} ist '
                '${active.condition.label.toLowerCase()}: '
                '${_attackerNote(active.condition)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (_attackBuffs.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Effekte bei diesem Angriff',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final (index, buff) in _attackBuffs.indexed)
                CheckboxListTile(
                  key: Key('attack-buff-$index'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(buff.summary),
                  value: !_ignoredBuffs.contains(buff),
                  onChanged: (applies) => setState(
                    () => applies ?? false
                        ? _ignoredBuffs.remove(buff)
                        : _ignoredBuffs.add(buff),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Text(
              'Am Tisch gewürfelt? (optional)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            _field(
              'manual-attack',
              'Angriffswurf (d20)',
              _manualAttack,
              helper: 'Gewürfelte Zahl ohne Angriffsbonus',
              formatters: _digits,
              number: true,
            ),
            for (final (index, MapEntry(key: buff, value: controller))
                in _buffDice.entries.indexed)
              if (!_ignoredBuffs.contains(buff))
                _field(
                  'manual-buff-$index',
                  '${buff.name} (Angriff ${buff.attackBonus!.dice})',
                  controller,
                  helper: 'Augensumme des Bonuswürfels',
                  formatters: _digits,
                  number: true,
                ),
            _field(
              'manual-damage',
              'Schadenswürfel (Summe)',
              _manualDamage,
              helper: 'Augensumme ohne Schadensbonus',
              formatters: _digits,
              number: true,
            ),
            for (final (index, MapEntry(key: buff, value: controller))
                in _buffDamageDice.entries.indexed)
              if (!_ignoredBuffs.contains(buff))
                _field(
                  'manual-buff-damage-$index',
                  '${buff.name} (Schaden ${buff.damageBonus!.dice})',
                  controller,
                  helper:
                      'Augensumme; bei kritischem Treffer doppelt so viele '
                      'Würfel',
                  formatters: _digits,
                  number: true,
                ),
            if (_errorText != null) _error(context, _errorText!),
            const SizedBox(height: 8),
            Text('Ziel wählen', style: Theme.of(context).textTheme.titleSmall),
            for (final (index, combatant) in combatants.indexed)
              if (combatant != widget.attacker)
                ListTile(
                  key: Key('target-$index'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(combatant.name),
                  subtitle: Text(
                    [
                      'RK ${combatant.effectiveArmorClass} · '
                          'TP ${combatant.hp}/${combatant.maxHp}',
                      for (final active in combatant.conditions)
                        '${active.condition.label}: '
                            '${_targetNote(active.condition)}',
                    ].join('\n'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _attackTarget(combatant),
                ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
      ],
    );
  }
}

/// `TP 18/20`, with temporary hit points `TP 18/20 (+8 temporär)`.
String _hpText(Combatant combatant) =>
    'TP ${combatant.hp}/${combatant.maxHp}'
    '${combatant.tempHp > 0 ? ' (+${combatant.tempHp} temporär)' : ''}';

/// Damage, healing or temporary hit points for one combatant without an
/// attack.
class _HpDialog extends StatefulWidget {
  const _HpDialog({required this.encounter, required this.combatant});

  final Encounter encounter;
  final Combatant combatant;

  @override
  State<_HpDialog> createState() => _HpDialogState();
}

class _HpDialogState extends State<_HpDialog> {
  final _amount = TextEditingController();
  final _source = TextEditingController();
  final _damageType = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _amount.dispose();
    _source.dispose();
    _damageType.dispose();
    super.dispose();
  }

  Future<void> _grantTempHp() async {
    final amount = int.tryParse(_amount.text);
    if (amount == null || amount < 1) {
      setState(() => _errorText = 'Bitte einen Betrag ab 1 eintragen.');
      return;
    }
    final event = await widget.encounter.grantTempHp(
      widget.combatant,
      amount,
      source: _source.text,
    );
    if (mounted) Navigator.pop(context, event);
  }

  Future<void> _removeTempHp() async {
    final event = await widget.encounter.removeTempHp(widget.combatant);
    if (mounted) Navigator.pop(context, event);
  }

  Future<void> _apply({required bool healing}) async {
    final amount = int.tryParse(_amount.text);
    if (amount == null || amount < 1) {
      setState(() => _errorText = 'Bitte einen Betrag ab 1 eintragen.');
      return;
    }
    if (healing && widget.combatant.isDead) {
      setState(
        () => _errorText =
            'Ein toter Charakter lässt sich nicht heilen, nur wiederbeleben.',
      );
      return;
    }
    final encounter = widget.encounter;
    final event = healing
        ? await encounter.heal(widget.combatant, amount, source: _source.text)
        : await encounter.damage(
            widget.combatant,
            amount,
            source: _source.text,
            damageType: _damageType.text,
          );
    if (mounted) Navigator.pop(context, event);
  }

  @override
  Widget build(BuildContext context) {
    final combatant = widget.combatant;

    return AlertDialog(
      title: Text('${combatant.name}: ${_hpText(combatant)}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(
              'hp-amount',
              'Betrag',
              _amount,
              formatters: _digits,
              number: true,
            ),
            _field(
              'hp-source',
              'Quelle (optional)',
              _source,
              helper: 'z. B. Feuerball, Heiltrank, Falle',
            ),
            _DamageTypeField(
              fieldKey: 'hp-damage-type',
              label: 'Schadensart (optional)',
              controller: _damageType,
              helper: 'z. B. Feuer; nur dann wirken Resistenzen',
            ),
            if (_errorText != null) _error(context, _errorText!),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    key: const Key('hp-damage'),
                    onPressed: () => _apply(healing: false),
                    child: const Text('Schaden'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    key: const Key('hp-heal'),
                    onPressed: () => _apply(healing: true),
                    child: const Text('Heilung'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('hp-temp'),
                onPressed: _grantTempHp,
                child: const Text('Temporäre TP'),
              ),
            ),
            Text(
              'Temporäre TP addieren sich nicht; der höhere Wert zählt.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (combatant.tempHp > 0)
              TextButton(
                key: const Key('hp-temp-remove'),
                onPressed: _removeTempHp,
                child: Text('${combatant.tempHp} temporäre TP entfernen'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
      ],
    );
  }
}

/// Death saving throw: rolled by the app or typed in from the table.
class _DeathSaveDialog extends StatefulWidget {
  const _DeathSaveDialog({required this.encounter, required this.combatant});

  final Encounter encounter;
  final Combatant combatant;

  @override
  State<_DeathSaveDialog> createState() => _DeathSaveDialogState();
}

class _DeathSaveDialogState extends State<_DeathSaveDialog> {
  final _manual = TextEditingController();

  /// Effects with bonus dice on saving throws, each with a field for the
  /// dice rolled at the table.
  late final _buffDice = {
    for (final buff in widget.combatant.buffs)
      if (buff.saveBonus?.isDice ?? false) buff: TextEditingController(),
  };
  String? _errorText;

  @override
  void dispose() {
    _manual.dispose();
    for (final controller in _buffDice.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _roll() async {
    try {
      final event = await widget.encounter.rollDeathSave(
        widget.combatant,
        manualRoll: int.tryParse(_manual.text),
        manualBuffRolls: {
          for (final MapEntry(key: buff, value: controller)
              in _buffDice.entries)
            buff: ?int.tryParse(controller.text),
        },
      );
      if (mounted) Navigator.pop(context, event);
    } on ArgumentError {
      setState(
        () => _errorText =
            'Ein eingetragener Wert ist mit diesen Würfeln nicht möglich.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final combatant = widget.combatant;

    return AlertDialog(
      title: Text('Todesrettungswurf: ${combatant.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Erfolge ${combatant.deathSaveSuccesses} · '
              'Fehlschläge ${combatant.deathSaveFailures}',
            ),
            const SizedBox(height: 8),
            _field(
              'manual-death-save',
              'Am Tisch gewürfelt? (d20, optional)',
              _manual,
              helper: 'Leer lassen, dann würfelt die App',
              formatters: _digits,
              number: true,
            ),
            for (final (index, MapEntry(key: buff, value: controller))
                in _buffDice.entries.indexed)
              _field(
                'manual-death-save-buff-$index',
                '${buff.name} (${buff.saveBonus!.dice})',
                controller,
                helper: 'Augensumme des Bonuswürfels, optional',
                formatters: _digits,
                number: true,
              ),
            for (final buff in widget.combatant.buffs)
              if (buff.saveBonus case final bonus? when !bonus.isDice)
                Text(
                  '${buff.name}: $bonus auf den Wurf',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            if (_errorText != null) _error(context, _errorText!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const Key('death-save-confirm'),
          onPressed: _roll,
          child: const Text('Würfeln'),
        ),
      ],
    );
  }
}

/// Brings a dead character back with a number of hit points.
class _ReviveDialog extends StatefulWidget {
  const _ReviveDialog({required this.encounter, required this.combatant});

  final Encounter encounter;
  final Combatant combatant;

  @override
  State<_ReviveDialog> createState() => _ReviveDialogState();
}

class _ReviveDialogState extends State<_ReviveDialog> {
  final _hp = TextEditingController(text: '1');
  final _source = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _hp.dispose();
    _source.dispose();
    super.dispose();
  }

  Future<void> _revive() async {
    final maxHp = widget.combatant.maxHp;
    final hp = int.tryParse(_hp.text);
    if (hp == null || hp < 1 || hp > maxHp) {
      setState(() => _errorText = 'Bitte 1 bis $maxHp TP eintragen.');
      return;
    }
    final event = await widget.encounter.revive(
      widget.combatant,
      hp: hp,
      source: _source.text,
    );
    if (mounted) Navigator.pop(context, event);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.combatant.name} wiederbeleben'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(
              'revive-hp',
              'Trefferpunkte danach',
              _hp,
              helper: 'Wiederbeleben, Tote erwecken: 1; Auferstehung: alle',
              formatters: _digits,
              number: true,
            ),
            _field(
              'revive-source',
              'Quelle (optional)',
              _source,
              helper: 'z. B. Wiederbeleben',
            ),
            if (_errorText != null) _error(context, _errorText!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const Key('revive-confirm'),
          onPressed: _revive,
          child: const Text('Wiederbeleben'),
        ),
      ],
    );
  }
}

/// Resistance, vulnerability and immunity of one combatant. Tapping a
/// damage type steps through the four states; changes apply immediately.
class _TraitsDialog extends StatefulWidget {
  const _TraitsDialog({required this.encounter, required this.combatant});

  final Encounter encounter;
  final Combatant combatant;

  @override
  State<_TraitsDialog> createState() => _TraitsDialogState();
}

class _TraitsDialogState extends State<_TraitsDialog> {
  void _step(String type) {
    final current = widget.combatant.damageEffectFor(type);
    final next = switch (current) {
      null => DamageEffect.resistance,
      DamageEffect.resistance => DamageEffect.vulnerability,
      DamageEffect.vulnerability => DamageEffect.immunity,
      DamageEffect.immunity => null,
    };
    setState(
      () => widget.encounter.setDamageTrait(widget.combatant, type, next),
    );
  }

  @override
  Widget build(BuildContext context) {
    final combatant = widget.combatant;
    // Standard types first, then anything else already set.
    final types = [
      ...damageTypes,
      for (final type in combatant.damageTraits.keys)
        if (!damageTypes.contains(type)) type,
    ];

    return AlertDialog(
      title: Text('Resistenzen: ${combatant.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Antippen wechselt: normal → Resistenz (halber Schaden) → '
              'Anfälligkeit (doppelter Schaden) → Immunität (kein Schaden).',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final type in types)
                  FilterChip(
                    key: Key('trait-$type'),
                    showCheckmark: false,
                    selected: combatant.damageEffectFor(type) != null,
                    label: Text(switch (combatant.damageEffectFor(type)) {
                      null => type,
                      final effect => '$type: ${effect.label}',
                    }),
                    onSelected: (_) => _step(type),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          key: const Key('traits-done'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Fertig'),
        ),
      ],
    );
  }
}

/// Gives a combatant a condition: optional duration, then one tap on the
/// condition.
class _ConditionDialog extends StatefulWidget {
  const _ConditionDialog({required this.encounter, required this.combatant});

  final Encounter encounter;
  final Combatant combatant;

  @override
  State<_ConditionDialog> createState() => _ConditionDialogState();
}

class _ConditionDialogState extends State<_ConditionDialog> {
  final _rounds = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _rounds.dispose();
    super.dispose();
  }

  Future<void> _add(Condition condition) async {
    final rounds = _rounds.text.isEmpty ? null : int.tryParse(_rounds.text);
    if (_rounds.text.isNotEmpty && (rounds == null || rounds < 1)) {
      setState(() => _errorText = 'Die Dauer beträgt mindestens 1 Runde.');
      return;
    }
    await widget.encounter.addCondition(
      widget.combatant,
      condition,
      rounds: rounds,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Zustand für ${widget.combatant.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(
              'condition-rounds',
              'Dauer in Runden (optional)',
              _rounds,
              helper: 'Leer: bleibt, bis der Zustand entfernt wird',
              formatters: _digits,
              number: true,
            ),
            if (_errorText != null) _error(context, _errorText!),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final condition in Condition.values)
                  ActionChip(
                    key: Key('condition-option-${condition.name}'),
                    label: Text(condition.label),
                    onPressed: () => _add(condition),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
      ],
    );
  }
}

/// Gives a combatant a named effect: bonus or penalty on attack rolls,
/// armor class, damage and/or saving throws, with an optional duration.
class _BuffDialog extends StatefulWidget {
  const _BuffDialog({required this.encounter, required this.combatant});

  final Encounter encounter;
  final Combatant combatant;

  @override
  State<_BuffDialog> createState() => _BuffDialogState();
}

class _BuffDialogState extends State<_BuffDialog> {
  final _name = TextEditingController();
  final _attack = TextEditingController();
  final _armorClass = TextEditingController();
  final _damage = TextEditingController();
  final _savingThrow = TextEditingController();
  final _rounds = TextEditingController();

  /// Damage type of the damage bonus; null for the attack's type.
  String? _damageType;
  String? _errorText;

  @override
  void dispose() {
    _name.dispose();
    _attack.dispose();
    _armorClass.dispose();
    _damage.dispose();
    _savingThrow.dispose();
    _rounds.dispose();
    super.dispose();
  }

  /// The bonus typed into [controller], null if it is empty. If it cannot
  /// be read, [message] is shown and [_InvalidInput] is thrown.
  Bonus? _readBonus(TextEditingController controller, String message) {
    if (controller.text.trim().isEmpty) return null;
    try {
      return Bonus.parse(controller.text);
    } on FormatException {
      setState(() => _errorText = message);
      throw const _InvalidInput();
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _errorText = 'Der Effekt braucht einen Namen.');
      return;
    }
    final Bonus? attackBonus;
    final Bonus? damageBonus;
    final Bonus? saveBonus;
    try {
      attackBonus = _readBonus(
        _attack,
        'Bonus auf den Angriffswurf bitte wie 1d4, -1d4 oder 2 angeben.',
      );
      damageBonus = _readBonus(
        _damage,
        'Bonus auf den Schaden bitte wie 1d6, -1d4 oder 2 angeben.',
      );
      saveBonus = _readBonus(
        _savingThrow,
        'Bonus auf Rettungswürfe bitte wie 1d4, -1d4 oder 2 angeben.',
      );
    } on _InvalidInput {
      return;
    }
    final armorClass = _armorClass.text.trim().isEmpty
        ? 0
        : int.tryParse(_armorClass.text.trim());
    if (armorClass == null) {
      setState(
        () => _errorText =
            'Bonus auf die Rüstungsklasse bitte als Zahl angeben, z. B. 2.',
      );
      return;
    }
    final rounds = _rounds.text.isEmpty ? null : int.tryParse(_rounds.text);
    if (_rounds.text.isNotEmpty && (rounds == null || rounds < 1)) {
      setState(() => _errorText = 'Die Dauer beträgt mindestens 1 Runde.');
      return;
    }

    await widget.encounter.addBuff(
      widget.combatant,
      name: _name.text,
      attackBonus: attackBonus,
      armorClassBonus: armorClass,
      damageBonus: damageBonus,
      damageType: damageBonus == null ? null : _damageType,
      saveBonus: saveBonus,
      rounds: rounds,
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Effekt für ${widget.combatant.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field('buff-name', 'Name (z. B. Segen)', _name),
            _field(
              'buff-attack',
              'Angriffswurf (optional)',
              _attack,
              helper: 'z. B. 1d4, -1d4 oder 2',
            ),
            _field(
              'buff-ac',
              'Rüstungsklasse (optional)',
              _armorClass,
              helper: 'z. B. 2 oder -2',
              formatters: _signedDigits,
              number: true,
            ),
            _field(
              'buff-damage',
              'Schaden (optional)',
              _damage,
              helper:
                  'z. B. 1d6 oder 2; bei kritischem Treffer doppelte Würfel',
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: DropdownButtonFormField<String?>(
                key: const Key('buff-damage-type'),
                initialValue: _damageType,
                isExpanded: true,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Schadensart des Bonus',
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('wie der Angriff'),
                  ),
                  for (final type in damageTypes)
                    DropdownMenuItem(value: type, child: Text(type)),
                ],
                onChanged: (type) => setState(() => _damageType = type),
              ),
            ),
            _field(
              'buff-saving-throw',
              'Rettungswürfe (optional)',
              _savingThrow,
              helper: 'z. B. 1d4 oder 2',
            ),
            _field(
              'buff-rounds',
              'Dauer in Runden (optional)',
              _rounds,
              helper: 'Leer: bleibt, bis der Effekt entfernt wird',
              formatters: _digits,
              number: true,
            ),
            if (_errorText != null) _error(context, _errorText!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const Key('buff-save'),
          onPressed: _save,
          child: const Text('Vergeben'),
        ),
      ],
    );
  }
}

/// Thrown by input helpers after they showed an error message.
class _InvalidInput implements Exception {
  const _InvalidInput();
}
