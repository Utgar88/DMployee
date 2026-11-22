import 'package:material_ui/material_ui.dart';

import '../characters/character.dart';
import '../characters/spell_slots.dart';

/// `Zauberplätze: 1. Grad 3/4 · Pakt 1/2 (3. Grad)`; null without slots.
String? spellSlotSummary(Character character) {
  if (!character.hasSpellSlots) return null;
  final parts = [
    for (final level in character.slotLevels)
      '$level. Grad ${character.slotsRemaining(level)}/'
          '${character.slotsTotal(level)}',
    if (character.pactSlots > 0)
      'Pakt ${character.pactSlotsRemaining}/${character.pactSlots} '
          '(${character.pactSlotLevel}. Grad)',
  ];
  return 'Zauberplätze: ${parts.join(' · ')}';
}

/// Shows the spell slots of [character]; each level and the pact magic can
/// use a slot or give one back.
Future<void> showSpellSlots(
  BuildContext context,
  SpellSlotService service,
  Character character,
) => showDialog<void>(
  context: context,
  builder: (_) => SpellSlotsDialog(service: service, character: character),
);

class SpellSlotsDialog extends StatefulWidget {
  const SpellSlotsDialog({
    super.key,
    required this.service,
    required this.character,
  });

  final SpellSlotService service;
  final Character character;

  @override
  State<SpellSlotsDialog> createState() => _SpellSlotsDialogState();
}

class _SpellSlotsDialogState extends State<SpellSlotsDialog> {
  late Character _character = widget.character;

  Future<void> _run(Future<Character> Function() change) async {
    final after = await change();
    if (mounted) setState(() => _character = after);
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final c = _character;
    return AlertDialog(
      title: Text('Zauberplätze: ${c.name}'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!c.hasSpellSlots)
                const Text(
                  'Keine Zauberplätze eingetragen. Sie stehen im '
                  'Charakterbogen.',
                ),
              for (final level in c.slotLevels)
                _row(
                  label: '$level. Grad',
                  count:
                      '${c.slotsRemaining(level)} von ${c.slotsTotal(level)}',
                  countKey: 'slot-count-$level',
                  useKey: 'slot-use-$level',
                  restoreKey: 'slot-restore-$level',
                  onUse: c.slotsRemaining(level) > 0
                      ? () => _run(() => service.use(c, level))
                      : null,
                  onRestore: (c.slotsUsed[level] ?? 0) > 0
                      ? () => _run(() => service.restore(c, level))
                      : null,
                ),
              if (c.pactSlots > 0)
                _row(
                  label: 'Paktmagie',
                  count:
                      '${c.pactSlotsRemaining} von ${c.pactSlots} '
                      '(${c.pactSlotLevel}. Grad)',
                  countKey: 'pact-count',
                  useKey: 'pact-use',
                  restoreKey: 'pact-restore',
                  onUse: c.pactSlotsRemaining > 0
                      ? () => _run(() => service.usePact(c))
                      : null,
                  onRestore: c.pactSlotsUsed > 0
                      ? () => _run(() => service.restorePact(c))
                      : null,
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('slots-close'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Schließen'),
        ),
      ],
    );
  }

  Widget _row({
    required String label,
    required String count,
    required String countKey,
    required String useKey,
    required String restoreKey,
    required VoidCallback? onUse,
    required VoidCallback? onRestore,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleSmall),
              Text(count, key: Key(countKey)),
            ],
          ),
        ),
        IconButton(
          key: Key(useKey),
          tooltip: 'Platz verbrauchen',
          onPressed: onUse,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        IconButton(
          key: Key(restoreKey),
          tooltip: 'Platz zurückgeben',
          onPressed: onRestore,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}
