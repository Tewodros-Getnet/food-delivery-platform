import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:food_delivery_rider/features/delivery/screens/earnings_screen.dart';

// ── Fake earnings data ────────────────────────────────────────────────────────

const _fakeEarnings = {
  'totalEarnings': 450.0,
  'totalDeliveries': 12,
  'deliveries': <dynamic>[],
};

// ── Helper ────────────────────────────────────────────────────────────────────

Widget _buildEarningsScreen({
  AsyncValue<Map<String, dynamic>>? earningsState,
}) {
  return ProviderScope(
    overrides: [
      earningsProvider.overrideWith(
        (_) async => earningsState != null
            ? earningsState.when(
                data: (d) => d,
                loading: () => throw UnimplementedError(),
                error: (e, _) => throw e,
              )
            : _fakeEarnings,
      ),
    ],
    child: const MaterialApp(home: EarningsScreen()),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('EarningsScreen — structure', () {
    testWidgets('renders Earnings AppBar', (tester) async {
      await tester.pumpWidget(_buildEarningsScreen());
      await tester.pumpAndSettle();

      expect(find.text('Earnings'), findsOneWidget);
    });

    testWidgets('shows loading indicator while fetching', (tester) async {
      // Override with a future that never completes to stay in loading state
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            earningsProvider.overrideWith((_) async {
              await Future<void>.delayed(const Duration(hours: 1));
              return _fakeEarnings;
            }),
          ],
          child: const MaterialApp(home: EarningsScreen()),
        ),
      );
      // Single pump — provider is still loading
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Drain pending timers so the test can close cleanly
      await tester.pump(const Duration(hours: 2));
    });

    testWidgets('shows total earnings after data loads', (tester) async {
      await tester.pumpWidget(_buildEarningsScreen());
      await tester.pumpAndSettle();

      expect(find.textContaining('ETB 450.00'), findsOneWidget);
    });

    testWidgets('shows delivery count after data loads', (tester) async {
      await tester.pumpWidget(_buildEarningsScreen());
      await tester.pumpAndSettle();

      expect(find.textContaining('12 deliveries completed'), findsOneWidget);
    });

    testWidgets('shows empty state when no deliveries', (tester) async {
      await tester.pumpWidget(_buildEarningsScreen());
      await tester.pumpAndSettle();

      expect(find.text('No completed deliveries yet'), findsOneWidget);
    });
  });

  group('EarningsScreen — with deliveries', () {
    testWidgets('renders delivery list items', (tester) async {
      const dataWithDeliveries = {
        'totalEarnings': 120.0,
        'totalDeliveries': 2,
        'deliveries': [
          {
            'delivery_fee': 60.0,
            'restaurant_name': 'Pizza Palace',
            'address_line': '123 Main St',
            'updated_at': '2026-04-01T10:00:00.000Z',
          },
          {
            'delivery_fee': 60.0,
            'restaurant_name': 'Burger Barn',
            'address_line': '456 Oak Ave',
            'updated_at': '2026-04-02T14:30:00.000Z',
          },
        ],
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            earningsProvider.overrideWith((_) async => dataWithDeliveries),
          ],
          child: const MaterialApp(home: EarningsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pizza Palace'), findsOneWidget);
      expect(find.text('Burger Barn'), findsOneWidget);
    });
  });
}
