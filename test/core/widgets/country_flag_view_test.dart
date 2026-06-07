import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/widgets/country_flag_view.dart';

void main() {
  Future<void> pumpFlag(WidgetTester tester, String code) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: CountryFlagView(countryCode: code)),
        ),
      ),
    );
  }

  group('CountryFlagView', () {
    testWidgets('renders ps, jo, us, jp without exceptions', (tester) async {
      for (final code in ['ps', 'jo', 'us', 'jp']) {
        await pumpFlag(tester, code);
        expect(tester.takeException(), isNull, reason: 'code $code threw');
        // A real flag renders the package widget, not the fallback.
        expect(find.byType(CountryFlag), findsOneWidget, reason: code);
        expect(find.byKey(const Key('countryFlagView_fallback')), findsNothing);
      }
    });

    testWidgets('accepts lowercase database keys', (tester) async {
      await pumpFlag(tester, 'jp');
      expect(tester.takeException(), isNull);
      expect(find.byType(CountryFlag), findsOneWidget);
    });

    testWidgets('invalid code produces the fallback without crashing', (
      tester,
    ) async {
      await pumpFlag(tester, 'zz');
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('countryFlagView_fallback')), findsOneWidget);
      expect(find.byType(CountryFlag), findsNothing);
    });

    testWidgets('malformed codes (empty / too long) fall back safely', (
      tester,
    ) async {
      for (final code in ['', 'x', 'usa', '12']) {
        await pumpFlag(tester, code);
        expect(tester.takeException(), isNull, reason: 'code "$code" threw');
        expect(
          find.byKey(const Key('countryFlagView_fallback')),
          findsOneWidget,
          reason: 'code "$code" should fall back',
        );
      }
    });

    testWidgets('uses fixed dimensions for layout stability', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CountryFlagView(countryCode: 'ps', width: 30, height: 20),
            ),
          ),
        ),
      );
      final Size size = tester.getSize(find.byType(CountryFlagView));
      expect(size.width, 30);
      expect(size.height, 20);
    });
  });
}
