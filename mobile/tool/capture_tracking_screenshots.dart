// Screenshots of the order tracking screen, for the client review package.
//
// Run it deliberately, never as part of the suite:
//
//   flutter test tool/capture_tracking_screenshots.dart --update-goldens
//
// It lives under tool/ rather than test/ for that reason — `flutter test` with
// no path runs test/ only, so CI never touches this.
//
// ONE HONEST CAVEAT. This is the real widget tree, real theme, real router and
// real screen code, driven by the same fake repository the widget tests use —
// but it is not a device, so platform channels, safe areas, the keyboard and
// lifecycle are absent. For the tracking screen against a real server on real
// hardware the evidence is the on-device suite, not these images.
//
// What is NOT a caveat: the type. `flutter test` draws every glyph as an empty
// box unless fonts are registered, so Roboto and MaterialIcons are loaded here
// straight out of the Flutter SDK — the same files a real build ships. Nothing
// about the theme is modified. If those files are missing the capture skips
// rather than writing pages of boxes and calling them screenshots.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';
import 'package:foodonthego/domain/models/order_timeline.dart';
import 'package:foodonthego/domain/models/placed_order.dart';
import 'package:foodonthego/domain/models/tracked_order.dart';

import '../test/support/harness.dart';

// The fonts come from the Flutter SDK itself — the same Roboto and
// MaterialIcons a real build ships — so nothing about the type in these images
// is a stand-in. `flutter test` otherwise renders every glyph as an empty box.
const String _textFamily = 'Roboto';
const String _iconFamily = 'MaterialIcons';

String? _flutterRoot() {
  final String? root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && Directory(root).existsSync()) return root;
  for (final String guess in <String>['/opt/flutter', '/usr/local/flutter']) {
    if (Directory(guess).existsSync()) return guess;
  }
  return null;
}

