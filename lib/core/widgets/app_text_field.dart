import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A read-only-friendly text input that uses the centralized input theme.
///
/// M1 screens use it for visual foundation only (no controllers/actions wired).
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.hintText,
    this.prefixIcon,
    this.enabled = true,
  });

  final String? hintText;
  final IconData? prefixIcon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      enabled: enabled,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, size: 18, color: AppColors.textSecondary),
      ),
    );
  }
}
