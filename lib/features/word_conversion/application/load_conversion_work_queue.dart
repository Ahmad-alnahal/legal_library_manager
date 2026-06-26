// lib/features/word_conversion/application/load_conversion_work_queue.dart

import '../domain/entities/conversion_work_item.dart';
import '../domain/repositories/word_conversion_repository.dart';

/// Loads Word conversion rows that still need conversion work or attention.
class LoadConversionWorkQueue {
  const LoadConversionWorkQueue({required this.repository});

  final WordConversionRepository repository;

  Future<List<ConversionWorkItem>> call() =>
      repository.loadConversionWorkQueue();
}
