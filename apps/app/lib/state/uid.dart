import 'dart:math';

final _rng = Random();
var _counter = 0;

/// A new item uid, unique across calls in this session (a counter) and very
/// likely across tabs and devices (the clock and a random suffix). Never
/// derived from a clock alone: the web clock only ticks in milliseconds, so
/// two creators in one tick would collide.
String newUid({String prefix = 'davdart'}) {
  final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
  final n = (_counter++).toRadixString(36);
  final r = _rng.nextInt(1 << 24).toRadixString(36);
  return '$prefix-$micros-$n$r';
}
