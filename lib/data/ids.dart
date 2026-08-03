import 'dart:math';

/// Identifiers minted on the device.
///
/// A photo taken in a dead zone needs an id the moment it is taken — the
/// server cannot supply one, and the job record has to reference it before
/// anything is uploaded. Time-ordered so a debug listing reads chronologically,
/// with random suffix so two devices (or two photos in the same microsecond)
/// cannot collide.
class IdGenerator {
  IdGenerator({Random? random, DateTime Function()? now})
    : _random = random ?? Random(),
      _now = now ?? DateTime.now;

  final Random _random;
  final DateTime Function() _now;

  int _counter = 0;

  String next([String prefix = 'id']) {
    // Milliseconds, not microseconds: on the web an int is a double and
    // microsecond precision is not available, so anything built on it works on
    // five platforms and throws on the sixth. A per-process counter restores
    // the uniqueness that the coarser clock gives up.
    final stamp = _now().toUtc().millisecondsSinceEpoch.toRadixString(36);
    _counter = (_counter + 1) & 0xFFFFFF;
    final seq = _counter.toRadixString(36).padLeft(4, '0');
    // Random guards against two devices minting the same id in the same
    // millisecond; the counter alone only protects within one process.
    final suffix = _random.nextInt(0xFFFFFF).toRadixString(36).padLeft(4, '0');
    return '$prefix-$stamp-$seq$suffix';
  }
}

/// The default generator. Injectable everywhere it matters; this is the
/// convenience for production code paths.
final IdGenerator ids = IdGenerator();
