import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../combat/attack.dart';
import '../combat/combatant.dart';
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

    final outcome = result.outcome;
    final line = widget.formatter.format(
      AttackEvent(
        attackerName: attacker.name,
        targetName: result.target.name,
        attackName: attack.name,
        targetArmorClass: result.target.armorClass,
        attackRoll: outcome.attackRoll,
        hit: outcome.hit,
        critical: outcome.critical,
        damageType: attack.damageType,
        damageRoll: outcome.damageRoll,
        damage: outcome.damage,
        damageEffect: outcome.damageEffect,
      ),
    );
    setState(() => _lastAction = line.text);
  }

  Future<void> _changeHp(Combatant combatant) async {
    final event = await showDialog<HpChangeEvent>(
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
                    'RK ${combatant.armorClass} · '
                    'TP ${combatant.hp}/${combatant.maxHp}',
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
            if (combatant.initiative != null)
              Text(
                'Initiative ${combatant.initiative}',
                key: Key('initiative-$index'),
                style: theme.textTheme.bodySmall,
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
    _field('attack-type', 'Schadensart (z. B. Hieb)', type),
  ];

  void dispose() {
    name.dispose();
    bonus.dispose();
    damage.dispose();
    type.dispose();
  }
}

class _CombatantDialog extends StatefulWidget {
  const _CombatantDialog({required this.encounter});

  final Encounter encounter;

  @override
  State<_CombatantDialog> createState() => _CombatantDialogState();
}

class _CombatantDialogState extends State<_CombatantDialog> {
  final _name = TextEditingController();
  final _armorClass = TextEditingController();
  final _hp = TextEditingController();
  final _initiative = TextEditingController();
  final _attack = _AttackFields();
  bool _isPlayer = false;
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
      title: const Text('Kämpfer hinzufügen'),
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
            Text(
              'Angriff (optional)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
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
          key: const Key('combatant-save'),
          onPressed: _save,
          child: const Text('Hinzufügen'),
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
  RollMode _mode = RollMode.normal;
  String? _errorText;

  @override
  void dispose() {
    _manualAttack.dispose();
    _manualDamage.dispose();
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
            _field(
              'manual-damage',
              'Schadenswürfel (Summe)',
              _manualDamage,
              helper: 'Augensumme ohne Schadensbonus',
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
                    'RK ${combatant.armorClass} · '
                    'TP ${combatant.hp}/${combatant.maxHp}',
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

/// Damage or healing for one combatant without an attack.
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

  Future<void> _apply({required bool healing}) async {
    final amount = int.tryParse(_amount.text);
    if (amount == null || amount < 1) {
      setState(() => _errorText = 'Bitte einen Betrag ab 1 eintragen.');
      return;
    }
    if (healing && widget.combatant.isDead) {
      setState(
        () => _errorText = 'Ein toter Charakter lässt sich nicht heilen.',
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
      title: Text('${combatant.name}: TP ${combatant.hp}/${combatant.maxHp}'),
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
            _field(
              'hp-damage-type',
              'Schadensart (optional)',
              _damageType,
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
  String? _errorText;

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  Future<void> _roll() async {
    try {
      final event = await widget.encounter.rollDeathSave(
        widget.combatant,
        manualRoll: int.tryParse(_manual.text),
      );
      if (mounted) Navigator.pop(context, event);
    } on ArgumentError {
      setState(() => _errorText = 'Ein d20 zeigt 1 bis 20.');
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
