import 'package:flutter/widgets.dart';

/// True when the user's text size is above 130%, the point where compact
/// layouts should switch to roomier ones (WCAG 1.4.4).
bool useLargeTextLayout(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(14) / 14 > 1.3;
