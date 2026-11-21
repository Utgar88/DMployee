/// Input building blocks shared by the combat screen and the character
/// sheet.
library;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../combat/attack.dart';
import '../combat/damage.dart';
import '../dice/dice_expression.dart';

final digitsInput = [FilteringTextInputFormatter.digitsOnly];
final signedDigitsInput = [
  FilteringTextInputFormatter.allow(RegExp(r'[-+0-9]')),
];

Widget inputField(
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
class DamageTypeField extends StatefulWidget {
  const DamageTypeField({
    super.key,
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
  State<DamageTypeField> createState() => _DamageTypeFieldState();
}

class _DamageTypeFieldState extends State<DamageTypeField> {
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

Widget formError(BuildContext context, String message) => Padding(
  padding: const EdgeInsets.only(top: 8),
  child: Text(
    message,
    key: const Key('form-error'),
    style: TextStyle(color: Theme.of(context).colorScheme.error),
  ),
);

/// Input fields for one attack. Used when creating a combatant and when
/// adding a further attack.
class AttackFields {
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
    inputField('attack-name', 'Angriff (z. B. Langschwert)', name),
    inputField(
      'attack-bonus',
      'Angriffsbonus',
      bonus,
      formatters: signedDigitsInput,
      number: true,
    ),
    inputField('attack-damage', 'Schaden (z. B. 1d8+3)', damage),
    DamageTypeField(
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

/// Asks for one attack and returns it. [owner] is shown in the title.
class AttackDialog extends StatefulWidget {
  const AttackDialog({super.key, required this.owner});

  final String owner;

  @override
  State<AttackDialog> createState() => _AttackDialogState();
}

class _AttackDialogState extends State<AttackDialog> {
  final _attack = AttackFields();
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
      title: Text('Angriff für ${widget.owner}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ..._attack.build(),
            if (_errorText != null) formError(context, _errorText!),
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
