import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/domain/models/pickup.dart';
import 'package:foodonthego/domain/models/pre_checkout.dart';

/// Reading what the server sent.
///
/// The widget tests build these objects directly, which is the right shape for
/// testing a screen and leaves the parsing itself uncovered — so it is covered
/// here. This is the layer where "a build that has never heard of this still
/// does the safe thing" is actually decided.
void main() {
  Map<String, dynamic> planJson({
    Object? status = 'SELECTED',
    List<Object?>? options,
  }) => <String, dynamic>{
    'server_now': '2026-09-07T06:30:00+00:00',
    'timezone': 'Asia/Kolkata',
    'travel': <String, dynamic>{
      'estimated_arrival_at': '2026-09-07T08:03:20+00:00',
      'travel_minutes': 93,
      'basis': 'planned_route',
      'calculated_at': '2026-09-07T06:30:00+00:00',
      'is_fresh': true,
    },
    'preparation': <String, dynamic>{'preparation_minutes': 20},
    'buffer_minutes': 5,
    'minimum_lead_minutes': 10,
    'earliest_ready_at': '2026-09-07T06:55:00+00:00',
    'requires_route_refresh': false,
    'is_feasible': true,
    'reason': null,
    'selection': <String, dynamic>{
      'status': status,
      'start_at': '2026-09-07T13:40:00+05:30',
      'end_at': '2026-09-07T13:50:00+05:30',
      'timezone': 'Asia/Kolkata',
      'selected_at': '2026-09-07T06:30:00+00:00',
    },
    'recommended_option_id': 'abc',
    'options':
        options ??
        <Object?>[
          <String, dynamic>{
            'id': 'abc',
            'start_at': '2026-09-07T13:40:00+05:30',
            'end_at': '2026-09-07T13:50:00+05:30',
            'is_recommended': true,
          },
        ],
  };

  group('the plan', () {
    test('reads every figure the screen explains a time with', () {
      final PickupPlan plan = PickupPlan.fromJson(planJson());

      expect(plan.travelMinutes, 93);
      expect(plan.preparationMinutes, 20);
      expect(plan.bufferMinutes, 5);
      expect(plan.minimumLeadMinutes, 10);
      expect(plan.timezone, 'Asia/Kolkata');
      expect(plan.isFeasible, isTrue);
      expect(plan.options, hasLength(1));
      expect(plan.recommended?.id, 'abc');
    });

    test('keeps the counter clock as well as the instant', () {
      final PickupOption option = PickupPlan.fromJson(planJson()).options.first;

      // Two readings of one moment, and both are needed.
      //
      // The instant is what comparisons use, and `DateTime.parse` normalises it
      // to UTC — which is why it cannot also be what a screen formats. Format
      // the instant and a Delhi pickup renders as 8:10 am on a phone set to
      // London, or as 8:10 UTC on any phone at all. The door says 1:40 pm.
      expect(option.startAt.toUtc(), DateTime.utc(2026, 9, 7, 8, 10));

      expect(option.localStartAt.hour, 13);
      expect(option.localStartAt.minute, 40);
      expect(option.localEndAt.hour, 13);
      expect(option.localEndAt.minute, 50);
    });

    test('the counter clock survives a zone the phone knows nothing about', () {
      // Chatham Islands, +12:45. A client doing its own offset arithmetic gets
      // this wrong; one reading the fields the server wrote does not.
      final PickupPlan plan = PickupPlan.fromJson(
        planJson(
          options: <Object?>[
            <String, dynamic>{
              'id': 'chatham',
              'start_at': '2026-09-07T19:15:00+12:45',
              'end_at': '2026-09-07T19:25:00+12:45',
              'is_recommended': true,
            },
          ],
        ),
      );

      final PickupOption option = plan.options.single;

      expect(option.localStartAt.hour, 19);
      expect(option.localStartAt.minute, 15);
      expect(option.startAt.toUtc(), DateTime.utc(2026, 9, 7, 6, 30));
    });

    test('the arrival and ready times carry a counter clock too', () {
      final PickupPlan plan = PickupPlan.fromJson(planJson());

      // The explanation card formats these, so they need the same treatment as
      // the windows. Missing one is how a screen ends up half in one zone.
      expect(plan.localEarliestReadyAt, isNotNull);
      expect(plan.localEstimatedArrivalAt, isNotNull);
      expect(plan.localEarliestReadyAt!.hour, 6);
      expect(plan.localEstimatedArrivalAt!.hour, 8);
    });

    test('a response that is not the documented shape is not a plan', () {
      // Not an exception, and not a half-built plan either: `isFeasible` false
      // is the honest reading of a body nothing could be made of.
      for (final Object? rubbish in <Object?>[
        null,
        'nonsense',
        42,
        <int>[1],
      ]) {
        final PickupPlan plan = PickupPlan.fromJson(rubbish);

        expect(plan.isFeasible, isFalse);
        expect(plan.options, isEmpty);
        expect(plan.selection.status, PickupSelectionStatus.none);
      }
    });

    test('an option missing its id or its times is dropped, not guessed at', () {
      final PickupPlan plan = PickupPlan.fromJson(
        planJson(
          options: <Object?>[
            <String, dynamic>{'start_at': '2026-09-07T13:40:00+05:30'},
            <String, dynamic>{'id': 'no-times'},
            <String, dynamic>{
              'id': 'good',
              'start_at': '2026-09-07T14:00:00+05:30',
              'end_at': '2026-09-07T14:10:00+05:30',
              'is_recommended': false,
            },
            'not an object',
          ],
        ),
      );

      // An option the client cannot render is an option it must not offer. A
      // chip with no id has nothing to send, and one with no times has nothing
      // to say.
      expect(plan.options.map((PickupOption o) => o.id), <String>['good']);
    });
  });

  group('the selection status', () {
    test('an unknown status is not read as settled', () {
      // A wire value from a future release. The safe reading of "the server is
      // saying something this build cannot interpret" is that nothing has been
      // agreed — never that it has.
      for (final Object? value in <Object?>[
        'COLLECTED',
        'CANCELLED',
        '',
        null,
        7,
        <String>['SELECTED'],
      ]) {
        expect(
          PickupSelectionStatus.fromWire(value),
          PickupSelectionStatus.none,
          reason: '$value was read as something other than "nothing chosen"',
        );
      }
    });

    test('only SELECTED lets a customer move on', () {
      expect(PickupSelectionStatus.selected.isUsable, isTrue);

      for (final PickupSelectionStatus status in <PickupSelectionStatus>[
        PickupSelectionStatus.none,
        PickupSelectionStatus.stale,
        PickupSelectionStatus.invalid,
      ]) {
        expect(status.isUsable, isFalse);
      }
    });
  });

  group('pre-checkout', () {
    Map<String, dynamic> resultJson({
      bool ready = false,
      List<Object?>? issues,
    }) => <String, dynamic>{
      'cart': null,
      'pickup': planJson(),
      'ready_for_checkout': ready,
      'selection_status': 'SELECTED',
      'issues': issues ?? <Object?>[],
    };

    test('readiness is read from the server and never derived', () {
      // The case that matters: no issues listed, and the answer is still no.
      final PreCheckoutResult result = PreCheckoutResult.fromJson(
        resultJson(ready: false),
      );

      expect(result.readyForCheckout, isFalse);
      expect(result.issues, isEmpty);
    });

    test('a missing ready_for_checkout is a no', () {
      final Map<String, dynamic> json = resultJson(ready: true)
        ..remove('ready_for_checkout');

      // Absent is not permission. A body this client cannot find the answer in
      // is a body it must not read a yes out of.
      expect(PreCheckoutResult.fromJson(json).readyForCheckout, isFalse);
    });

    test('an issue with a code this build has never heard of still counts', () {
      final PreCheckoutResult result = PreCheckoutResult.fromJson(
        resultJson(
          issues: <Object?>[
            <String, dynamic>{
              'code': 'SOMETHING_FROM_NEXT_RELEASE',
              'message': 'A reason this version does not know about.',
              'blocking': true,
            },
          ],
        ),
      );

      // Kept, not dropped. The message came with it, so an old build still puts
      // a sentence in front of the customer — and `blocking` came with it too,
      // so an issue nobody has mapped still stops them.
      expect(result.issues, hasLength(1));
      expect(result.issues.single.code, isNull);
      expect(
        result.issues.single.message,
        'A reason this version does not know about.',
      );
      expect(result.blockers, hasLength(1));
    });

    test('blocking is the server flag, not a lookup from the code', () {
      final PreCheckoutResult result = PreCheckoutResult.fromJson(
        resultJson(
          issues: <Object?>[
            // A code this build DOES know, marked non-blocking by the server.
            <String, dynamic>{
              'code': 'PRICE_INCREASED',
              'message': 'A price went up.',
              'blocking': false,
            },
          ],
        ),
      );

      // The client does not second-guess it. If the server has decided a rise
      // is not in the way this time, the client is not the place that overrules
      // it.
      expect(result.blockers, isEmpty);
      expect(result.notices, hasLength(1));
    });

    test('an issue with no message is dropped rather than shown blank', () {
      final PreCheckoutResult result = PreCheckoutResult.fromJson(
        resultJson(
          issues: <Object?>[
            <String, dynamic>{'code': 'CART_EMPTY', 'blocking': true},
            'not an object',
            null,
          ],
        ),
      );

      // A bullet with nothing beside it tells a customer less than no bullet.
      expect(result.issues, isEmpty);
    });
  });
}
