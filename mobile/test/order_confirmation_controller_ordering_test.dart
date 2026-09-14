import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/domain/models/order_status_report.dart';
import 'package:foodonthego/shared/state/order_confirmation_controller.dart';
import 'package:foodonthego/shared/state/providers.dart';

import 'support/harness.dart';

/// Which status report the confirmation screen is allowed to believe.
///
/// This is the screen that says the money is safe. `load()` is started by
/// `build()`, re-armed by its own timer while the order settles, and started
/// again by `retry()` — whose doc offers it to "the impatient customer". The
/// screen today shows Retry only once a load has finished, so a tap cannot
/// overlap one; but that gate is in the screen, the promise is in the
/// controller, and this file holds the controller to its promise.
///
/// Found by the source-scan guard in `controllers_order_their_answers_test.dart`
/// after the hand audit had declared every controller covered. It had not
/// looked at this one.
void main() {
  late FakeOrderRepository orders;
  late ProviderContainer container;

  const OrderStatusReport stillCreating = OrderStatusReport(
    state: OrderCreationState.creating,
    isPaidFor: true,
    order: null,
  );

  setUp(() {
    orders = FakeOrderRepository();
    container = ProviderContainer(
      // Inferred rather than annotated: flutter_riverpod does not export
      // `Override`, so naming the element type does not compile.
      overrides: [orderRepositoryProvider.overrideWithValue(orders)],
    );
    addTearDown(container.dispose);
  });

  Future<void> settle() async {
    for (int i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  OrderConfirmationState read() =>
      container.read(orderConfirmationProvider('order-1'));

  OrderConfirmationController notifier() =>
      container.read(orderConfirmationProvider('order-1').notifier);

  /// Builds the controller and keeps it alive.
  ///
  /// The provider is autoDispose and a family, so without a listener it is
  /// disposed between awaits and `read()` returns a fresh, empty state — the
  /// same trap the route test fell into first.
  void open() {
    container.listen<OrderConfirmationState>(
      orderConfirmationProvider('order-1'),
      (OrderConfirmationState? previous, OrderConfirmationState next) {},
      fireImmediately: true,
    );
  }

  test('a status read that answers after a retry does not undo it', () async {
    // The first read — the one build() starts — finds the order still being
    // written, and the server is slow to say so.
    orders.statusReport = stillCreating;
    final Completer<void> slowAnswer = Completer<void>();
    orders.holdStatus = slowAnswer;

    open();
    await settle();

    expect(read().phase, OrderConfirmationPhase.loading);
    expect(orders.statusCalls, 1);

    // Meanwhile the order lands, and the customer taps Retry. That read is
    // quick and comes back PLACED. (The fake's default report is a placed
    // order with a collectable status, so the credential is fetched too.)
    orders.statusReport = null;
    await notifier().retry();
    await settle();

    expect(
      read().phase,
      OrderConfirmationPhase.placed,
      reason: 'the retry did not take even before the race',
    );
    expect(read().credential, isNotNull);

    // Now the first read finally answers, with the order as it stood before.
    slowAnswer.complete();
    await settle();

    expect(
      read().phase,
      OrderConfirmationPhase.placed,
      reason:
          'an answer issued before the retry slid the screen back from "your '
          'order is placed" to "still creating" and re-armed the poll over an '
          'order that is already placed',
    );
  });

  // ------------------------------------------------------------- the control
  //
  // This would pass on a controller that discarded every answer after the
  // first, which would leave the screen on its loading spinner forever.

  test('a read with nothing newer behind it is still applied', () async {
    orders.statusReport = stillCreating;

    open();
    await settle();

    expect(read().phase, OrderConfirmationPhase.creating);

    // The order lands and the customer retries. This is the newest read and
    // its answer must replace what is on screen.
    orders.statusReport = null;
    await notifier().retry();
    await settle();

    expect(
      read().phase,
      OrderConfirmationPhase.placed,
      reason: 'a later answer was discarded, which is the opposite failure',
    );
  });
}
