import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/legislation/domain/entities/legislation_relation_scope.dart';
import 'package:legal_library_manager/features/legislation/domain/entities/legislation_relation_type.dart';

void main() {
  group('LegislationRelationType', () {
    test('every value round-trips through its key', () {
      for (final v in LegislationRelationType.values) {
        expect(LegislationRelationType.fromKey(v.key), v);
      }
    });

    test('all five keys are recognised', () {
      expect(
        LegislationRelationType.fromKey('repeals'),
        LegislationRelationType.repeals,
      );
      expect(
        LegislationRelationType.fromKey('amends'),
        LegislationRelationType.amends,
      );
      // DB key is 'implements'; Dart value is implementing (reserved word).
      expect(
        LegislationRelationType.fromKey('implements'),
        LegislationRelationType.implementing,
      );
      expect(
        LegislationRelationType.fromKey('based_on'),
        LegislationRelationType.basedOn,
      );
      expect(
        LegislationRelationType.fromKey('supersedes'),
        LegislationRelationType.supersedes,
      );
    });

    test('.key returns the correct DB string for implementing', () {
      expect(LegislationRelationType.implementing.key, 'implements');
    });

    test('unknown key throws ArgumentError', () {
      expect(
        () => LegislationRelationType.fromKey('implementing'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('LegislationRelationScope', () {
    test('every value round-trips through its key', () {
      for (final v in LegislationRelationScope.values) {
        expect(LegislationRelationScope.fromKey(v.key), v);
      }
    });

    test('all three keys are recognised', () {
      expect(
        LegislationRelationScope.fromKey('full'),
        LegislationRelationScope.full,
      );
      expect(
        LegislationRelationScope.fromKey('partial'),
        LegislationRelationScope.partial,
      );
      expect(
        LegislationRelationScope.fromKey('unknown'),
        LegislationRelationScope.unknown,
      );
    });

    test('unknown key throws ArgumentError', () {
      expect(
        () => LegislationRelationScope.fromKey('bad'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
