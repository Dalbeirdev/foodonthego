import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/domain/models/pickup.dart';
import 'package:foodonthego/shared/state/pickup_controller.dart';
import 'package:foodonthego/shared/state/providers.dart';

import 'support/harness.dart';

/// Which answer the pickup screen is allowed to believe.
///
/// Every method on PickupController that writes the plan is a request, and
/// requests do not come back in the order they went out. A customer on a slow
/// connection can tap a time while a load is still in flight; the load then
/// answers with a plan that was true a moment before the tap, and nothing in
/// the response says so.
///
/// These tests exist because that shape of failure was observed. On the Android
/// emulator a confirmed pickup time disappeared from the screen seconds after
/// it was chosen — no error, no stale notice, the chooser simply back to
/// unselected — while the cart on the server still held the choice. Whether
/// that run had two loads in flight is not established here; what is
/// established is that if it did, the screen had no defence. A customer it
/// happens to is left with a greyed-out button, a cart the server considers
/// chosen, and nothing on screen that explains either.
void main() {
  late FakePickupRepository pickup;
  late ProviderContainer container;

  setUp(() {
    pickup = FakePickupRepository();
    container = ProviderContainer(
      // Inferred rather than annotated: flutter_riverpod does not export
      // `Override`, so naming the element type does not compile.
      overrides: [pickupRepositoryProvider.overrideWithValue(pickup)],
    );
    addTearDown(container.dispose);
  });

  PickupState read() => container.read(pickupControllerProvider);
  PickupController notifier() =>
      container.read(pickupControllerProvider.notifier);

  test('a load that answers after a choice does not undo the choice', () async {
    await notifier().open(tripId: 'trip-1');

    expect(read().options, isNotEmpty);

    // A second load goes out — a pull-to-refresh, or the screen mounted twice
    // on a deep link — and the server is slow to answer it.
    final Completer<void> slowAnswer = Completer<void>();
    pickup.holdOptions = slowAnswer;

    final Future<void> refreshing = notifier().refresh();

    // While it is still in the air the customer chooses a time, and that
    // request completes first.
    final String chosen = read().options.first.id;
    await notifier().choose(chosen);

    expect(
      read().selectedOptionId,
      chosen,
      reason: 'the choice did not take even before the race',
    );

    // Now the older request finally answers, carrying the plan as it stood
    // before the tap: nothing chosen.
    slowAnswer.complete();
    await refreshing;

    expect(
      read().selection.status,
      PickupSelectionStatus.selected,
      reason:
          'an answer issued before the choice was allowed to overwrite it — '
          'the selection card vanishes and the chooser goes blank',
    );
    expect(
      read().selectedOptionId,
      chosen,
      reason: 'the Check my order button is gated on this and would be dead',
    );
  });

  test('a load that answers after a newer load is the one discarded', () async {
    await notifier().open(tripId: 'trip-1');

    // The first refresh is held, the second is not. The second is newer, so its
    // answer is the one the screen keeps — and the first must not land on top
    // of it afterwards.
    final Completer<void> slowAnswer = Completer<void>();
    pickup.holdOptions = slowAnswer;

    final Future<void> first = notifier().refresh();
    final Future<void> second = notifier().refresh();

    await second;

    expect(read().isRefreshing, isFalse);

    slowAnswer.complete();
    await first;

    expect(
      read().isRefreshing,
      isFalse,
      reason: 'the older answer reopened a refresh the newer one had finished',
    );
    expect(pickup.optionsCalls, 3);
  });

  // ------------------------------------------------------------- the control
  //
  // Without this, both tests above would pass on a controller that ignored
  // every answer after the first — which is a worse bug wearing the fix's
  // clothes. A later answer must still win.

  test('an answer with nothing newer behind it is still applied', () async {
    await notifier().open(tripId: 'trip-1');

    final String chosen = read().options.first.id;
    await notifier().choose(chosen);

    expect(read().selectedOptionId, chosen);

    // A refresh after the choice is NEWER information and must win, selection
    // and all — here the server has since dropped it.
    pickup.selectionStatus = PickupSelectionStatus.none;

    await notifier().refresh();

    expect(
      read().selection.status,
      PickupSelectionStatus.none,
      reason: 'a later answer was discarded, which is the opposite failure',
    );
  });
}
