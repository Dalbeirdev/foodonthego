import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/domain/models/cart.dart';
import 'package:foodonthego/shared/state/cart_controller.dart';
import 'package:foodonthego/shared/state/providers.dart';

import 'support/harness.dart';

/// Which answer the cart screen is allowed to believe.
///
/// The same fault found on the pickup screen, in the place it is easiest for a
/// customer to hit. A revalidation is a read of the cart as it was when the
/// request went out; an edit is a write that lands after. If the read is
/// allowed to overwrite the write when it finally answers, the quantity the
/// customer just set drops back to what it was — over a cart the server has
/// already changed.
///
/// The second test needs no slow connection and no pull-to-refresh. Every
/// successful edit fires a quiet revalidation behind it, so two taps on the
/// stepper are enough: the first tap's revalidation can outlive the second
/// tap's response.
void main() {
  late FakeCartRepository carts;
  late ProviderContainer container;

  setUp(() {
    carts = FakeCartRepository(
      lines: <CartLine>[sampleCartLine(quantity: 1)],
    );
    container = ProviderContainer(
      // Inferred rather than annotated: flutter_riverpod does not export
      // `Override`, so naming the element type does not compile.
      overrides: [cartRepositoryProvider.overrideWithValue(carts)],
    );
    addTearDown(container.dispose);
  });

  CartState read() => container.read(cartControllerProvider);
  CartController notifier() =>
      container.read(cartControllerProvider.notifier);

  int quantityOnScreen() => read().view.cart!.lines.first.quantity;

  test('a revalidation that answers after an edit does not undo it', () async {
    await notifier().open(tripId: 'trip-1');

    expect(quantityOnScreen(), 1);

    // A pull-to-refresh goes out and the server is slow to answer it.
    final Completer<void> slowAnswer = Completer<void>();
    carts.holdRevalidate = slowAnswer;

    final Future<void> refreshing = notifier().refresh();

    // The customer adds one while it is still in the air, and that lands first.
    await notifier().increment(read().view.cart!.lines.first);

    expect(quantityOnScreen(), 2, reason: 'the edit did not take at all');

    slowAnswer.complete();
    await refreshing;

    expect(
      quantityOnScreen(),
      2,
      reason:
          'a read issued before the edit was allowed to overwrite it — the '
          'quantity reverts on screen over a cart the server has already '
          'changed',
    );
  });

  test('the revalidation behind one tap cannot undo the next tap', () async {
    await notifier().open(tripId: 'trip-1');

    // Armed BEFORE the first tap, which matters: the edit fires its quiet
    // revalidation unawaited the instant its own response lands, so arming
    // afterwards catches nothing and the test passes having exercised none of
    // this. It did, on the first draft.
    final Completer<void> slowAnswer = Completer<void>();
    carts.holdRevalidate = slowAnswer;

    await notifier().increment(read().view.cart!.lines.first);
    expect(quantityOnScreen(), 2);

    // A second tap, which is what a customer wanting three of something does.
    // Its own quiet revalidation is not held and answers straight away.
    await notifier().increment(read().view.cart!.lines.first);
    expect(quantityOnScreen(), 3);

    // Now the FIRST tap's revalidation answers, carrying the cart as it was
    // before the second tap.
    slowAnswer.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(
      quantityOnScreen(),
      3,
      reason: 'the first tap\'s revalidation reverted the second tap',
    );
  });

  // ------------------------------------------------------------- the control
  //
  // Both tests above would pass on a controller that discarded every answer
  // after the first, which is a worse fault wearing the fix's clothes.

  test('a read with nothing newer behind it is still applied', () async {
    await notifier().open(tripId: 'trip-1');

    await notifier().increment(read().view.cart!.lines.first);
    expect(quantityOnScreen(), 2);

    // The line changes behind the screen's back — a later read is newer
    // information and must replace what is on screen. Written straight through
    // the fake, the way the server would have it after somebody else's call.
    await carts.setQuantity(tripId: 'trip-1', lineId: 'line-1', quantity: 7);

    await notifier().refresh();

    expect(
      quantityOnScreen(),
      7,
      reason: 'a later answer was discarded, which is the opposite failure',
    );
  });
}
