/// A flat bonus or penalty with a named source, e.g. `+5 Stärke`.
///
/// The [label] is what the log later shows as the origin of the value.
class Modifier {
  const Modifier(this.label, this.value);

  factory Modifier.fromJson(Map<String, Object?> json) =>
      Modifier(json['label']! as String, json['value']! as int);

  final String label;
  final int value;

  Map<String, Object?> toJson() => {'label': label, 'value': value};

  /// Sum of all [modifiers].
  static int sum(Iterable<Modifier> modifiers) =>
      modifiers.fold(0, (total, modifier) => total + modifier.value);

  @override
  String toString() => '${value >= 0 ? '+' : ''}$value $label';

  @override
  bool operator ==(Object other) =>
      other is Modifier && other.label == label && other.value == value;

  @override
  int get hashCode => Object.hash(label, value);
}
