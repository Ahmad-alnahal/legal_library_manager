import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_status_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_panel.dart';
import '../../../../core/widgets/page_header.dart';
import '../../../../core/widgets/screen_container.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../managed_copy/domain/entities/copy_roots_setup_report.dart';
import '../../../managed_copy/domain/services/copy_root_picker.dart';
import '../../../managed_copy/presentation/bloc/copy_settings_bloc.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          getIt<CopySettingsBloc>()..add(const CopySettingsStarted()),
      child: const _SettingsBody(),
    );
  }
}

class _SettingsBody extends StatelessWidget {
  const _SettingsBody();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocListener<CopySettingsBloc, CopySettingsState>(
      listenWhen: (a, b) => a.sequence != b.sequence && b.messageKey != null,
      listener: (context, state) {
        final text = switch (state.messageKey) {
          'saved' => 'تم حفظ مواقع المكتبة المدارة والنسخ الاحتياطي بأمان.',
          'choose_both' => 'اختر مجلدي المكتبة المدارة والنسخ الاحتياطي.',
          'unsafe_overlap' =>
            'يجب أن تكون المجلدات منفصلة عن بعضها وعن قاعدة البيانات.',
          'recreated' =>
            'تمت إعادة إنشاء المجلد المفقود بأمان دون أي تغيير على الملفات الحالية.',
          'recreate_unsafe' =>
            'تعذّرت إعادة الإنشاء: يجب أن يكون المجلد منفصلًا عن المجلدات الأخرى وقاعدة البيانات ومجلدات المصدر.',
          'recreate_invalid' =>
            'تعذّرت إعادة الإنشاء: مسار المجلد المُهيأ غير صالح.',
          'recreate_failed' =>
            'تعذّرت إعادة إنشاء المجلد. يبقى الإعداد بحاجة إلى الانتباه دون أي تغيير على الملفات الحالية.',
          'defaults_applied' =>
            'تم تطبيق المجلدات الافتراضية لمرجعي. الملفات المدارة والنسخ الاحتياطية السابقة في مواقعها الأصلية.',
          'defaults_resolution_failed' =>
            'تعذّر تحديد مجلد المستندات. تحقق من صلاحيات النظام.',
          'defaults_creation_failed' =>
            'تعذّر إنشاء المجلدات الافتراضية. تحقق من المساحة المتاحة وصلاحيات الكتابة.',
          _ => 'تعذّر اعتماد المجلد المحدد. اختر مجلدًا موجودًا وآمنًا.',
        };
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(text)));
      },
      child: ScreenContainer(
        children: [
          PageHeader(
            title: l10n.settingsTitle,
            subtitle: l10n.settingsSubtitle,
          ),
          const SizedBox(height: AppSpacing.lg),
          const _CopyOnlyPolicyPanel(),
          const SizedBox(height: AppSpacing.lg),
          const _CopyLocationsPanel(),
        ],
      ),
    );
  }
}

