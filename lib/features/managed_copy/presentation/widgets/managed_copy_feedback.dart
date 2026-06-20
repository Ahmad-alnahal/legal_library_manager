import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/managed_copy_error.dart';
import '../bloc/managed_copy_bloc.dart';

class ManagedCopyFeedbackListener extends StatelessWidget {
  const ManagedCopyFeedbackListener({
    super.key,
    required this.child,
    this.onSuccess,
  });

  final Widget child;
  final VoidCallback? onSuccess;

  @override
  Widget build(BuildContext context) {
    return BlocListener<ManagedCopyBloc, ManagedCopyState>(
      listenWhen: (a, b) => a.sequence != b.sequence,
      listener: (context, state) {
        final message = switch (state.status) {
          ManagedCopyStatus.success => 'تم نسخ المستند والتحقق منه بنجاح.',
          ManagedCopyStatus.recovery =>
            'تم إنشاء الملف، لكن يلزم التحقق من حالة قاعدة البيانات قبل إعادة المحاولة.',
          ManagedCopyStatus.blocked => _blockedMessage(state.error),
          ManagedCopyStatus.failed => _failedMessage(state.error),
          _ => null,
        };
        if (message != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(message)));
        }
        final shouldRefresh =
            state.status == ManagedCopyStatus.success ||
            (state.status == ManagedCopyStatus.blocked &&
                (state.error == ManagedCopyError.alreadyCopied ||
                    state.error == ManagedCopyError.restoredFromDisk));
        if (shouldRefresh) onSuccess?.call();
      },
      child: child,
    );
  }

  String _blockedMessage(ManagedCopyError? error) => switch (error) {
    ManagedCopyError.rootsNotConfigured =>
      'اضبط مجلدي المكتبة المدارة والنسخ الاحتياطي من الإعدادات أولًا.',
    ManagedCopyError.ambiguousSource =>
      'يوجد أكثر من ملف مصدر صالح. حدّد الملف المفضل للنسخ أولًا.',
    ManagedCopyError.noEligibleSource =>
      'لا يوجد ملف PDF مصدري سليم صالح للنسخ.',
    ManagedCopyError.alreadyCopied =>
      'هذا المستند منسوخ بالفعل إلى المكتبة المدارة.',
    ManagedCopyError.restoredFromDisk =>
      'تم اكتشاف الملف المدار على القرص والتحقق من صحته. استُعيد المستند إلى المكتبة.',
    ManagedCopyError.notClassified =>
      'يجب اعتماد تصنيف المستند قبل نسخه إلى المكتبة المدارة.',
    ManagedCopyError.missingSource => 'تعذّر العثور على الملف المصدري المسجل.',
    ManagedCopyError.unsupportedSource =>
      'الملف المصدري المحدد ليس ملف PDF صالحًا.',
    ManagedCopyError.rootsMissing =>
      'بعض مجلدات التخزين غير متاحة وتحتاج إلى الانتباه. أعد إنشاء المجلد المفقود من الإعدادات قبل النسخ.',
    ManagedCopyError.unsafeRoots =>
      'تعذّر النسخ لأن أحد مسارات التخزين غير آمن أو يتداخل مع مسار محمي.',
    _ => 'تعذّر بدء النسخ بأمان.',
  };

  String _failedMessage(ManagedCopyError? error) => switch (error) {
    ManagedCopyError.backupFailed =>
      'تعذّر إنشاء نسخة احتياطية موثوقة، لذلك لم يبدأ نسخ الملف.',
    ManagedCopyError.targetConflict =>
      'يوجد ملف في موقع النسخة المدارة لا يمكن إزالته. تحقق من صلاحيات المجلد ثم أعد المحاولة.',
    ManagedCopyError.temporaryTargetConflict =>
      'يوجد ملف مؤقت سابق يحتاج إلى المراجعة قبل إعادة النسخ.',
    ManagedCopyError.hashFailed =>
      'تعذّر التحقق من بصمة الملف. تحقق من أن الملف متاح وغير مستخدم من برنامج آخر ثم أعد المحاولة.',
    ManagedCopyError.hashMismatch =>
      'فشل التحقق من التطابق: الملف الموجود أو النسخة الجديدة لا تطابق بصمة المصدر المسجلة. سيحاول مرجعي استبدال النسخة المدارة عند إعادة النسخ.',
    ManagedCopyError.copyFailed =>
      'تعذّر نسخ الملف إلى المكتبة المدارة. تحقق من صلاحيات المجلد والمساحة المتاحة ثم أعد المحاولة.',
    ManagedCopyError.finalizationFailed =>
      'تم نسخ الملف مؤقتًا لكن تعذّر تثبيت النسخة النهائية في المكتبة المدارة. أغلق أي برنامج يستخدم الملف ثم أعد المحاولة.',
    ManagedCopyError.databasePersistenceFailed =>
      'تم إنشاء الملف والتحقق منه، لكن تعذّر حفظ حالته في قاعدة البيانات. أعد فتح المستند أو أعد المحاولة بعد التحديث.',
    ManagedCopyError.fileSizeUnreadable =>
      'تم إنشاء النسخة لكن تعذّر قراءة حجم الملف النهائي. تحقق من صلاحيات الملف ثم أعد المحاولة.',
    ManagedCopyError.unexpectedFailure =>
      'تعذّرت مطابقة حالة النسخة المدارة مع السجل. أعد فتح المستند ثم أعد المحاولة.',
    _ => 'فشل النسخ بأمان. لم تتأثر الملفات الأصلية.',
  };
}
