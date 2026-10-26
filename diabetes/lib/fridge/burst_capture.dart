import 'dart:async';

import 'package:camera/camera.dart' show XFile;
import 'package:flutter/foundation.dart';

import 'photo_quality.dart';

/// If the first frame alone takes longer than this, bursts are too slow on
/// this platform.
const slowFrameLimit = Duration(milliseconds: 1500);

/// Session-wide memory of whether bursts are too slow here.
abstract final class BurstCapture {
  /// Set once a first frame took longer than [slowFrameLimit]; from then on
  /// [captureSharpest] takes single frames. Reset only in tests.
  static bool tooSlow = false;
}

/// The sharpest frame of a burst.
class BurstResult {
  const BurstResult({
    required this.bytes,
    required this.scores,
    required this.elapsed,
  });

  /// The sharpest frame's bytes.
  final Uint8List bytes;

  /// [sharpnessScore] of every frame, in capture order. Empty when only one
  /// frame was taken (nothing to compare it with).
  final List<double> scores;

  /// How long taking the pictures took.
  final Duration elapsed;

  int get frames => scores.isEmpty ? 1 : scores.length;
}

/// Takes up to [frames] pictures back to back and returns the sharpest. Stops
/// early once [budget] has passed, but always keeps one. [clock] is a
/// monotonic time source (tests fake it).
Future<BurstResult> captureSharpest(
  Future<XFile> Function() takePicture, {
  int frames = 4,
  Duration budget = const Duration(milliseconds: 800),
  Duration Function()? clock,
}) async {
  final Duration Function() now;
  if (clock != null) {
    now = clock;
  } else {
    final watch = Stopwatch()..start();
    now = () => watch.elapsed;
  }
  final start = now();
  final wanted = BurstCapture.tooSlow ? 1 : frames;

  final shots = <Uint8List>[];
  final scoring = <Future<double>>[];
  for (var i = 0; i < wanted; i++) {
    if (i > 0 && now() - start > budget) break;
    final before = now();
    final file = await takePicture();
    final took = now() - before;
    final bytes = await file.readAsBytes();
    shots.add(bytes);
    // Scored while the next picture is being taken.
    if (wanted > 1) scoring.add(compute(sharpnessScore, bytes));
    if (i == 0 && took > slowFrameLimit) {
      BurstCapture.tooSlow = true;
      break;
    }
  }
  final elapsed = now() - start;

  if (shots.length == 1) {
    // Not worth scoring a lone frame; drop the pending score.
    unawaited(Future.wait(scoring));
    return BurstResult(bytes: shots.single, scores: const [], elapsed: elapsed);
  }

  final scores = await Future.wait(scoring);
  var best = 0;
  for (var i = 1; i < scores.length; i++) {
    if (scores[i] > scores[best]) best = i;
  }
  return BurstResult(bytes: shots[best], scores: scores, elapsed: elapsed);
}
