import 'package:material_ui/material_ui.dart';

import '../log/log_formatter.dart';
import '../log/log_repository.dart';

/// Shows the log, newest entry first. Values with details can be tapped to
/// see how they came about. Entries can be filtered by session.
class LogScreen extends StatefulWidget {
  const LogScreen({
    super.key,
    required this.log,
    this.formatter = const LogFormatter(),
  });

  final LogRepository log;
  final LogFormatter formatter;

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  List<Session> _sessions = const [];
  List<LogEntry> _entries = const [];

  /// Session to show; null shows all sessions.
  int? _sessionFilter;

  /// Unfolded details: entry id to the index of the tapped value within
  /// that entry's line.
  final _expanded = <int, int>{};

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await widget.log.sessions();
    final entries = await widget.log.entries(sessionId: _sessionFilter);
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _startSession() async {
    final controller = TextEditingController(
      text: defaultSessionName(DateTime.now()),
    );
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Neue Session starten'),
        content: TextField(
          key: const Key('session-name-field'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const Key('session-start-button'),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Starten'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    await widget.log.startSession(name);
    await _load();
  }

  static String _time(DateTime timestamp) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(timestamp.hour)}:${two(timestamp.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log'),
        actions: [
          IconButton(
            key: const Key('new-session-button'),
            tooltip: 'Neue Session starten',
            onPressed: _startSession,
            icon: const Icon(Icons.playlist_add),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButton<int?>(
                key: const Key('session-filter'),
                isExpanded: true,
                value: _sessionFilter,
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Alle Sessions'),
                  ),
                  for (final session in _sessions)
                    DropdownMenuItem(
                      value: session.id,
                      child: Text(session.name),
                    ),
                ],
                onChanged: (sessionId) {
                  _sessionFilter = sessionId;
                  _load();
                },
              ),
            ),
            Expanded(child: _buildEntries(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildEntries(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_entries.isEmpty) {
      return const Center(child: Text('Noch keine Einträge'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _entries.length,
      itemBuilder: (context, index) => _buildEntry(context, _entries[index]),
    );
  }

  Widget _buildEntry(BuildContext context, LogEntry entry) {
    final theme = Theme.of(context);
    final line = widget.formatter.format(entry.event);
    final tappable = [
      for (final span in line.spans)
        if (span.hasDetails) span,
    ];
    final expandedIndex = _expanded[entry.id];
    final details = expandedIndex == null
        ? const <String>[]
        : tappable[expandedIndex].details;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: line.isFreeRoll
                ? Tooltip(
                    message: 'Freier Wurf',
                    child: Icon(
                      Icons.casino_outlined,
                      key: Key('free-roll-icon-${entry.id}'),
                      size: 20,
                      color: theme.colorScheme.outline,
                    ),
                  )
                : null,
          ),
          SizedBox(
            width: 48,
            child: Text(
              _time(entry.timestamp),
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  key: Key('log-line-${entry.id}'),
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final span in line.spans)
                      if (span.hasDetails)
                        _buildValue(theme, entry, tappable.indexOf(span), span)
                      else
                        Text(span.text),
                  ],
                ),
                if (expandedIndex != null)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [for (final detail in details) Text(detail)],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A tappable value. The first one in a line has the key
  /// `log-value-<entry id>`, further ones `log-value-<entry id>-<index>`.
  Widget _buildValue(ThemeData theme, LogEntry entry, int index, LogSpan span) {
    return InkWell(
      key: Key(
        index == 0 ? 'log-value-${entry.id}' : 'log-value-${entry.id}-$index',
      ),
      onTap: () => setState(() {
        if (_expanded[entry.id] == index) {
          _expanded.remove(entry.id);
        } else {
          _expanded[entry.id] = index;
        }
      }),
      child: Text(
        span.text,
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}
