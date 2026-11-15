import 'dart:math';

/// Test double for [Random]: returns the given die faces in order.
///
/// `FixedRandom([4, 17])` makes the first die show 4 and the second show 17.
/// Throws if more dice are rolled than faces were provided, or if a face does
/// not fit the die being rolled.
class FixedRandom implements Random {
  FixedRandom(List<int> faces) : _faces = List.of(faces);

  final List<int> _faces;
  int _index = 0;

  @override
  int nextInt(int max) {
    if (_index >= _faces.length) {
      throw StateError('FixedRandom: no more faces left');
    }
    final face = _faces[_index++];
    if (face < 1 || face > max) {
      throw StateError('FixedRandom: face $face does not fit a d$max');
    }
    return face - 1;
  }

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();
}
