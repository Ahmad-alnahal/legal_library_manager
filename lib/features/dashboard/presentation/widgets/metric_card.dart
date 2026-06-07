import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_panel.dart';

/// A single operational metric (label, value, status-tinted icon).
///
/// Values are passed in as pre-formatted strings; the card renders no logic.
/// The header adapts to the available width: a label/icon row at normal widths,
/// stacking the icon above the label only when the card is unusually narrow so
/// the fixed-size icon badge can never overflow. The large value scales down to
/// fit rather than clipping or overflowing.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.status,
  });

  final String label;
  final String value;
  final IconData icon;
  final StatusColor status;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return AppPanel(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Inner content width (the panel padding is already excluded here).
          // Below this the label + fixed icon badge cannot sit side by side
          // comfortably, so the header stacks instead.
          final bool stackHeader = constraints.maxWidth < 120;

          final Widget labelText = Text(
            label,
            style: text.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (stackHeader) ...[
                _IconBadge(icon: icon, status: status),
                const SizedBox(height: AppSpacing.sm),
                labelText,
              ] else
                Row(
                  children: [
                    Expanded(child: labelText),
                    const SizedBox(width: AppSpacing.sm),
                    _IconBadge(icon: icon, status: status),
                  ],
                ),
              const SizedBox(height: AppSpacing.md),
              // Scale the value down to fit narrow cards instead of clipping or
              // overflowing; at normal widths it renders at its natural size.
              SizedBox(
                width: double.infinity,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: AppTypography.metricValue,
                      maxLines: 1,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The status-tinted icon badge shown on a metric card.
class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.status});

  final IconData icon;
  final StatusColor status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: status.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 18, color: status.foreground),
    );
  }
}
