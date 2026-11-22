import '../combat/buff.dart';
import '../combat/condition.dart';
import '../combat/damage.dart';
import '../dice/dice_roller.dart';
import '../dice/modifier.dart';
import '../rules/exhaustion_rules.dart';
import '../rules/rest_rules.dart';
import '../rules/ruleset.dart';
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
      BuffEvent() => _buff(event),
      TempHpEvent() => _tempHp(event),
      CombatantRevivedEvent() => LogLine([
        LogSpan(
          '${event.name} wird wiederbelebt und hat ${event.hp} TP'
          '${event.source == null ? '' : ' (${event.source})'}',
        ),
      ]),
      CombatantStableEvent() => LogLine([LogSpan('${event.name} ist stabil')]),
      CombatantDiedEvent() => LogLine([
        LogSpan(
          event.massiveDamage
              ? '${event.name} stirbt sofort (massiver Schaden)'
              : event.exhaustion
              ? '${event.name} stirbt an Erschöpfung'
              : '${event.name} stirbt',
        ),
      ]),
      RestEvent() => _rest(event),
      HitDieEvent() => _hitDie(event),
      SpellSlotEvent() => _spellSlot(event),
      ExhaustionEvent() => _exhaustion(event),
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
      if (event.armorClassModifiers.isNotEmpty)
        'Rüstungsklasse: '
            '${event.targetArmorClass - Modifier.sum(event.armorClassModifiers)} '
            '${event.armorClassModifiers.join(' ')} '
            '= ${event.targetArmorClass}',
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

    final effects = {
      ?event.damageEffect?.label,
      for (final extra in event.extraDamage) ?extra.damageEffect?.label,
    };
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
                '${event.rolledDamage} → '
                '${adjustDamage(event.rolledDamage, effect)}',
          for (final extra in event.extraDamage) ...[
            'Schaden (${extra.damageType}):',
            for (final modifier in extra.modifiers) '$modifier',
            'Summe: ${Modifier.sum(extra.modifiers)}',
            if (extra.damageEffect case final effect?)
              '${effect.label} gegen ${extra.damageType}: '
                  '${extra.rolled} → ${extra.damage}',
          ],
          if (event.extraDamage.isNotEmpty) 'Gesamtschaden: ${event.damage}',
          if (event.tempHpAbsorbed > 0)
            'Von temporären TP abgefangen: ${event.tempHpAbsorbed}',
        ],
      ),
      LogSpan(
        ' Schaden ${event.critical ? 'kritisch ' : ''}getroffen'
        '${effects.isEmpty ? '' : ' (${effects.join(', ')})'}',
      ),
    ]);
  }

  LogLine _initiative(InitiativeEvent event) {
    return LogLine([
      const LogSpan('Initiative: '),
      for (final (index, entry) in event.entries.indexed) ...[
        LogSpan('${index == 0 ? '' : ', '}${entry.name} '),
        LogSpan(
          '${entry.roll.total}',
          details: [
            ...rollDetails(entry.roll),
            ?_exhaustionReason(entry.disadvantageFromExhaustion),
          ],
        ),
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
      if (event.tempHpBefore != event.tempHpAfter)
        'Temporäre TP: ${event.tempHpBefore} → ${event.tempHpAfter}',
      'Trefferpunkte: ${event.hpBefore} → ${event.hpAfter} '
          '(Maximum ${event.maxHp})',
      if (event.effective + event.tempHpBefore - event.tempHpAfter !=
          event.adjusted)
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

  LogLine _tempHp(TempHpEvent event) {
    final source = event.source == null ? '' : ' (${event.source})';
    final String text;
    if (event.amount == 0) {
      text = '${event.name} verliert ${event.tempHpBefore} temporäre TP';
    } else if (event.kept) {
      text =
          '${event.name} behält ${event.tempHpAfter} temporäre TP '
          'statt ${event.amount}$source';
    } else {
      text = '${event.name} erhält ${event.amount} temporäre TP$source';
    }
    return LogLine([LogSpan(text)]);
  }

  /// `D&D 5e (2014)` for a stored ruleset id; the id itself if this app
  /// version does not know it.
  String _rulesetLabel(String id) => Ruleset.byId(id)?.label ?? id;

  LogLine _rest(RestEvent event) {
    final ruleset = Ruleset.byId(event.ruleset);
    final rulesetLine = 'Regelwerk: ${_rulesetLabel(event.ruleset)}';
    final short = event.kind == RestKind.short;

    if (event.blocker case final blocker?) {
      final reason = switch (blocker) {
        RestBlocker.dead => 'tot',
        RestBlocker.dying => 'liegt im Sterben',
        RestBlocker.tooFewHp => '${event.hpBefore} TP',
      };
      final minHp = ruleset == null
          ? null
          : short
          ? ruleset.minHpForShortRest
          : ruleset.minHpForLongRest;
      return LogLine([
        LogSpan('${event.name} hat keinen Nutzen von der '),
        LogSpan(
          short ? 'kurzen Rast' : 'langen Rast',
          details: [
            rulesetLine,
            if (blocker == RestBlocker.tooFewHp && minHp != null)
              'Voraussetzung: mindestens $minHp TP',
          ],
        ),
        LogSpan(' ($reason)'),
      ]);
    }

    final summary =
        'TP ${event.hpAfter}/${event.maxHp}, '
        'Trefferwürfel ${event.hitDiceAfter}/${event.hitDiceTotal}';
    final slotLines = [
      if (event.slotsRegained > 0)
        'Zauberplätze zurück: ${event.slotsRegained}',
      if (event.pactSlotsRegained > 0)
        'Paktmagie zurück: ${event.pactSlotsRegained}',
    ];
    if (short) {
      return LogLine([
        LogSpan('${event.name} macht eine kurze Rast: '),
        LogSpan(summary, details: [rulesetLine, ...slotLines]),
      ]);
    }
    return LogLine([
      LogSpan('${event.name} beendet eine lange Rast: '),
      LogSpan(
        summary,
        details: [
          rulesetLine,
          'Trefferpunkte: ${event.hpBefore} → ${event.hpAfter} '
              '(Maximum ${event.maxHp})',
          if (event.tempHpBefore > 0) 'Temporäre TP: ${event.tempHpBefore} → 0',
          'Trefferwürfel übrig: ${event.hitDiceBefore} → '
              '${event.hitDiceAfter} von ${event.hitDiceTotal}',
          if (ruleset != null)
            'Zurück nach der langen Rast: ${ruleset.longRestHitDiceRule}',
          ...slotLines,
          if (event.exhaustionBefore != event.exhaustionAfter)
            'Erschöpfung: Stufe ${event.exhaustionBefore} → '
                '${event.exhaustionAfter}',
        ],
      ),
    ]);
  }

  LogLine _exhaustion(ExhaustionEvent event) {
    final ruleset = Ruleset.byId(event.ruleset);
    final details = [
      'Stufe: ${event.before} → ${event.after}',
      'Regelwerk: ${ruleset?.label ?? event.ruleset}',
      ...?ruleset?.exhaustionEffects(event.after),
    ];
    if (event.after == 0) {
      return LogLine([
        LogSpan('${event.name} ist nicht mehr '),
        LogSpan('erschöpft', details: details),
      ]);
    }
    final word = event.after > event.before ? 'erschöpft' : 'weniger erschöpft';
    return LogLine([
      LogSpan('${event.name} ist $word: '),
      LogSpan('Stufe ${event.after}', details: details),
    ]);
  }

  LogLine _spellSlot(SpellSlotEvent event) {
    final slot =
        '${event.pact ? 'Paktmagie-Platz' : 'Zauberplatz'} '
        'des ${event.level}. Grades';
    final verb = switch (event.change) {
      SlotChange.used => 'verbraucht einen $slot',
      SlotChange.restored => 'erhält einen $slot zurück',
    };
    return LogLine([
      LogSpan(
        '${event.name} $verb (${event.remaining} von ${event.total} übrig)',
      ),
    ]);
  }

  LogLine _hitDie(HitDieEvent event) {
    final effective = event.hpAfter - event.hpBefore;
    return LogLine([
      LogSpan('${event.name} gibt einen Trefferwürfel aus und wird um '),
      LogSpan(
        '${event.healing}',
        details: [
          ...rollDetails(event.roll),
          if (event.healing != event.roll.total)
            'Mindestens ${event.healing} TP nach '
                '${_rulesetLabel(event.ruleset)}',
          'Trefferpunkte: ${event.hpBefore} → ${event.hpAfter} '
              '(Maximum ${event.maxHp})',
          if (effective != event.healing) 'Davon wirksam: $effective',
          'Trefferwürfel übrig: ${event.hitDiceLeft} von ${event.hitDiceTotal}',
        ],
      ),
      const LogSpan(' TP geheilt'),
    ]);
  }

  /// `vergiftet` for `poisoned`; the stored name itself if this app version
  /// does not know the condition.
  String _conditionWord(String name) => name == exhaustionCondition
      ? 'erschöpft'
      : Condition.fromName(name)?.label.toLowerCase() ?? name;

  /// Detail line for disadvantage from exhaustion [level]; null without.
  String? _exhaustionReason(int? level) =>
      level == null ? null : 'Nachteil: erschöpft (Stufe $level)';

  LogLine _condition(ConditionEvent event) {
    final word = _conditionWord(event.condition);
    final rounds = event.rounds;
    return LogLine([
      LogSpan(switch (event.change) {
        EffectChange.added =>
          '${event.name} ist jetzt $word'
              '${rounds == null ? '' : ' ($rounds ${rounds == 1 ? 'Runde' : 'Runden'})'}',
        EffectChange.removed => '${event.name} ist nicht mehr $word',
        EffectChange.expired =>
          '${event.name} ist nicht mehr $word (Dauer abgelaufen)',
      }),
    ]);
  }

  LogLine _buff(BuffEvent event) {
    final rounds = event.rounds;
    final notes = [
      ...describeBuffEffects(
        attackBonus: event.attackBonus,
        armorClassBonus: event.armorClassBonus,
        damageBonus: event.damageBonus,
        damageType: event.damageType,
        saveBonus: event.saveBonus,
      ),
      if (rounds != null) '$rounds ${rounds == 1 ? 'Runde' : 'Runden'}',
    ];
    return LogLine([
      LogSpan(switch (event.change) {
        EffectChange.added =>
          '${event.name} erhält ${event.buff}'
              '${notes.isEmpty ? '' : ' (${notes.join(', ')})'}',
        EffectChange.removed => '${event.buff} endet bei ${event.name}',
        EffectChange.expired =>
          '${event.buff} endet bei ${event.name} (Dauer abgelaufen)',
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
          ?_exhaustionReason(event.disadvantageFromExhaustion),
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
