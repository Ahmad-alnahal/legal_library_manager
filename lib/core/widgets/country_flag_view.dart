// lib/core/widgets/country_flag_view.dart

import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

/// A small, reusable presentation widget that renders a bundled, offline
/// country flag from a database country code.
///
/// Behaviour:
/// - Accepts a lowercase database country key (e.g. `ps`, `jo`) and normalizes
///   it safely for the underlying [country_flags] package.
/// - Renders a compact rounded rectangular flag from the package's bundled SVG
///   assets — fully offline, never downloaded at runtime, never an emoji flag.
/// - Uses fixed [width]/[height] so flags never shift surrounding layout.
/// - Renders a neutral fallback box for empty/invalid/unsupported codes instead
///   of throwing.
///
/// No flag bytes or asset paths are ever persisted; rendering is derived purely
/// from the code.
class CountryFlagView extends StatelessWidget {
  const CountryFlagView({
    required this.countryCode,
    this.width = 24,
    this.height = 16,
    this.borderRadius = 2,
    super.key,
  });

  /// The database country key (lowercase ISO 3166-1 alpha-2, e.g. `ps`).
  final String countryCode;

  /// Fixed flag width in logical pixels.
  final double width;

  /// Fixed flag height in logical pixels.
  final double height;

  /// Corner radius applied to the rendered flag.
  final double borderRadius;

  /// Normalizes a raw database code to the package's expected form, or returns
  /// `null` when the code is not a supported ISO 3166-1 alpha-2 code.
  static String? _resolve(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.length != 2) return null;
    final String upper = trimmed.toUpperCase();
    // FlagCode resolves only supported codes; unsupported codes yield null.
    return FlagCode.fromCountryCode(upper) == null ? null : upper;
  }

  @override
  Widget build(BuildContext context) {
    final String? resolved = _resolve(countryCode);
    if (resolved == null) {
      return _FlagFallback(
        width: width,
        height: height,
        borderRadius: borderRadius,
      );
    }
    return SizedBox(
      width: width,
      height: height,
      child: CountryFlag.fromCountryCode(
        resolved,
        theme: ImageTheme(
          width: width,
          height: height,
          shape: RoundedRectangle(borderRadius),
        ),
      ),
    );
  }
}

/// Neutral, layout-stable placeholder used when a code cannot be rendered.
class _FlagFallback extends StatelessWidget {
  const _FlagFallback({
    required this.width,
    required this.height,
    required this.borderRadius,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final Color border = Theme.of(context).dividerColor;
    return SizedBox(
      key: const Key('countryFlagView_fallback'),
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFEEEEEE),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: border, width: 0.5),
        ),
        child: Center(
          child: Icon(
            Icons.flag_outlined,
            size: height * 0.7,
            color: const Color(0xFF9E9E9E),
          ),
        ),
      ),
    );
  }
}
