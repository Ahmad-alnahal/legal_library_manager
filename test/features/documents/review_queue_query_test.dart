import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/documents/domain/entities/review_queue_query.dart';

void main() {
  group('ReviewQueueScope', () {
    test('classified statusKeys includes ready_for_export', () {
      expect(ReviewQueueScope.classified.statusKeys, [
        'classified',
        'copied_to_library',
        'ready_for_export',
      ]);
    });
  });
}
