import 'package:flutter/material.dart';

/// M3 motion tokens (easing and duration pairs). Keep durations here so no
/// widget invents its own magic number.
abstract class AppMotion {
  static const Duration short = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 300);

  /// Cross-fade used instead of slides when Reduce Motion is on.
  static const Duration reducedFade = Duration(milliseconds: 150);

  static const Curve enter = Easing.emphasizedDecelerate;
  static const Curve exit = Easing.emphasizedAccelerate;
}
