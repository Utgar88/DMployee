/// A dice expression such as `2d6+3`: [count] dice with [sides] faces each,
/// plus a flat [modifier].
class DiceExpression {
  DiceExpression({
    required this.count,
    required this.sides,
    this.modifier = 0,
  }) {
    if (count < 1) {
      throw ArgumentError.value(count, 'count', 'must be at least 1');
    }
    if (sides < 2) {
      throw ArgumentError.value(sides, 'sides', 'must be at least 2');
    }
  }

  /// Parses standard dice notation.
  ///
  /// Accepts `d` or the German `W` as separator, any letter case and
  /// arbitrary whitespace: `2d6+3`, `d20`, `1W8-1`.
  /// Throws a [FormatException] for anything else.
  factory DiceExpression.parse(String input) {
    final normalized = input.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final match = _pattern.firstMatch(normalized);
    if (match == null) {
      throw FormatException('Not a valid dice expression', input);
    }

    final count = match.group(1)!.isEmpty ? 1 : int.parse(match.group(1)!);
    final sides = int.parse(match.group(2)!);
    final modifier = match.group(3) == null ? 0 : int.parse(match.group(3)!);

    if (count < 1) {
      throw FormatException('Dice count must be at least 1', input);
    }
    if (sides < 2) {
      throw FormatException('A die needs at least 2 sides', input);
    }
    return DiceExpression(count: count, sides: sides, modifier: modifier);
  }

  static final _pattern = RegExp(r'^(\d*)[dw](\d+)([+-]\d+)?$');

  final int count;
  final int sides;
  final int modifier;

  /// Lowest possible total.
  int get min => count + modifier;

  /// Highest possible total.
  int get max => count * sides + modifier;

  @override
  String toString() {
    final sign = modifier > 0 ? '+' : '';
    return '${count}d$sides${modifier == 0 ? '' : '$sign$modifier'}';
  }

  @override
  bool operator ==(Object other) =>
      other is DiceExpression &&
      other.count == count &&
      other.sides == sides &&
      other.modifier == modifier;

  @override
  int get hashCode => Object.hash(count, sides, modifier);
}