Future<ByteData> _bytes(String path) async =>
    ByteData.sublistView(await File(path).readAsBytes());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final String? root = _flutterRoot();
  final String fonts = '$root/bin/cache/artifacts/material_fonts';
  final bool haveFonts =
      root != null && File('$fonts/Roboto-Regular.ttf').existsSync();

  setUpAll(() async {
    if (!haveFonts) {
      // ignore: avoid_print
      print('NO SDK FONTS FOUND at $fonts — nothing will be captured.');
      return;
    }

    final FontLoader text = FontLoader(_textFamily)
      ..addFont(_bytes('$fonts/Roboto-Regular.ttf'))
      ..addFont(_bytes('$fonts/Roboto-Medium.ttf'))
      ..addFont(_bytes('$fonts/Roboto-Bold.ttf'));
    await text.load();

    final FontLoader icons = FontLoader(_iconFamily)
      ..addFont(_bytes('$fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  OrderTimelineStep step(
    PlacedOrderStatus status,
    OrderTimelineStepState state, {
    DateTime? at,
    String? note,
  }) => OrderTimelineStep(
    status: status,
    state: state,
    title: switch (status) {
      PlacedOrderStatus.placed => 'Order placed',
      PlacedOrderStatus.accepted => 'Restaurant accepted your order',
      PlacedOrderStatus.cooking => 'Your food is being prepared',
      PlacedOrderStatus.ready => 'Ready for pickup',
      PlacedOrderStatus.pickedUp => 'Picked up',
      PlacedOrderStatus.rejected => "Restaurant couldn't accept this order",
      _ => status.label,
    },
    occurredAt: at,
    note: note,
  );

  TrackedOrder tracked({
    required PlacedOrderStatus status,
    required int version,
    required List<OrderTimelineStep> timeline,
    bool isActive = true,
    String? reason,
    bool credential = true,
  }) => TrackedOrder(
    order: FakeOrderRepository.orderFor(
      id: 'order-1',
      status: status,
      orderNumber: 'FOTG-260918-K4M9PQ2X7B',
      statusTitle: switch (status) {
        PlacedOrderStatus.placed => 'Order placed',
        PlacedOrderStatus.accepted => 'Restaurant accepted your order',
        PlacedOrderStatus.cooking => 'Your food is being prepared',
        PlacedOrderStatus.ready => 'Ready for pickup',
        PlacedOrderStatus.pickedUp => 'Picked up',
        PlacedOrderStatus.rejected => "Restaurant couldn't accept this order",
        _ => status.label,
      },
    ),
    version: version,
    timeline: timeline,
    isActive: isActive,
    customerSafeReason: reason,
    pickupCredentialAvailable: credential,
  );

  final DateTime placedAt = DateTime(2026, 9, 18, 16, 1);
  final DateTime acceptedAt = DateTime(2026, 9, 18, 16, 3);
  final DateTime cookingAt = DateTime(2026, 9, 18, 16, 6);
  final DateTime readyAt = DateTime(2026, 9, 18, 16, 21);
  final DateTime pickedUpAt = DateTime(2026, 9, 18, 16, 34);

  Future<void> capture(
    WidgetTester tester,
    String name,
    TrackedOrder order, {
    Size size = const Size(390, 844),
    double textScale = 1.0,
    DateTime Function()? clock,
  }) async {
    usePhoneSurface(tester, size: size);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: wrapApp(
          repository: StubHomeRepository.value(
            const HomeDashboard(
              customer: CustomerSummary(fullName: 'Rahul Sharma'),
            ),
          ),
          orders: FakeOrderRepository()..trackedOrder = order,
          trackingClock: clock,
          initialLocation: '/orders/order-1/track',
        ),
      ),
    );

    await tester.pump();
    // Long enough for the route transition to finish: a half-faded app bar is
    // not what a customer sees, and a golden of one is not a screenshot.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        '../../docs/evidence/module-17/screenshots/tracking-$name.png',
      ),
    );
  }

  testWidgets('placed', (WidgetTester tester) async {
    if (!haveFonts) {
      markTestSkipped('no SDK fonts; nothing captured');
      return;
    }
    await capture(
      tester,
      'placed',
      tracked(
        status: PlacedOrderStatus.placed,
        version: 1,
        timeline: <OrderTimelineStep>[
          step(
            PlacedOrderStatus.placed,
            OrderTimelineStepState.current,
            at: placedAt,
          ),
          step(PlacedOrderStatus.accepted, OrderTimelineStepState.upcoming),
          step(PlacedOrderStatus.cooking, OrderTimelineStepState.upcoming),
          step(PlacedOrderStatus.ready, OrderTimelineStepState.upcoming),
          step(PlacedOrderStatus.pickedUp, OrderTimelineStepState.upcoming),
        ],
      ),
    );
  });

  testWidgets('cooking', (WidgetTester tester) async {
    if (!haveFonts) {
      markTestSkipped('no SDK fonts; nothing captured');
      return;
    }
    await capture(
      tester,
      'cooking',
      tracked(
        status: PlacedOrderStatus.cooking,
        version: 3,
        timeline: <OrderTimelineStep>[
          step(
            PlacedOrderStatus.placed,
            OrderTimelineStepState.completed,
            at: placedAt,
          ),
          step(
            PlacedOrderStatus.accepted,
            OrderTimelineStepState.completed,
            at: acceptedAt,
          ),
          step(
            PlacedOrderStatus.cooking,
            OrderTimelineStepState.current,
            at: cookingAt,
          ),
          step(PlacedOrderStatus.ready, OrderTimelineStepState.upcoming),
          step(PlacedOrderStatus.pickedUp, OrderTimelineStepState.upcoming),
        ],
      ),
    );
  });

  testWidgets('ready', (WidgetTester tester) async {
    if (!haveFonts) {
      markTestSkipped('no SDK fonts; nothing captured');
      return;
    }
    await capture(
      tester,
      'ready',
      tracked(
        status: PlacedOrderStatus.ready,
        version: 4,
        timeline: <OrderTimelineStep>[
          step(
            PlacedOrderStatus.placed,
            OrderTimelineStepState.completed,
            at: placedAt,
          ),
          step(
            PlacedOrderStatus.accepted,
            OrderTimelineStepState.completed,
            at: acceptedAt,
          ),
          step(
            PlacedOrderStatus.cooking,
            OrderTimelineStepState.completed,
            at: cookingAt,
          ),
          step(
            PlacedOrderStatus.ready,
            OrderTimelineStepState.current,
            at: readyAt,
          ),
          step(PlacedOrderStatus.pickedUp, OrderTimelineStepState.upcoming),
        ],
      ),
    );
  });

  testWidgets('picked up', (WidgetTester tester) async {
    if (!haveFonts) {
      markTestSkipped('no SDK fonts; nothing captured');
      return;
    }
    await capture(
      tester,
      'picked-up',
      tracked(
        status: PlacedOrderStatus.pickedUp,
        version: 5,
        isActive: false,
        credential: false,
        timeline: <OrderTimelineStep>[
          step(
            PlacedOrderStatus.placed,
            OrderTimelineStepState.completed,
            at: placedAt,
          ),
          step(
            PlacedOrderStatus.accepted,
            OrderTimelineStepState.completed,
            at: acceptedAt,
          ),
          step(
            PlacedOrderStatus.cooking,
            OrderTimelineStepState.completed,
            at: cookingAt,
          ),
          step(
            PlacedOrderStatus.ready,
            OrderTimelineStepState.completed,
            at: readyAt,
          ),
          step(
            PlacedOrderStatus.pickedUp,
            OrderTimelineStepState.current,
            at: pickedUpAt,
          ),
        ],
      ),
    );
  });

  testWidgets('rejected', (WidgetTester tester) async {
    if (!haveFonts) {
      markTestSkipped('no SDK fonts; nothing captured');
      return;
    }
    await capture(
      tester,
      'rejected',
      tracked(
        status: PlacedOrderStatus.rejected,
        version: 2,
        isActive: false,
        credential: false,
        reason: 'The kitchen is closed for the rest of today.',
        timeline: <OrderTimelineStep>[
          step(
            PlacedOrderStatus.placed,
            OrderTimelineStepState.completed,
            at: placedAt,
          ),
          step(
            PlacedOrderStatus.rejected,
            OrderTimelineStepState.exception,
            at: acceptedAt,
          ),
        ],
      ),
    );
  });

  testWidgets('too old to vouch for', (WidgetTester tester) async {
    if (!haveFonts) {
      markTestSkipped('no SDK fonts; nothing captured');
      return;
    }
    // KI-031. The same cooking order, rendered a day after it was read. The
    // status and the timeline are gone; the order number, the restaurant, the
    // items and the amount paid are not, because none of those go stale.
    await capture(
      tester,
      'status-unknown',
      tracked(
        status: PlacedOrderStatus.cooking,
        version: 3,
        timeline: <OrderTimelineStep>[
          step(
            PlacedOrderStatus.placed,
            OrderTimelineStepState.completed,
            at: placedAt,
          ),
          step(
            PlacedOrderStatus.accepted,
            OrderTimelineStepState.completed,
            at: acceptedAt,
          ),
          step(
            PlacedOrderStatus.cooking,
            OrderTimelineStepState.current,
            at: cookingAt,
          ),
          step(PlacedOrderStatus.ready, OrderTimelineStepState.upcoming),
          step(PlacedOrderStatus.pickedUp, OrderTimelineStepState.upcoming),
        ],
      ),
      clock: () => DateTime.now().add(const Duration(days: 1)),
    );
  });

  testWidgets('narrow 320', (WidgetTester tester) async {
    if (!haveFonts) {
      markTestSkipped('no SDK fonts; nothing captured');
      return;
    }
    await capture(
      tester,
      'cooking-320',
      tracked(
        status: PlacedOrderStatus.cooking,
        version: 3,
        timeline: <OrderTimelineStep>[
          step(
            PlacedOrderStatus.placed,
            OrderTimelineStepState.completed,
            at: placedAt,
          ),
          step(
            PlacedOrderStatus.accepted,
            OrderTimelineStepState.completed,
            at: acceptedAt,
          ),
          step(
            PlacedOrderStatus.cooking,
            OrderTimelineStepState.current,
            at: cookingAt,
          ),
          step(PlacedOrderStatus.ready, OrderTimelineStepState.upcoming),
          step(PlacedOrderStatus.pickedUp, OrderTimelineStepState.upcoming),
        ],
      ),
      size: const Size(320, 720),
    );
  });

  testWidgets('large text', (WidgetTester tester) async {
    if (!haveFonts) {
      markTestSkipped('no SDK fonts; nothing captured');
      return;
    }
    await capture(
      tester,
      'cooking-large-text',
      tracked(
        status: PlacedOrderStatus.cooking,
        version: 3,
        timeline: <OrderTimelineStep>[
          step(
            PlacedOrderStatus.placed,
            OrderTimelineStepState.completed,
            at: placedAt,
          ),
          step(
            PlacedOrderStatus.accepted,
            OrderTimelineStepState.completed,
            at: acceptedAt,
          ),
          step(
            PlacedOrderStatus.cooking,
            OrderTimelineStepState.current,
            at: cookingAt,
          ),
          step(PlacedOrderStatus.ready, OrderTimelineStepState.upcoming),
          step(PlacedOrderStatus.pickedUp, OrderTimelineStepState.upcoming),
        ],
      ),
      textScale: 2.0,
    );
  });
}
