import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/mark_ready_for_export_bloc.dart';

class MarkReadyForExportFeedbackListener extends StatelessWidget {
  const MarkReadyForExportFeedbackListener({
    super.key,
    required this.child,
    this.onSuccess,
  });

  final Widget child;
  final VoidCallback? onSuccess;

  @override
  Widget build(BuildContext context) {
    return BlocListener<MarkReadyForExportBloc, MarkReadyForExportState>(
      listenWhen: (a, b) => a.sequence != b.sequence,
      listener: (context, state) {
        final message = switch (state.status) {
          MarkReadyForExportStatus.success => 'تم تعيين المستند جاهزاً للتصدير',
          MarkReadyForExportStatus.ineligible =>
            'غير مؤهل للتصدير: ${state.ineligibleReasons.join('، ')}',
          MarkReadyForExportStatus.failed =>
            'تعذّر إكمال العملية. لم تتأثر الملفات الأصلية.',
          _ => null,
        };
        if (message != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(message)));
        }
        if (state.status == MarkReadyForExportStatus.success) onSuccess?.call();
      },
      child: child,
    );
  }
}
