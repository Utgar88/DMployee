import 'package:material_ui/material_ui.dart';

import '../rules/ruleset.dart';
import '../settings/app_settings.dart';

/// The app settings, opened from the menu on the left.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Regelwerk',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Gilt überall, wo sich die Regeln unterscheiden, zum '
                'Beispiel bei Rasten.',
              ),
            ),
            RadioGroup<Ruleset>(
              groupValue: settings.ruleset,
              onChanged: (ruleset) {
                if (ruleset != null) settings.setRuleset(ruleset);
              },
              child: Column(
                children: [
                  for (final ruleset in Ruleset.values)
                    RadioListTile<Ruleset>(
                      key: Key('ruleset-${ruleset.id}'),
                      value: ruleset,
                      title: Text(ruleset.label),
                      subtitle: Text(ruleset.description),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
