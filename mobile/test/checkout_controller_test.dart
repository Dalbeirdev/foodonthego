import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/checkout.dart';
import 'package:foodonthego/shared/state/checkout_controller.dart';
import 'package:foodonthego/shared/state/providers.dart';

import 'support/harness.dart';

/// The checkout controller, without a widget tree.
///
/// **Nothing in this class computes an amount or decides readiness.** The tests
/// that matter here are the ones where the response is internally inconsistent
/// — a body that says "not ready" with no issues, a total that is not the sum of
/// its parts — and the controller is required to carry the server's answer
/// through unchanged.
void main() {
  ProviderContainer containerWith(FakeCheckoutRepository checkouts) {
    final ProviderContainer container = ProviderContainer(
      overrides: [checkoutRepositoryProvider.overrideWithValue(checkouts)],
    );

    container.listen(
      checkoutControllerProvider,
      (CheckoutState? _, CheckoutState _) {},
      fireImmediately: true,
    );

    addTearDown(container.dispose);

    return container;
  }

  CheckoutState stateOf(ProviderContainer container) =>
      container.read(checkoutControllerProvider);

  CheckoutController notifier(ProviderContainer container) =>
      container.read(checkoutControllerProvider.notifier);

  // --- opening --------------------------------------------------------------

  test('opening prepares once and holds what came back', () async {
    final FakeCheckoutRepository checkouts = FakeCheckoutRepository();
    final ProviderContainer container = containerWith(checkouts);

    await notifier(container).open(tripId: 'trip-1');

    expect(checkouts.prepareCalls, 1);
    expect(stateOf(container).checkout, isNotNull);
    expect(stateOf(container).hasLoaded, isTrue);
    expect(stateOf(container).isLoading, isFalse);
  });

  test('readiness is the server flag, not the empty issue list', () async {
    final FakeCheckoutRepository checkouts = FakeCheckoutRepository()
      ..readyForPayment = false;

    final ProviderContainer container = containerWith(checkouts);

    await notifier(container).open(tripId: 'trip-1');

    expect(stateOf(container).checkout!.validation!.issues, isEmpty);
    expect(stateOf(container).readyForPayment, isFalse);
  });

  test('readiness before the first answer is not a yes', () {
    final ProviderContainer container = containerWith(FakeCheckoutRepository());

    // Nothing has been asked. "Not known yet" must not read as "ready".
    expect(stateOf(container).checkout, isNull);
    expect(stateOf(container).readyForPayment, isFalse);
    expect(stateOf(container).isUsable, isFalse);
  });

  // --- validating -----------------------------------------------------------

  test('validating sends the id the server issued', () async {
    final FakeCheckoutRepository checkouts = FakeCheckoutRepository();
    final ProviderContainer container = containerWith(checkouts);

    await notifier(container).open(tripId: 'trip-1');
    await notifier(container).validate();

    expect(checkouts.checkoutIdsSent, <String>[checkouts.issuedCheckoutId]);
  });

  test('validating before anything is prepared sends nothing', () async {
    final FakeCheckoutRepository checkouts = FakeCheckoutRepository();
    final ProviderContainer container = containerWith(checkouts);

    await notifier(container).validate();

    // No trip and no quote. A request built out of nulls would be a request the
    // server has to reject, and the client should not make it.
    expect(checkouts.validateCalls, 0);
  });

  test('a second validate is ignored while the first is in flight', () async {
    final FakeCheckoutRepository checkouts = FakeCheckoutRepository();
    final ProviderContainer container = containerWith(checkouts);

    await notifier(container).open(tripId: 'trip-1');

    final Future<void> first = notifier(container).validate();
    final Future<void> second = notifier(container).validate();

    await Future.wait(<Future<void>>[first, second]);

    expect(checkouts.validateCalls, 1);
  });

  test('a forgotten quote is replaced rather than reported', () async {
    final FakeCheckoutRepository checkouts = FakeCheckoutRepository();
    final ProviderContainer container = containerWith(checkouts);

    await notifier(container).open(tripId: 'trip-1');

    checkouts.nextValidateError = ApiException(
      code: ApiErrorCode.checkoutQuoteNotFound,
      message: 'That checkout is no longer available.',
    );

    await notifier(container).validate();

    // A fresh quote, because an id the customer never saw cannot be explained
    // to them and a refresh is what the screen would offer anyway.
    expect(checkouts.prepareCalls, 2);
  });

  test('an expired quote is replaced too', () async {
    final FakeCheckoutRepository checkouts = FakeCheckoutRepository();
    final ProviderContainer container = containerWith(checkouts);

    await notifier(container).open(tripId: 'trip-1');

    checkouts.nextValidateError = ApiException(
      code: ApiErrorCode.checkoutQuoteExpired,
      message: 'That checkout has expired.',
    );

    await notifier(container).validate();

    expect(checkouts.prepareCalls, 2);
  });

  // --- refreshing -----------------------------------------------------------

  test('a refresh prepares afresh rather than revalidating', () async {
    // A quote goes stale because the facts under it moved. Asking again about
    // the old one would answer a question about a cart that no longer exists.
    final FakeCheckoutRepository checkouts = FakeCheckoutRepository()
      ..status = CheckoutStatus.stale;

    final ProviderContainer container = containerWith(checkouts);

    await notifier(container).open(tripId: 'trip-1');
    await notifier(container).refresh();

    expect(checkouts.prepareCalls, 2);
    expect(checkouts.validateCalls, 0);
  });

  test('a refresh before anything is open does nothing', () async {
    final FakeCheckoutRepository checkouts = FakeCheckoutRepository();
    final ProviderContainer container = containerWith(checkouts);

    await notifier(container).refresh();

    expect(checkouts.prepareCalls, 0);
  });

  test('preparing again picks up the new quote id', () async {
    final FakeCheckoutRepository checkouts = FakeCheckoutRepository();
    final ProviderContainer container = containerWith(checkouts);

    await notifier(container).open(tripId: 'trip-1');

    final String first = stateOf(container).checkout!.checkoutId!;

    checkouts.supersede();

    await notifier(container).refresh();

    final String second = stateOf(container).checkout!.checkoutId!;

    expect(second, isNot(first));

    // And the next validate uses the current one. Holding the superseded id
    // would be a request the server refuses, on a quote it has already
    // replaced.
    await notifier(container).validate();

    expect(checkouts.checkoutIdsSent.single, second);
  });

  // --- failures -------------------------------------------------------------

  test('each refusal maps to something the screen can say', () async {
    final Map<ApiErrorCode, CheckoutFailure> expected =
        <ApiErrorCode, CheckoutFailure>{
          ApiErrorCode.network: CheckoutFailure.network,
          ApiErrorCode.tripNotFound: CheckoutFailure.tripGone,
          ApiErrorCode.cartNotFound: CheckoutFailure.cartGone,
          ApiErrorCode.cartEmpty: CheckoutFailure.cartEmpty,
          ApiErrorCode.checkoutQuoteNotFound: CheckoutFailure.quoteGone,
          ApiErrorCode.checkoutQuoteExpired: CheckoutFailure.quoteGone,
          ApiErrorCode.checkoutQuoteStale: CheckoutFailure.quoteGone,
          ApiErrorCode.checkoutQuoteConsumed: CheckoutFailure.quoteGone,
          ApiErrorCode.unauthenticated: CheckoutFailure.unauthorized,
          ApiErrorCode.rateLimited: CheckoutFailure.rateLimited,
          ApiErrorCode.serverError: CheckoutFailure.serverError,
        };

    for (final MapEntry<ApiErrorCode, CheckoutFailure> entry
        in expected.entries) {
      final FakeCheckoutRepository checkouts = FakeCheckoutRepository()
        ..nextPrepareError = ApiException(code: entry.key, message: 'no');

      final ProviderContainer container = containerWith(checkouts);

      await notifier(container).open(tripId: 'trip-1');

      expect(
        stateOf(container).loadFailure,
        entry.value,
        reason: '${entry.key} should read as ${entry.value}',
      );
    }
  });

  test('a failure this build has never met is still a failure', () async {
    final FakeCheckoutRepository checkouts = FakeCheckoutRepository()
      ..nextPrepareError = ApiException(
        code: ApiErrorCode.unknown,
        message: 'Something new went wrong.',
      );

    final ProviderContainer container = containerWith(checkouts);

    await notifier(container).open(tripId: 'trip-1');

    expect(stateOf(container).loadFailure, CheckoutFailure.unknown);

    // And no price is left on screen from before, because there never was one.
    expect(stateOf(container).checkout, isNull);
  });

  test('a retry after a failure clears it', () async {
    final FakeCheckoutRepository checkouts = FakeCheckoutRepository()
      ..nextPrepareError = ApiException(
        code: ApiErrorCode.network,
        message: 'No connection.',
      );

    final ProviderContainer container = containerWith(checkouts);

    await notifier(container).open(tripId: 'trip-1');

    expect(stateOf(container).loadFailure, CheckoutFailure.network);

    await notifier(container).retry();

    expect(stateOf(container).loadFailure, isNull);
    expect(stateOf(container).checkout, isNotNull);
  });

  test('a failed validate leaves the quote on screen', () async {
    // The customer is looking at a price. A network failure while checking it
    // is not a reason to take it away — only a reason not to proceed.
    final FakeCheckoutRepository checkouts = FakeCheckoutRepository();
    final ProviderContainer container = containerWith(checkouts);

    await notifier(container).open(tripId: 'trip-1');

    checkouts.nextValidateError = ApiException(
      code: ApiErrorCode.network,
      message: 'No connection.',
    );

    await notifier(container).validate();

    expect(stateOf(container).checkout, isNotNull);
    expect(stateOf(container).failure, CheckoutFailure.network);
    expect(stateOf(container).isValidating, isFalse);
  });

  // --- what the quote's state means -----------------------------------------

  test('only an active quote is usable', () async {
    for (final CheckoutStatus status in CheckoutStatus.values) {
      final FakeCheckoutRepository checkouts = FakeCheckoutRepository()
        ..status = status;

      final ProviderContainer container = containerWith(checkouts);

      await notifier(container).open(tripId: 'trip-1');

      expect(
        stateOf(container).isUsable,
        status == CheckoutStatus.active,
        reason: '$status',
      );
    }
  });

  test('no request the controller makes carries an amount', () async {
    final FakeCheckoutRepository checkouts = FakeCheckoutRepository();
    final ProviderContainer container = containerWith(checkouts);

    await notifier(container).open(tripId: 'trip-1');
    await notifier(container).validate();
    await notifier(container).refresh();

    // Not "the amounts were right" — there is nowhere to put one. The
    // repository interface has no parameter for a price.
    expect(checkouts.bodiesSent, hasLength(3));
    for (final Map<String, Object?> body in checkouts.bodiesSent) {
      expect(body, isEmpty);
    }
  });
}
