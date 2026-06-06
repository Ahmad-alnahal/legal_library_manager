import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Standard scrollable, padded body for a section screen.
///
/// Scrolling keeps content usable at the shortest supported height (800 px)
/// without overflow, while a max content width keeps line lengths comfortable
/// on wide monitors.
class ScreenContainer extends StatelessWidget {
  const ScreenContainer({
    super.key,
    required this.children,
    this.maxContentWidth = 1320,
  });

  final List<Widget> children;
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.pagePadding),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}
