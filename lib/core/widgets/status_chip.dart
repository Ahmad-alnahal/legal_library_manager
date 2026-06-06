import 'package:flutter/material.dart';

import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';
import '../theme/app_status_colors.dart';

/// A small status pill using a [StatusColor] foreground/background pair.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.status});

  final String label;
  final StatusColor status;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: status.background,
        borderRadius: AppRadii.control,
      ),
      child: Text(
        label,
        style: text.labelMedium?.copyWith(
          color: status.foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
