import '../dice/dice_roller.dart';
import 'log_event.dart';
import 'roll_record.dart';

/// One piece of a log line. A span with [details] can be tapped to show how
/// its value came about.
class LogSpan {
  const LogSpan(this.text, {this.details = const []});

  final String text;

  /// Breakdown lines shown when the span is tapped.
  final List<String> details;

  bool get hasDetails => details.isNotEmpty;
}

/// A log entry as shown to the user.
class LogLine {
  const LogLine(this.spans, {this.isFreeRoll = false});

  final List<LogSpan> spans;

  /// True for rolls made without a character, so the UI can mark them.
  final bool isFreeRoll;

  /// The whole line as plain text.
  String get text => spans.map((span) => span.text).join();
}

/// Turns stored [LogEvent]s into the lines and details shown in the log.
class LogFormatter {
  const LogFormatter();

  LogLine format(LogEvent event) {
    return switch (event) {
      FreeRollEvent() => _freeRoll(event),
      UnknownEvent() => LogLine([
        LogSpan('Unbekannter Eintrag (${event.type})'),
      ]),
    };
  }

  LogLine _freeRoll(FreeRollEvent event) {
    final roll = event.roll;
    final outcome = _checkOutcome(event);

    return LogLine([
      LogSpan('Freier Wurf ${roll.notation}: '),
      LogSpan('${roll.total}', details: [...rollDetails(roll), ?outcome]),
      if (outcome != null) LogSpan(' ($outcome)'),
    ], isFreeRoll: true);
  }

  /// Breakdown of a single roll: dice, each modifier with its source, total.
  List<String> rollDetails(RollRecord roll) {
    return [
      _diceLine(roll),
      for (final modifier in roll.modifiers) '$modifier',
      'Summe: ${roll.total}',
      if (roll.isNatural20) 'Natürliche 20',
      if (roll.isNatural1) 'Natürliche 1',
    ];
  }

  String _diceLine(RollRecord roll) {
    switch (roll.mode) {
      case RollMode.advantage:
        return '${roll.dice} mit Vorteil: ${roll.rolls.join(' | ')} '
            '→ ${roll.kept}';
      case RollMode.disadvantage:
        return '${roll.dice} mit Nachteil: ${roll.rolls.join(' | ')} '
            '→ ${roll.kept}';
      case RollMode.normal:
        if (roll.rolls.length == 1) return '${roll.dice}: ${roll.kept}';
        return '${roll.dice}: ${roll.rolls.join(' + ')} = ${roll.kept}';
    }
  }

  String? _checkOutcome(FreeRollEvent event) {
    final success = event.isSuccess;
    if (success == null) return null;
    return '${success ? 'Erfolg' : 'Fehlschlag'} gegen SG ${event.dc}';
  }
}
