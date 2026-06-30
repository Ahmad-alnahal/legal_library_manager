import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/entities/legislation_relation.dart';
import '../../domain/entities/legislation_relation_input.dart';
import '../../domain/entities/legislation_relation_scope.dart';
import '../../domain/entities/legislation_relation_type.dart';
import '../bloc/legislation_relation_bloc.dart';
import '../bloc/legislation_relation_event.dart';
import '../bloc/legislation_relation_state.dart';
import 'legislation_document_picker_dialog.dart';
import 'relation_labels.dart';

/// Displays outgoing and incoming relations for a legislation document and
/// provides buttons to add or delete relations.
///
/// Manages its own [LegislationRelationBloc] lifecycle. Embed this widget
/// inside a parent that has [documentId] available.
class LegislationRelationsSection extends StatelessWidget {
  const LegislationRelationsSection({
    super.key,
    required this.documentId,
    required this.legislationDocumentTypeId,
  });

  final int documentId;
  final int? legislationDocumentTypeId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<LegislationRelationBloc>(
      create: (_) =>
          getIt<LegislationRelationBloc>()
            ..add(LegislationRelationsLoaded(documentId)),
      child: _RelationsSectionBody(
        documentId: documentId,
        legislationDocumentTypeId: legislationDocumentTypeId,
      ),
    );
  }
}

class _RelationsSectionBody extends StatelessWidget {
  const _RelationsSectionBody({
    required this.documentId,
    required this.legislationDocumentTypeId,
  });

  final int documentId;
  final int? legislationDocumentTypeId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final srcLabels = relationTypeSourceLabels(l10n);
    final tgtLabels = relationTypeTargetLabels(l10n);
    final scopeLabels = relationScopeLabels(l10n);

