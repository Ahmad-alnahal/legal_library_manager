import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../documents/domain/entities/document_list_item.dart';
import '../../../documents/domain/entities/document_list_query.dart';
import '../../../documents/domain/repositories/document_list_repository.dart';

/// A modal dialog for searching and selecting a legislation document.
///
/// Returns a [PickedLegislationDocument] when a document is selected, or
/// `null` when the user cancels. Self-relation is prevented by excluding
/// [excludeDocumentId] from results.
class LegislationDocumentPickerDialog extends StatefulWidget {
  const LegislationDocumentPickerDialog({
    super.key,
    required this.legislationDocumentTypeId,
    required this.excludeDocumentId,
  });

  final int? legislationDocumentTypeId;
  final int excludeDocumentId;

  static Future<PickedLegislationDocument?> show(
    BuildContext context, {
    required int? legislationDocumentTypeId,
    required int excludeDocumentId,
  }) {
    return showDialog<PickedLegislationDocument>(
      context: context,
      builder: (_) => LegislationDocumentPickerDialog(
        legislationDocumentTypeId: legislationDocumentTypeId,
        excludeDocumentId: excludeDocumentId,
      ),
    );
  }

  @override
  State<LegislationDocumentPickerDialog> createState() =>
      _LegislationDocumentPickerDialogState();
}

class PickedLegislationDocument {
  const PickedLegislationDocument({
    required this.id,
    this.title,
    this.documentCode,
  });

  final int id;
  final String? title;
  final String? documentCode;
}

class _LegislationDocumentPickerDialogState
    extends State<LegislationDocumentPickerDialog> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<DocumentListItem> _items = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load(String query) async {
    setState(() => _loading = true);
    try {
      final repo = getIt<DocumentListRepository>();
      final page = await repo.getDocuments(
        DocumentListQuery(
          filters: DocumentListFilters(
            search: query.isEmpty ? null : query,
            documentTypeId: widget.legislationDocumentTypeId,
          ),
          limit: 50,
        ),
      );
      if (!mounted) return;
      setState(() {
        _items = page.items
            .where((item) => item.id != widget.excludeDocumentId)
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _load(value.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.legislationPickerTitle),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.legislationPickerSearchLabel,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: _onSearch,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_loading)
              const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_items.isEmpty)
              SizedBox(
                height: 80,
                child: Center(child: Text(l10n.legislationPickerEmpty)),
              )
            else
              SizedBox(
                height: 320,
                child: ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final titleLabel =
                        item.title ??
                        item.documentCode ??
                        l10n.legislationRelationDocumentFallback(item.id);
                    final year = item.publicationYear?.toString();
                    return ListTile(
                      title: Text(
                        titleLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: year != null ? Text(year) : null,
                      onTap: () => Navigator.of(context).pop(
                        PickedLegislationDocument(
                          id: item.id,
                          title: item.title,
                          documentCode: item.documentCode,
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.legislationPickerCancel),
        ),
      ],
    );
  }
}
