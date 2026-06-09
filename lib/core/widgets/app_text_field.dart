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
    this.controller,
    this.focusNode,
    this.onChanged,
    this.suffixIcon,
    this.textInputAction,
  });

  final String? hintText;
  final IconData? prefixIcon;
  final bool enabled;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final Widget? suffixIcon;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextField(
      enabled: enabled,
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      textInputAction: textInputAction,
      decoration: InputDecoration(
        hintText: hintText,
        suffixIcon: suffixIcon,
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, size: 18, color: AppColors.textSecondary),
      ),
    );
  }
}