    return BlocBuilder<LegislationRelationBloc, LegislationRelationState>(
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.legislationRelationsSectionTitle,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: l10n.legislationRelationAddTooltip,
                    icon: const Icon(Icons.add),
                    onPressed: state.isLoading
                        ? null
                        : () => _showAddDialog(context, l10n),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    state.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (state.isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: LinearProgressIndicator(),
                ),
              if (state.outgoing.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    l10n.legislationRelationsOutgoingHeader,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                for (final rel in state.outgoing)
                  _RelationTile(
                    label:
                        srcLabels[rel.relationType.key] ?? rel.relationType.key,
                    otherDocumentId: rel.targetDocumentId,
                    otherDocumentTitle: rel.targetDocumentTitle,
                    otherDocumentCode: rel.targetDocumentCode,
                    scope: scopeLabels[rel.relationScope.key],
                    date: rel.effectiveDate,
                    onDelete: () => _confirmDelete(context, l10n, rel),
                  ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (state.incoming.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    l10n.legislationRelationsIncomingHeader,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                for (final rel in state.incoming)
                  _RelationTile(
                    label:
                        tgtLabels[rel.relationType.key] ?? rel.relationType.key,
                    otherDocumentId: rel.sourceDocumentId,
                    otherDocumentTitle: rel.sourceDocumentTitle,
                    otherDocumentCode: rel.sourceDocumentCode,
                    scope: scopeLabels[rel.relationScope.key],
                    date: rel.effectiveDate,
                    onDelete: () => _confirmDelete(context, l10n, rel),
                  ),
              ],
              if (!state.isLoading &&
                  state.outgoing.isEmpty &&
                  state.incoming.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    l10n.legislationRelationsEmpty,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddDialog(
    BuildContext context,
    AppLocalizations l10n,
  ) async {
    final bloc = context.read<LegislationRelationBloc>();
    final result = await showDialog<_NewRelationData>(
      context: context,
      builder: (_) => _AddRelationDialog(
        documentId: documentId,
        legislationDocumentTypeId: legislationDocumentTypeId,
      ),
    );
    if (result == null) return;
    bloc.add(
      LegislationRelationCreateRequested(
        documentId: documentId,
        input: LegislationRelationInput(
          sourceDocumentId: documentId,
          targetDocumentId: result.targetDocumentId,
          relationType: result.relationType,
          relationScope: result.scope,
          effectiveDate: result.effectiveDate,
          notes: result.notes,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AppLocalizations l10n,
    LegislationRelation relation,
  ) async {
    final bloc = context.read<LegislationRelationBloc>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.legislationRelationDeleteTitle),
        content: Text(l10n.legislationRelationDeleteContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.legislationRelationCancel),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.legislationRelationDeleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      bloc.add(
        LegislationRelationDeleteRequested(
          documentId: documentId,
          relationId: relation.id,
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Private tile widget
// ---------------------------------------------------------------------------

class _RelationTile extends StatelessWidget {
  const _RelationTile({
    required this.label,
    required this.otherDocumentId,
    required this.onDelete,
    this.otherDocumentTitle,
    this.otherDocumentCode,
    this.scope,
    this.date,
  });

  final String label;
  final int otherDocumentId;
  final String? otherDocumentTitle;
  final String? otherDocumentCode;
  final VoidCallback onDelete;
  final String? scope;
  final String? date;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final docLabel =
        otherDocumentTitle ??
        otherDocumentCode ??
        l10n.legislationRelationDocumentFallback(otherDocumentId);
    final parts = <String?>[scope, date].whereType<String>().toList();
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text('$label: $docLabel'),
      subtitle: parts.isNotEmpty ? Text(parts.join(' · ')) : null,
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: l10n.legislationRelationDeleteTooltip,
        onPressed: onDelete,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add-relation dialog (private)
// ---------------------------------------------------------------------------

class _NewRelationData {
  const _NewRelationData({
    required this.targetDocumentId,
    required this.relationType,
    required this.scope,
    this.effectiveDate,
    this.notes,
  });

  final int targetDocumentId;
  final LegislationRelationType relationType;
  final LegislationRelationScope scope;
  final String? effectiveDate;
  final String? notes;
}

class _AddRelationDialog extends StatefulWidget {
  const _AddRelationDialog({
    required this.documentId,
    required this.legislationDocumentTypeId,
  });

  final int documentId;
  final int? legislationDocumentTypeId;

  @override
  State<_AddRelationDialog> createState() => _AddRelationDialogState();
}

class _AddRelationDialogState extends State<_AddRelationDialog> {
  LegislationRelationType _relationType = LegislationRelationType.repeals;
  LegislationRelationScope _scope = LegislationRelationScope.unknown;
  int? _targetDocumentId;
  String? _targetTitle;
  String? _targetCode;
  final _effectiveDateController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _effectiveDateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickTarget() async {
    final picked = await LegislationDocumentPickerDialog.show(
      context,
      legislationDocumentTypeId: widget.legislationDocumentTypeId,
      excludeDocumentId: widget.documentId,
    );
    if (picked == null) return;
    setState(() {
      _targetDocumentId = picked.id;
      _targetTitle = picked.title;
      _targetCode = picked.documentCode;
    });
  }

  void _submit() {
    final effectiveDate = _effectiveDateController.text.trim();
    final notes = _notesController.text.trim();
    Navigator.of(context).pop(
      _NewRelationData(
        targetDocumentId: _targetDocumentId!,
        relationType: _relationType,
        scope: _scope,
        effectiveDate: effectiveDate.isEmpty ? null : effectiveDate,
        notes: notes.isEmpty ? null : notes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final srcLabels = relationTypeSourceLabels(l10n);
    final scopeLabels = relationScopeLabels(l10n);
    final canSubmit = _targetDocumentId != null;
    final targetLabel =
        _targetTitle ??
        _targetCode ??
        (_targetDocumentId != null
            ? l10n.legislationRelationDocumentFallback(_targetDocumentId!)
            : null);

    return AlertDialog(
      title: Text(l10n.legislationRelationAddDialogTitle),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<LegislationRelationType>(
              initialValue: _relationType,
              decoration: InputDecoration(
                labelText: l10n.legislationRelationTypeLabel,
              ),
              items: [
                for (final e in srcLabels.entries)
                  DropdownMenuItem(
                    value: LegislationRelationType.values.firstWhere(
                      (t) => t.key == e.key,
                    ),
                    child: Text(e.value),
                  ),
              ],
              onChanged: (v) => setState(() => _relationType = v!),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<LegislationRelationScope>(
              initialValue: _scope,
              decoration: InputDecoration(
                labelText: l10n.legislationRelationScopeLabel,
              ),
              items: [
                for (final e in scopeLabels.entries)
                  DropdownMenuItem(
                    value: LegislationRelationScope.values.firstWhere(
                      (s) => s.key == e.key,
                    ),
                    child: Text(e.value),
                  ),
              ],
              onChanged: (v) => setState(() => _scope = v!),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: targetLabel != null
                      ? Text(targetLabel, overflow: TextOverflow.ellipsis)
                      : Text(
                          l10n.legislationRelationNoTarget,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                ),
                const SizedBox(width: AppSpacing.sm),
                TextButton.icon(
                  icon: const Icon(Icons.search),
                  label: Text(l10n.legislationRelationPickTarget),
                  onPressed: _pickTarget,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _effectiveDateController,
              decoration: InputDecoration(
                labelText: l10n.legislationRelationEffectiveDateLabel,
                hintText: l10n.legislationRelationEffectiveDateHint,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText: l10n.legislationRelationNotesLabel,
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.legislationRelationCancel),
        ),
        FilledButton(
          onPressed: canSubmit ? _submit : null,
          child: Text(l10n.legislationRelationAddSubmit),
        ),
      ],
    );
  }
}
