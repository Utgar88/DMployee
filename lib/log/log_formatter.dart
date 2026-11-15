import '../combat/condition.dart';
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
      AttackEvent() => _attack(event),
      InitiativeEvent() => _initiative(event),
      RoundEvent() => LogLine([LogSpan('Runde ${event.round} beginnt')]),
      CombatantDownEvent() => LogLine([LogSpan('${event.name} geht zu Boden')]),
      HpChangeEvent() => _hpChange(event),
      DeathSaveEvent() => _deathSave(event),
      DyingDamageEvent() => LogLine([
        LogSpan(
          '${event.name} erleidet am Boden Schaden: '
          '${event.failuresAdded == 1 ? '1 Fehlschlag' : '${event.failuresAdded} Fehlschläge'} '
          'bei den Todesrettungswürfen (Fehlschläge ${event.failures})',
        ),
      ]),
      ConditionEvent() => _condition(event),
      CombatantStableEvent() => LogLine([LogSpan('${event.name} ist stabil')]),
      CombatantDiedEvent() => LogLine([
        LogSpan(
          event.massiveDamage
              ? '${event.name} stirbt sofort (massiver Schaden)'
              : '${event.name} stirbt',
        ),
      ]),
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

  LogLine _attack(AttackEvent event) {
    final who = '${event.attackerName} hat ${event.targetName}';
    final armorClass = 'gegen RK ${event.targetArmorClass}';
    final attackDetails = [
      'Angriff: ${event.attackName}',
      ...rollDetails(event.attackRoll),
      ..._modeReasons(event),
    ];

    if (!event.hit) {
      return LogLine([
        LogSpan('$who mit '),
        LogSpan(
          '${event.attackRoll.total}',
          details: [...attackDetails, 'Verfehlt $armorClass'],
        ),
        const LogSpan(' verfehlt'),
      ]);
    }

    return LogLine([
      LogSpan('$who für '),
      LogSpan(
        '${event.damage}',
        details: [
          ...attackDetails,
          '${event.critical ? 'Kritischer Treffer' : 'Treffer'} $armorClass',
          'Schaden (${event.damageType}):',
          ...rollDetails(event.damageRoll!),
          if (event.damageEffect case final effect?)
            '${effect.label} gegen ${event.damageType}: '
                '${event.rolledDamage} → ${event.damage}',
        ],
      ),
      LogSpan(
        ' Schaden ${event.critical ? 'kritisch ' : ''}getroffen'
        '${event.damageEffect == null ? '' : ' (${event.damageEffect!.label})'}',
      ),
    ]);
  }

  LogLine _initiative(InitiativeEvent event) {
    return LogLine([
      const LogSpan('Initiative: '),
      for (final (index, entry) in event.entries.indexed) ...[
        LogSpan('${index == 0 ? '' : ', '}${entry.name} '),
        LogSpan('${entry.roll.total}', details: rollDetails(entry.roll)),
      ],
    ]);
  }

  LogLine _hpChange(HpChangeEvent event) {
    final effect = event.damageEffect;
    final notes = [?event.source, ?effect?.label];
    final details = [
      if (event.source != null) 'Quelle: ${event.source}',
      if (event.damageType != null) 'Schadensart: ${event.damageType}',
      if (effect != null)
        '${effect.label}'
            '${event.damageType == null ? '' : ' gegen ${event.damageType}'}: '
            '${event.amount} → ${event.adjusted}',
      'Trefferpunkte: ${event.hpBefore} → ${event.hpAfter} '
          '(Maximum ${event.maxHp})',
      if (event.effective != event.adjusted)
        'Davon wirksam: ${event.effective}',
    ];

    return LogLine([
      LogSpan('${event.name} ${event.healing ? 'wird um' : 'erleidet'} '),
      LogSpan('${event.adjusted}', details: details),
      LogSpan(
        '${event.healing ? ' TP geheilt' : ' Schaden'}'
        '${notes.isEmpty ? '' : ' (${notes.join(', ')})'}',
      ),
    ]);
  }

  /// `vergiftet` for `poisoned`; the stored name itself if this app version
  /// does not know the condition.
  String _conditionWord(String name) =>
      Condition.fromName(name)?.label.toLowerCase() ?? name;

  LogLine _condition(ConditionEvent event) {
    final word = _conditionWord(event.condition);
    final rounds = event.rounds;
    return LogLine([
      LogSpan(switch (event.change) {
        ConditionChange.added =>
          '${event.name} ist jetzt $word'
              '${rounds == null ? '' : ' ($rounds ${rounds == 1 ? 'Runde' : 'Runden'})'}',
        ConditionChange.removed => '${event.name} ist nicht mehr $word',
        ConditionChange.expired =>
          '${event.name} ist nicht mehr $word (Dauer abgelaufen)',
      }),
    ]);
  }

  /// Why an attack was rolled with advantage, disadvantage or neither, if
  /// conditions were involved.
  List<String> _modeReasons(AttackEvent event) {
    if (event.conditionEffects.isEmpty) return const [];

    final chosen = event.chosenMode;
    var advantage = chosen == RollMode.advantage;
    var disadvantage = chosen == RollMode.disadvantage;
    final lines = [
      if (advantage) 'Vorteil: von der Spielleitung gewählt',
      if (disadvantage) 'Nachteil: von der Spielleitung gewählt',
    ];
    for (final effect in event.conditionEffects) {
      final who = effect.onAttacker ? event.attackerName : event.targetName;
      lines.add(
        '${effect.advantage ? 'Vorteil' : 'Nachteil'}: '
        '$who ist ${_conditionWord(effect.condition)}',
      );
      advantage |= effect.advantage;
      disadvantage |= !effect.advantage;
    }
    if (advantage && disadvantage) {
      lines.add('Vorteil und Nachteil heben sich auf');
    }
    return lines;
  }

  LogLine _deathSave(DeathSaveEvent event) {
    final roll = event.roll;
    final tally = '(Erfolge ${event.successes}, Fehlschläge ${event.failures})';
    final String result;
    if (roll.isNatural20) {
      result = '${event.name} kommt mit 1 TP wieder zu sich';
    } else if (roll.isNatural1) {
      result = 'zwei Fehlschläge $tally';
    } else if (roll.total >= 10) {
      result = 'Erfolg $tally';
    } else {
      result = 'Fehlschlag $tally';
    }

    return LogLine([
      LogSpan('Todesrettungswurf von ${event.name}: '),
      LogSpan(
        '${roll.total}',
        details: [
          ...rollDetails(roll),
          'Erfolg ab 10',
          'Erfolge: ${event.successes} von 3',
          'Fehlschläge: ${event.failures} von 3',
        ],
      ),
      LogSpan(', $result'),
    ]);
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
    if (roll.manual) {
      final mode = switch (roll.mode) {
        RollMode.normal => '',
        RollMode.advantage => ' mit Vorteil',
        RollMode.disadvantage => ' mit Nachteil',
      };
      return '${roll.dice}$mode von Hand: ${roll.kept}';
    }
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
