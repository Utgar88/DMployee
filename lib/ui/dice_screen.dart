import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../dice/dice_expression.dart';
import '../dice/dice_roller.dart';
import '../dice/modifier.dart';
import '../log/log_event.dart';
import '../log/log_repository.dart';
import '../log/roll_record.dart';
import 'menu_button.dart';

/// One finished roll as shown in the result card, plus the event written to
/// the log for it.
class _RollEntry {
  const _RollEntry({
    required this.total,
    required this.detail,
    required this.event,
    this.note,
  });

  final int total;
  final String detail;
  final String? note;
  final FreeRollEvent event;
}

/// Dice roller screen: pick a die, count and modifier, then roll.
///
/// A single d20 can additionally be rolled with advantage or disadvantage and
/// against a difficulty class (saving throw / ability check).
///
/// Every roll is written to the [log] as a free roll.
class DiceScreen extends StatefulWidget {
  DiceScreen({
    super.key,
    required this.log,
    DiceRoller? roller,
    this.onOpenMenu,
  }) : roller = roller ?? DiceRoller();

  final LogRepository log;
  final DiceRoller roller;

  /// Opens the app menu; without it the app bar has no menu button.
  final VoidCallback? onOpenMenu;

  static const dice = [4, 6, 8, 10, 12, 20, 100];

  @override
  State<DiceScreen> createState() => _DiceScreenState();
}

class _DiceScreenState extends State<DiceScreen> {
  final _dcController = TextEditingController();
  _RollEntry? _latest;

  int _sides = 20;
  int _count = 1;
  int _modifier = 0;
  RollMode _mode = RollMode.normal;

  DiceExpression get _expression =>
      DiceExpression(count: _count, sides: _sides, modifier: _modifier);

  /// Advantage, disadvantage and difficulty class only apply to one d20.
  bool get _isSingleD20 => _sides == 20 && _count == 1;

  @override
  void dispose() {
    _dcController.dispose();
    super.dispose();
  }

  Future<void> _roll() async {
    final dc = _isSingleD20 ? int.tryParse(_dcController.text) : null;
    final entry = _isSingleD20 ? _rollD20(dc) : _rollExpression();

    setState(() => _latest = entry);
    await widget.log.add(entry.event);
  }

  _RollEntry _rollExpression() {
    final result = widget.roller.roll(_expression);
    return _RollEntry(
      total: result.total,
      detail:
          '$_expression: ${result.rolls.join(' + ')}'
          '${_modifierSuffix(_modifier)}',
      event: FreeRollEvent(roll: RollRecord.fromRoll(result)),
    );
  }

  _RollEntry _rollD20(int? dc) {
    final roll = widget.roller.rollD20(
      mode: _mode,
      modifiers: [if (_modifier != 0) Modifier('Modifier', _modifier)],
    );

    final String detail;
    if (_mode == RollMode.normal) {
      detail = '$_expression: ${roll.kept}${_modifierSuffix(_modifier)}';
    } else {
      final label = _mode == RollMode.advantage ? 'Vorteil' : 'Nachteil';
      detail =
          '$_expression $label: ${roll.rolls.join(' | ')} → ${roll.kept}'
          '${_modifierSuffix(_modifier)}';
    }

    String? note;
    if (dc != null) {
      final check = CheckResult(roll: roll, dc: dc);
      note = '${check.isSuccess ? 'Erfolg' : 'Fehlschlag'} gegen SG $dc';
    } else if (roll.isNatural20) {
      note = 'Natürliche 20';
    } else if (roll.isNatural1) {
      note = 'Natürliche 1';
    }

    return _RollEntry(
      total: roll.total,
      detail: detail,
      note: note,
      event: FreeRollEvent(roll: RollRecord.fromD20(roll), dc: dc),
    );
  }

  static String _modifierSuffix(int modifier) {
    if (modifier == 0) return '';
    return modifier > 0 ? ' + $modifier' : ' - ${-modifier}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = _latest;

    return Scaffold(
      appBar: AppBar(
        leading: menuButton(widget.onOpenMenu),
        title: const Text('Würfler'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final sides in DiceScreen.dice)
                  ChoiceChip(
                    key: Key('die-$sides'),
                    label: Text('d$sides'),
                    selected: _sides == sides,
                    onSelected: (_) => setState(() => _sides = sides),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _Stepper(
              label: 'Anzahl',
              value: '$_count',
              keyPrefix: 'count',
              onMinus: _count > 1 ? () => setState(() => _count--) : null,
              onPlus: _count < 99 ? () => setState(() => _count++) : null,
            ),
            _Stepper(
              label: 'Modifier',
              value: _modifier > 0 ? '+$_modifier' : '$_modifier',
              keyPrefix: 'modifier',
              onMinus: () => setState(() => _modifier--),
              onPlus: () => setState(() => _modifier++),
            ),
            if (_isSingleD20) ...[
              const SizedBox(height: 8),
              SegmentedButton<RollMode>(
                key: const Key('mode-selector'),
                segments: const [
                  ButtonSegment(
                    value: RollMode.normal,
                    label: Text('Normal', key: Key('mode-normal')),
                  ),
                  ButtonSegment(
                    value: RollMode.advantage,
                    label: Text('Vorteil', key: Key('mode-advantage')),
                  ),
                  ButtonSegment(
                    value: RollMode.disadvantage,
                    label: Text('Nachteil', key: Key('mode-disadvantage')),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) =>
                    setState(() => _mode = selection.first),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('dc-field'),
                controller: _dcController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Schwierigkeitsgrad (SG), optional',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('roll-button'),
              onPressed: _roll,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Würfeln: '),
                    Text('$_expression', key: const Key('expression')),
                  ],
                ),
              ),
            ),
            if (latest != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        '${latest.total}',
                        key: const Key('result-total'),
                        style: theme.textTheme.displayLarge,
                      ),
                      Text(
                        latest.detail,
                        key: const Key('result-detail'),
                        textAlign: TextAlign.center,
                      ),
                      if (latest.note != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          latest.note!,
                          key: const Key('result-note'),
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.keyPrefix,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final String value;
  final String keyPrefix;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton.filledTonal(
          key: Key('$keyPrefix-minus'),
          onPressed: onMinus,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 56,
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        IconButton.filledTonal(
          key: Key('$keyPrefix-plus'),
          onPressed: onPlus,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}
