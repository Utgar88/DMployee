import 'log_event.dart';

/// A play session. Every log entry belongs to exactly one session, so the
/// log can later be filtered per evening.
class Session {
  const Session({
    required this.id,
    required this.name,
    required this.startedAt,
  });

  final int id;
  final String name;
  final DateTime startedAt;
}

/// A stored [LogEvent] with its position in time.
class LogEntry {
  const LogEntry({
    required this.id,
    required this.sessionId,
    required this.timestamp,
    required this.event,
  });

  /// Ascending number: a higher id was logged later.
  final int id;
  final int sessionId;
  final DateTime timestamp;
  final LogEvent event;
}

/// Storage for the log. All modules write their events here.
abstract class LogRepository {
  /// Starts a new session. New entries go into it from now on.
  Future<Session> startSession(String name);

  /// All sessions, newest first.
  Future<List<Session>> sessions();

  /// The session new entries go into. Creates one named after today's date
  /// if none exists yet.
  Future<Session> activeSession();

  /// Stores [event] in the [activeSession].
  Future<LogEntry> add(LogEvent event);

  /// Entries, newest first. Limited to one session if [sessionId] is given.
  Future<List<LogEntry>> entries({int? sessionId});

  Future<void> close();
}

/// Name for an automatically created session, e.g. `Session 15.11.2026`.
String defaultSessionName(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return 'Session ${two(date.day)}.${two(date.month)}.${date.year}';
}

/// Keeps the log in memory only. Used in tests; everything is lost when the
/// app closes.
class InMemoryLogRepository implements LogRepository {
  InMemoryLogRepository({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final _sessions = <Session>[];
  final _entries = <LogEntry>[];

  @override
  Future<Session> startSession(String name) async {
    final session = Session(
      id: _sessions.length + 1,
      name: name,
      startedAt: _now(),
    );
    _sessions.add(session);
    return session;
  }

  @override
  Future<List<Session>> sessions() async => _sessions.reversed.toList();

  @override
  Future<Session> activeSession() async {
    if (_sessions.isEmpty) {
      return startSession(defaultSessionName(_now()));
    }
    return _sessions.last;
  }

  @override
  Future<LogEntry> add(LogEvent event) async {
    final session = await activeSession();
    final entry = LogEntry(
      id: _entries.length + 1,
      sessionId: session.id,
      timestamp: _now(),
      event: event,
    );
    _entries.add(entry);
    return entry;
  }

  @override
  Future<List<LogEntry>> entries({int? sessionId}) async {
    return [
      for (final entry in _entries.reversed)
        if (sessionId == null || entry.sessionId == sessionId) entry,
    ];
  }

  @override
  Future<void> close() async {}
}
