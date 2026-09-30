import 'dart:math';

/// Produces a shuffled copy without mutating the Firestore/provider list that
/// supplied it. Call once per page session and retain the returned list.
List<T> shuffledSessionCopy<T>(Iterable<T> items, Random random) {
  final shuffled = List<T>.of(items);
  shuffled.shuffle(random);
  return shuffled;
}
