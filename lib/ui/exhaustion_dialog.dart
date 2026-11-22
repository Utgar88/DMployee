import 'package:material_ui/material_ui.dart';

import '../rules/exhaustion_rules.dart';
import '../rules/ruleset.dart';

/// Shows the exhaustion of [name] at [level] under [ruleset]: raise or
/// lower it by one, with the effects in force. [onChange] applies a new
/// level and returns the level afterwards. Raising to the highest level
/// asks first, because it kills.
Future<void> showExhaustion(
  BuildContext context, {
  required String name,
  required int level,
  required Ruleset ruleset,
  required Future<int> Function(int level) onChange,
}) => showDialog<void>(
  context: context,
  builder: (_) => ExhaustionDialog(
    name: name,
    level: level,
    ruleset: ruleset,
    onChange: onChange,
  ),
);

class ExhaustionDialog extends StatefulWidget {
  const ExhaustionDialog({
    super.key,
    required this.name,
    required this.level,
    required this.ruleset,
    required this.onChange,
  });

  final String name;
  final int level;
  final Ruleset ruleset;
  final Future<int> Function(int level) onChange;

  @override
  State<ExhaustionDialog> createState() => _ExhaustionDialogState();
}

class _ExhaustionDialogState extends State<ExhaustionDialog> {
  late int _level = widget.level;

  Future<void> _set(int level) async {
    if (widget.ruleset.exhaustionKills(level) && !await _confirmDeath()) {
      return;
    }
    final after = await widget.onChange(level);
    if (mounted) setState(() => _level = after);
  }

  Future<bool> _confirmDeath() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stufe 6'),
        content: Text('${widget.name} stirbt an Erschöpfung.'),
        actions: [
          TextButton(
            key: const Key('exhaustion-death-cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const Key('exhaustion-death-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stufe 6'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effects = widget.ruleset.exhaustionEffects(_level);
    return AlertDialog(
      title: Text('Erschöpfung: ${widget.name}'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    key: const Key('exhaustion-down'),
                    tooltip: 'Stufe senken',
                    onPressed: _level > 0 ? () => _set(_level - 1) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Stufe $_level',
                      key: const Key('exhaustion-level'),
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    key: const Key('exhaustion-up'),
                    tooltip: 'Stufe erhöhen',
                    onPressed: _level < maxExhaustion
                        ? () => _set(_level + 1)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Regelwerk: ${widget.ruleset.label}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text('Folgen', style: theme.textTheme.titleSmall),
              // Room for the longest list, so the buttons above stay put
              // while the level changes.
              ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      maxExhaustion *
                      MediaQuery.textScalerOf(context)
                          .scale(theme.textTheme.bodyMedium?.fontSize ?? 14) *
                      (theme.textTheme.bodyMedium?.height ?? 1.43),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (effects.isEmpty) const Text('Keine Folgen'),
                    for (final effect in effects) Text(effect),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Eine lange Rast senkt die Erschöpfung um 1.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('exhaustion-close'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Schließen'),
        ),
      ],
    );
  }
}
