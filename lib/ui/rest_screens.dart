import 'package:material_ui/material_ui.dart';

import '../characters/character.dart';
import '../characters/rest.dart';
import '../log/log_event.dart';
import 'form_widgets.dart';

/// What the game master chose in the [RestDialog].
typedef RestChoice = ({RestKind kind, List<Character> characters});

/// `tot`, `liegt im Sterben` or `0 TP`.
String restBlockerText(RestBlocker blocker, Character character) =>
    switch (blocker) {
      RestBlocker.dead => 'tot',
      RestBlocker.dying => 'liegt im Sterben',
      RestBlocker.tooFewHp => '${character.hp} TP',
    };

/// Chooses short or long rest and who takes part; all characters are
/// chosen at first. Characters the rest would not help show why.
class RestDialog extends StatefulWidget {
  const RestDialog({super.key, required this.characters, required this.rests});

  final List<Character> characters;
  final RestService rests;

  @override
  State<RestDialog> createState() => _RestDialogState();
}

class _RestDialogState extends State<RestDialog> {
  var _kind = RestKind.short;
  late final _chosen = {...widget.characters};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Rast'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Regeln: ${widget.rests.ruleset.label}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              SegmentedButton<RestKind>(
                key: const Key('rest-kind'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: RestKind.short,
                    label: Text('Kurze Rast'),
                  ),
                  ButtonSegment(
                    value: RestKind.long,
                    label: Text('Lange Rast'),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (selection) =>
                    setState(() => _kind = selection.single),
              ),
              const SizedBox(height: 8),
              for (final (index, character) in widget.characters.indexed)
                _tile(context, index, character),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('rest-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          key: const Key('rest-confirm'),
          onPressed: _chosen.isEmpty
              ? null
              : () => Navigator.pop<RestChoice>(context, (
                  kind: _kind,
                  characters: [
                    for (final character in widget.characters)
                      if (_chosen.contains(character)) character,
                  ],
                )),
          child: const Text('Rasten'),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, int index, Character character) {
    final blocker = widget.rests.blockerFor(character, _kind);
    return CheckboxListTile(
      key: Key('rest-character-$index'),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: _chosen.contains(character),
      onChanged: (value) => setState(
        () =>
            value == true ? _chosen.add(character) : _chosen.remove(character),
      ),
      title: Text(character.name),
      subtitle: blocker == null
          ? Text(
              'TP ${character.hp}/'
              '${character.maxHpUnder(widget.rests.ruleset)}',
            )
          : Text(
              'kein Nutzen: ${restBlockerText(blocker, character)}',
              key: Key('rest-blocker-$index'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
    );
  }
}

/// During a short rest: each character spends hit dice one at a time,
/// rolled by the app or rolled at the table and typed in.
class ShortRestScreen extends StatefulWidget {
  const ShortRestScreen({
    super.key,
    required this.characters,
    required this.rests,
  });

  final List<Character> characters;
  final RestService rests;

  @override
  State<ShortRestScreen> createState() => _ShortRestScreenState();
}

class _ShortRestScreenState extends State<ShortRestScreen> {
  late final _characters = [...widget.characters];
  late final _faces = [
    for (final _ in widget.characters) TextEditingController(),
  ];
  final _results = <int, String>{};
  final _errors = <int, String>{};

  @override
  void dispose() {
    for (final controller in _faces) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _spend(int index) async {
    final character = _characters[index];
    final face = int.tryParse(_faces[index].text);
    try {
      final after = await widget.rests.spendHitDie(character, manualFace: face);
      setState(() {
        _characters[index] = after;
        _results[index] = '+${after.hp - character.hp} TP';
        _errors.remove(index);
        _faces[index].clear();
      });
    } on ArgumentError {
      setState(
        () => _errors[index] =
            'Ein W${character.hitDie} zeigt 1 bis ${character.hitDie}.',
      );
    }
  }

  /// Why [character] cannot spend a hit die; null if it can.
  String? _reason(Character character) {
    if (widget.rests.blockerFor(character, RestKind.short) case final b?) {
      return 'kein Nutzen: ${restBlockerText(b, character)}';
    }
    if (character.hitDiceRemaining == 0) return 'keine Trefferwürfel übrig';
    if (character.hp >= character.maxHpUnder(widget.rests.ruleset)) {
      return 'TP voll';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kurze Rast'),
        actions: [
          TextButton(
            key: const Key('short-rest-done'),
            onPressed: () => Navigator.pop(context),
            child: const Text('Fertig'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Trefferwürfel einzeln ausgeben: leer lassen, damit die App '
              'würfelt, oder den am Tisch gewürfelten Wert eintragen.',
            ),
            const SizedBox(height: 8),
            for (final (index, character) in _characters.indexed)
              _card(context, index, character),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, int index, Character character) {
    final theme = Theme.of(context);
    final reason = _reason(character);
    final status = [?_results[index], ?reason].join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(character.name, style: theme.textTheme.titleMedium),
            Text(
              'TP ${character.hp}/'
              '${character.maxHpUnder(widget.rests.ruleset)} · Trefferwürfel '
              '${character.hitDiceRemaining}/${character.hitDiceTotal} '
              '(W${character.hitDie})',
              key: Key('short-rest-stats-$index'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    key: Key('hit-die-face-$index'),
                    controller: _faces[index],
                    enabled: reason == null,
                    keyboardType: TextInputType.number,
                    inputFormatters: digitsInput,
                    decoration: InputDecoration(
                      labelText: 'W${character.hitDie} am Tisch',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  key: Key('hit-die-$index'),
                  onPressed: reason == null ? () => _spend(index) : null,
                  child: const Text('Trefferwürfel'),
                ),
              ],
            ),
            if (_errors[index] case final error?) formError(context, error),
            if (status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(status, key: Key('hit-die-result-$index')),
              ),
          ],
        ),
      ),
    );
  }
}
