import 'package:flutter/material.dart';

import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status_colors.dart';

/// Visual tone for a [SafetyBanner].
enum SafetyBannerTone { info, success }

/// A prominent, non-dismissible banner used to communicate source-file safety
/// guarantees (copy-only policy, metadata-only duplicate handling, …).
class SafetyBanner extends StatelessWidget {
  const SafetyBanner({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.shield_outlined,
    this.tone = SafetyBannerTone.info,
  });

  final String title;
  final String message;
  final IconData icon;
  final SafetyBannerTone tone;

  StatusColor get _colors => switch (tone) {
    SafetyBannerTone.info => AppStatusColors.info,
    SafetyBannerTone.success => AppStatusColors.teal,
  };

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final StatusColor colors = _colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: AppRadii.card,
        border: Border.all(color: colors.foreground.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.foreground, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.titleMedium?.copyWith(color: colors.foreground),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(message, style: text.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
