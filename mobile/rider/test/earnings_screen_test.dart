import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:food_delivery_rider/features/delivery/screens/earnings_screen.dart';

const _fakeEarnings = {
  'totalEarnings': 450.0,
  'totalDeliveries': 12,
  'deliveries': <dynamic>[],
};

// Override all three period variants so any tab works in tests
List<Override> _overrides(Map<String, dynamic> data) => [
      earningsProvider(EarningsPeriod.week).overrideWith((_) async => data),
      earningsProvider(EarningsPeriod.month).overrideWith((_) async => data),
      earningsProvider(EarningsPeriod.all).overrideWith((_) async => data),
    ];

Widget _buildEarningsScreen({Map<String, dynamic>? data}) {
  return ProviderScope(
    overrides: _overrides(data ?? _fakeEarnings),
    child: const MaterialApp(home: EarningsScreen()),
  );
}

void main() {
  group('EarningsScreen — structure', () {
    testWidgets('renders Earnings AppBar', (tester) async {
      await tester.pumpWidget(_buildEarningsScreen());
      await tester.pumpAndSettle();
      expect(find.text('Earnings'), findsOneWidget);
    });

    testWidgets('shows This Week / This Month / All Time tabs', (tester) async {
      await tester.pumpWidget(_buildEarningsScreen());
      await tester.pumpAndSettle();
      expect(find.text('This Week'), findsWidgets);
      expect(find.text('This Month'), findsWidgets);
      expect(find.text('All Time'), findsWidgets);
    });

    testWidgets('shows loading indicator while fetching', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            earningsProvider(EarningsPeriod.week).overrideWith((_) async {
              await Future<void>.delayed(const Duration(hours: 1));
              return _fakeEarnings;
            }),
            earningsProvider(EarningsPeriod.month).overrideWith((_) async {
              await Future<void>.delayed(const Duration(hours: 1));
              return _fakeEarnings;
            }),
            earningsProvider(EarningsPeriod.all).overrideWith((_) async {
              await Future<void>.delayed(const Duration(hours: 1));
              return _fakeEarnings;
            }),
          ],
          child: const MaterialApp(home: EarningsScreen()),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
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
      expect(find.textContaining('No deliveries'), findsOneWidget);
    });

    testWidgets('shows average per delivery', (tester) async {
      await tester.pumpWidget(_buildEarningsScreen());
      await tester.pumpAndSettle();
      // 450 / 12 = 37.50
      expect(find.textContaining('37.50'), findsOneWidget);
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

      await tester.pumpWidget(_buildEarningsScreen(data: dataWithDeliveries));
      await tester.pumpAndSettle();

      expect(find.text('Pizza Palace'), findsOneWidget);
      expect(find.text('Burger Barn'), findsOneWidget);
    });
  });
}
