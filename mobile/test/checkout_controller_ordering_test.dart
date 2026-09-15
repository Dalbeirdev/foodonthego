import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/domain/models/checkout.dart';
import 'package:foodonthego/shared/state/checkout_controller.dart';
import 'package:foodonthego/shared/state/providers.dart';

import 'support/harness.dart';

/// Which quote the checkout screen is allowed to believe.
///
/// The third place the KI-041 fault was found, and the one where being wrong
/// costs the most to explain: this screen carries money and the id the payment
/// will be raised against.
///
/// `_prepare()` and `validate()` both write the quote. A pull-to-refresh still
/// in flight when the customer taps Proceed answers with the quote as it stood
/// before the server was asked to validate it, and puts that back on screen.
void main() {
  late FakeCheckoutRepository checkout;
  late ProviderContainer container;

  setUp(() {
    checkout = FakeCheckoutRepository();
    container = ProviderContainer(
      // Inferred rather than annotated: flutter_riverpod does not export
      // `Override`, so naming the element type does not compile.
      overrides: [checkoutRepositoryProvider.overrideWithValue(checkout)],
    );
    addTearDown(container.dispose);
  });

  CheckoutState read() => container.read(checkoutControllerProvider);
  CheckoutController notifier() =>
      container.read(checkoutControllerProvider.notifier);

  test('a prepare that answers after a validation does not undo it', () async {
    await notifier().open(tripId: 'trip-1');

    expect(read().checkout?.status, CheckoutStatus.active);

    // A pull-to-refresh goes out and the server is slow to answer it.
    final Completer<void> slowAnswer = Completer<void>();
    checkout.holdPrepare = slowAnswer;

    final Future<void> refreshing = notifier().refresh();

    // Meanwhile the facts move and the customer taps Proceed. The server says
    // the quote has gone stale, and that answer arrives first.
    checkout.status = CheckoutStatus.stale;
    await notifier().validate();

    expect(
      read().checkout?.status,
      CheckoutStatus.stale,
      reason: 'the validation did not take even before the race',
    );

    // Now the older request answers, carrying the quote as it was before.
    slowAnswer.complete();
    await refreshing;

    expect(
      read().checkout?.status,
      CheckoutStatus.stale,
      reason:
          'an answer issued before the validation put a quote the server has '
          'since called stale back on a screen carrying money',
    );
  });

  // ------------------------------------------------------------- the control
  //
  // This would pass on a controller that discarded every answer after the
  // first, which is a worse fault wearing the fix's clothes.

  test('a prepare with nothing newer behind it is still applied', () async {
    await notifier().open(tripId: 'trip-1');

    await notifier().validate();

    checkout.status = CheckoutStatus.expired;

    await notifier().refresh();

    expect(
      read().checkout?.status,
      CheckoutStatus.expired,
      reason: 'a later answer was discarded, which is the opposite failure',
    );
  });
}