class _CopyOnlyPolicyPanel extends StatelessWidget {
  const _CopyOnlyPolicyPanel();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const accent = AppStatusColors.teal;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: accent.background,
        borderRadius: AppRadii.card,
        border: Border.all(color: accent.foreground.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, color: accent.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsCopyPolicyTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(l10n.settingsCopyPolicyBody),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.settingsCopyPolicyActive,
                  style: TextStyle(color: accent.foreground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyLocationsPanel extends StatelessWidget {
  const _CopyLocationsPanel();

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: BlocBuilder<CopySettingsBloc, CopySettingsState>(
        builder: (context, state) {
          if (state.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          final bloc = context.read<CopySettingsBloc>();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  const Icon(
                    Icons.folder_copy_outlined,
                    color: AppColors.accentTeal,
                  ),
                  Text(
                    'مواقع النسخ الآمن',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'تُحفظ ملفات PDF المدارة داخل مجلد files، وتبقى النسخ الاحتياطية في مجلد منفصل. '
                'يجهّز التطبيق هذه المواقع تلقائيًا، ويمكن تغييرها كخيار متقدم.',
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'تغيير المواقع لا ينقل الملفات المدارة أو النسخ الاحتياطية السابقة؛ تبقى في مكانها الحالي.',
              ),
              if (state.requiresAttention) ...[
                const SizedBox(height: AppSpacing.md),
                const _AttentionBanner(),
              ],
              const SizedBox(height: AppSpacing.lg),
              _LocationRow(
                title: 'جذر المكتبة المدارة',
                value: state.managedRoot,
                status: state.managedStatus,
                icon: Icons.library_books_outlined,
                enabled: !state.busy,
                onChoose: () => bloc.add(
                  const CopyRootSelectionRequested(CopyRootKind.managedLibrary),
                ),
                onRecreate: state.managedStatus == CopyRootStatus.missing
                    ? () => _confirmAndRecreate(
                        context,
                        bloc,
                        CopyRootKind.managedLibrary,
                      )
                    : null,
              ),
              const Divider(height: AppSpacing.xl),
              _LocationRow(
                title: 'مجلد النسخ الاحتياطي لقاعدة البيانات',
                value: state.backupRoot,
                status: state.backupStatus,
                icon: Icons.backup_outlined,
                enabled: !state.busy,
                onChoose: () => bloc.add(
                  const CopyRootSelectionRequested(CopyRootKind.databaseBackup),
                ),
                onRecreate: state.backupStatus == CopyRootStatus.missing
                    ? () => _confirmAndRecreate(
                        context,
                        bloc,
                        CopyRootKind.databaseBackup,
                      )
                    : null,
              ),
              const Divider(height: AppSpacing.xl),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppSecondaryButton(
                  label: 'استخدام المجلدات الافتراضية',
                  icon: Icons.restore_outlined,
                  onPressed: !state.busy
                      ? () => _confirmResetToDefaults(context, bloc)
                      : null,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'تغيير المسارات إلى الافتراضي لا ينقل الملفات المدارة أو النسخ '
                'الاحتياطية من مواقعها الحالية.',
                style: TextStyle(fontSize: 12),
              ),
              if (state.busy) ...[
                const SizedBox(height: AppSpacing.md),
                const LinearProgressIndicator(),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Asks the user to confirm before any directory is created, then dispatches
/// the explicit repair request (M8.5). Creation never happens without this
/// confirmed click.
Future<void> _confirmAndRecreate(
  BuildContext context,
  CopySettingsBloc bloc,
  CopyRootKind kind,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('إعادة إنشاء المجلد'),
      content: const Text(
        'سيتم إنشاء المجلد المفقود في نفس المسار المُهيأ فقط، بعد التحقق من سلامته. '
        'لا يتم نقل أو نسخ أو تعديل أو حذف أي ملفات موجودة.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('إعادة الإنشاء'),
        ),
      ],
    ),
  );
  if (confirmed == true && !bloc.isClosed) {
    bloc.add(CopyRootRepairRequested(kind));
  }
}

/// Asks the user to confirm before resetting both roots to the MARJIY defaults
/// (M8.6 Part A). Warns clearly that files are never moved.
Future<void> _confirmResetToDefaults(
  BuildContext context,
  CopySettingsBloc bloc,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('استخدام المجلدات الافتراضية'),
      content: const Text(
        'سيتم تعيين مجلدَي المكتبة المدارة والنسخ الاحتياطي إلى المواقع '
        'الافتراضية لمرجعي داخل مجلد المستندات.\n\n'
        'تنبيه: هذا لا ينقل الملفات المدارة أو النسخ الاحتياطية السابقة؛ '
        'تبقى في مواقعها الحالية ولا يتأثر أي ملف موجود.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('تطبيق الافتراضي'),
        ),
      ],
    ),
  );
  if (confirmed == true && !bloc.isClosed) {
    bloc.add(const CopyRootsResetToDefaultRequested());
  }
}

class _AttentionBanner extends StatelessWidget {
  const _AttentionBanner();

  @override
  Widget build(BuildContext context) {
    const accent = AppStatusColors.warning;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: accent.background,
        borderRadius: AppRadii.card,
        border: Border.all(color: accent.foreground.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_outlined, color: accent.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'يتطلب إعداد مواقع النسخ الآمن انتباهك. يبقى النسخ إلى المكتبة المدارة '
              'متوقفًا حتى يكتمل الإعداد، دون أي تأثير على الملفات الحالية.',
              style: TextStyle(color: accent.foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.title,
    required this.value,
    required this.status,
    required this.icon,
    required this.enabled,
    required this.onChoose,
    this.onRecreate,
  });

  final String title;
  final String? value;
  final CopyRootStatus status;
  final IconData icon;
  final bool enabled;
  final VoidCallback onChoose;

  /// Non-null only when this configured root is missing/inaccessible. Renders
  /// the explicit "إعادة إنشاء المجلد" action beside the missing folder.
  final VoidCallback? onRecreate;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: title,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final details = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: AppSpacing.xs),
                    SelectableText(value ?? 'لم يتم الاختيار بعد'),
                    const SizedBox(height: AppSpacing.xs),
                    _StatusChip(status: status),
                    if (onRecreate != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: AppPrimaryButton(
                          label: 'إعادة إنشاء المجلد',
                          icon: Icons.create_new_folder_outlined,
                          onPressed: enabled ? onRecreate : null,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
          final button = AppSecondaryButton(
            label: value == null ? 'اختيار' : 'تغيير',
            icon: Icons.folder_open_outlined,
            onPressed: enabled ? onChoose : null,
          );
          if (constraints.maxWidth < 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: button,
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: details),
              const SizedBox(width: AppSpacing.md),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final CopyRootStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      CopyRootStatus.automatic => ('مُهيأ تلقائيًا', AppStatusColors.success),
      CopyRootStatus.custom => ('موقع مخصص', AppStatusColors.info),
      CopyRootStatus.missing => (
        'المجلد غير متاح — يتطلب الانتباه',
        AppStatusColors.warning,
      ),
      CopyRootStatus.notConfigured => (
        'غير مُهيأ بعد',
        AppStatusColors.neutral,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.background,
        borderRadius: AppRadii.control,
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: color.foreground),
      ),
    );
  }
}
