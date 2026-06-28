// lib/features/import/domain/usecases/get_recent_import_batches_use_case.dart

import '../entities/import_batch_record.dart';
import '../repositories/import_repository.dart';

/// Returns up to [limit] recent import batches from the repository, newest-first.
///
/// Pure domain use case: no Drift, no Flutter. Delegates entirely to
/// [ImportRepository.getRecentBatches].
class GetRecentImportBatchesUseCase {
  const GetRecentImportBatchesUseCase(this._repository);

  final ImportRepository _repository;

  Future<List<ImportBatchRecord>> call({int limit = 20}) =>
      _repository.getRecentBatches(limit: limit);
}
