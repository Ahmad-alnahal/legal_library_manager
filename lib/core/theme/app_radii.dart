import 'package:flutter/widgets.dart';

/// Centralized border-radius tokens.
///
/// Deliberately modest radii — cards and panels use small rounding, never the
/// oversized pill/blob rounding of marketing layouts.
abstract final class AppRadii {
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;

  static const BorderRadius card = BorderRadius.all(Radius.circular(md));
  static const BorderRadius panel = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius control = BorderRadius.all(Radius.circular(sm));
}
