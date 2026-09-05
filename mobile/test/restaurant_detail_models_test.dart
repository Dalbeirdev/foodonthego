import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/domain/models/restaurant_detail.dart';

/// Reading a restaurant detail response.
void main() {
  /// A minimal body the parser will accept, so each test can vary one thing.
  Map<String, dynamic> body([Map<String, dynamic> extra = const {}]) =>
      <String, dynamic>{
        'id': 'restaurant-1',
        'name': 'Highway Spice Kitchen',
        'location': <String, dynamic>{'latitude': 27.6, 'longitude': 76.5},
        'route': <String, dynamic>{
          'proximity_meters': 900,
          'distance_ahead_meters': 68400,
        },
        ...extra,
      };

  group('what the screen can be built from', () {
    test('a response with no route relation is not a restaurant page', () {
      // Every figure this screen exists to show is measured against a journey.
      // Rendering the profile with a blank route card would be a generic
      // restaurant listing wearing FoodOnTheGo's chrome.
      expect(
        RestaurantDetail.fromJson(<String, dynamic>{
          'id': 'r',
          'name': 'Somewhere',
          'location': <String, dynamic>{'latitude': 1.0, 'longitude': 1.0},
        }),
        isNull,
      );
    });

    test('the route figures survive into the detail unchanged', () {
      final RestaurantDetail detail = RestaurantDetail.fromJson(
        body(<String, dynamic>{
          'route': <String, dynamic>{
            'proximity_meters': 900,
            'distance_ahead_meters': 68400,
            'detour_duration_seconds': 240,
            'time_ahead_seconds': 3600,
            'requires_backtracking': false,
          },
        }),
      )!;

      // A card saying "4 min detour" and this screen saying "9 min" is the
      // kind of disagreement a customer does not forgive.
      expect(detail.restaurant.route.detourDurationSeconds, 240);
      expect(detail.restaurant.route.distanceAheadMetres, 68400);
    });
  });

  group('optional things, honestly absent', () {
    test('an empty description is no description', () {
      final RestaurantDetail detail = RestaurantDetail.fromJson(
        body(<String, dynamic>{'description': '   '}),
      )!;

      expect(detail.description, isNull);
      expect(detail.hasDescription, isFalse);
    });

    test('a missing phone is not an empty string', () {
      expect(RestaurantDetail.fromJson(body())!.publicPhone, isNull);
    });

    test('no media is an empty gallery, not a null one', () {
      final RestaurantDetail detail = RestaurantDetail.fromJson(body())!;

      expect(detail.media, isEmpty);
      expect(detail.hasMedia, isFalse);
    });
  });

  group('media', () {
    test('an image with no url is dropped rather than rendered broken', () {
      final RestaurantDetail detail = RestaurantDetail.fromJson(
        body(<String, dynamic>{
          'media': <dynamic>[
            <String, dynamic>{'id': 'a', 'url': ''},
            <String, dynamic>{'id': 'b', 'url': 'https://cdn/b.jpg'},
          ],
        }),
      )!;

      expect(detail.media, hasLength(1));
      expect(detail.media.single.id, 'b');
    });

    test('a missing thumbnail falls back to the full image', () {
      final RestaurantDetail detail = RestaurantDetail.fromJson(
        body(<String, dynamic>{
          'media': <dynamic>[
            <String, dynamic>{'id': 'a', 'url': 'https://cdn/a.jpg'},
          ],
        }),
      )!;

      // A client that asked for a thumbnail and got null renders a hole.
      expect(detail.media.single.thumbnailUrl, 'https://cdn/a.jpg');
    });

    test('a blank caption is no caption', () {
      final RestaurantDetail detail = RestaurantDetail.fromJson(
        body(<String, dynamic>{
          'media': <dynamic>[
            <String, dynamic>{
              'id': 'a',
              'url': 'https://cdn/a.jpg',
              'alt_text': '  ',
            },
          ],
        }),
      )!;

      expect(detail.media.single.altText, isNull);
    });

    test('an intrinsic size becomes an aspect ratio, and a missing one does '
        'not', () {
      const RestaurantImage sized = RestaurantImage(
        id: 'a',
        url: 'u',
        thumbnailUrl: 'u',
        width: 1600,
        height: 900,
      );
      const RestaurantImage unsized = RestaurantImage(
        id: 'b',
        url: 'u',
        thumbnailUrl: 'u',
      );

      expect(sized.aspectRatio, closeTo(1.777, 0.001));
      expect(unsized.aspectRatio, isNull);
    });
  });

  group('ordering state', () {
    test('each state maps from its wire value', () {
      for (final RestaurantOrderingState state
          in RestaurantOrderingState.values) {
        expect(RestaurantOrderingState.fromWire(state.wire), state);
      }
    });

    test('a state this build has never heard of is not permission', () {
      // A newer server naming something new must not degrade to "go ahead".
      expect(
        RestaurantOrderingState.fromWire('OPEN_ON_TUESDAYS_ONLY'),
        RestaurantOrderingState.unavailable,
      );
      expect(
        RestaurantOrderingState.fromWire(null),
        RestaurantOrderingState.unavailable,
      );
    });

    test('only open-and-accepting can be ordered from', () {
      final RestaurantDetail open = RestaurantDetail.fromJson(
        body(<String, dynamic>{
          'ordering': <String, dynamic>{'state': 'OPEN_ACCEPTING'},
        }),
      )!;
      final RestaurantDetail paused = RestaurantDetail.fromJson(
        body(<String, dynamic>{
          'ordering': <String, dynamic>{'state': 'OPEN_PAUSED'},
        }),
      )!;

      expect(open.canOrder, isTrue);
      expect(paused.canOrder, isFalse);
    });
  });

  group('opening hours', () {
    test('a week comes back with its shut days in it', () {
      final RestaurantDetail detail = RestaurantDetail.fromJson(
        body(<String, dynamic>{
          'hours': <String, dynamic>{
            'timezone': 'Asia/Kolkata',
            'today': <String, dynamic>{'windows': <dynamic>[]},
            'week': <dynamic>[
              <String, dynamic>{
                'day_of_week': 0,
                'is_today': true,
                'windows': <dynamic>[],
              },
              <String, dynamic>{
                'day_of_week': 1,
                'windows': <dynamic>[
                  <String, dynamic>{
                    'opens_at': '09:00:00',
                    'closes_at': '17:00:00',
                  },
                ],
              },
            ],
          },
        }),
      )!;

      // A closed day is a row that says Closed, not a row that is missing.
      expect(detail.hours.week.first.isClosed, isTrue);
      expect(detail.hours.week.first.isToday, isTrue);
      expect(detail.hours.week[1].isClosed, isFalse);
    });

    test('an overnight window says so', () {
      final RestaurantDetail detail = RestaurantDetail.fromJson(
        body(<String, dynamic>{
          'hours': <String, dynamic>{
            'timezone': 'Asia/Kolkata',
            'today': <String, dynamic>{
              'windows': <dynamic>[
                <String, dynamic>{
                  'opens_at': '18:00:00',
                  'closes_at': '02:00:00',
                  'is_overnight': true,
                },
              ],
            },
          },
        }),
      )!;

      // "18:00 – 02:00" read quickly looks like a typo, so the screen says it.
      expect(detail.hours.today.single.isOvernight, isTrue);
    });

    test('an open restaurant knows when it closes', () {
      final RestaurantDetail detail = RestaurantDetail.fromJson(
        body(<String, dynamic>{
          'hours': <String, dynamic>{
            'timezone': 'Asia/Kolkata',
            'current_window': <String, dynamic>{
              'opens_at': '18:00:00',
              'closes_at': '02:00:00',
              'closes_at_utc': '2026-09-08T20:30:00Z',
            },
          },
        }),
      )!;

      expect(detail.hours.isOpenNow, isTrue);
      expect(detail.hours.closesAt, isNotNull);
    });

    test('a shut restaurant with no schedule says nothing rather than '
        'guessing', () {
      final RestaurantDetail detail = RestaurantDetail.fromJson(
        body(<String, dynamic>{
          'hours': <String, dynamic>{
            'timezone': 'Asia/Kolkata',
            'next_open_at': null,
          },
        }),
      )!;

      expect(detail.hours.nextOpenAt, isNull);
      expect(detail.hours.isOpenNow, isFalse);
      expect(detail.hours.hasSchedule, isFalse);
    });

    test('a day outside Monday to Sunday is dropped', () {
      final RestaurantDetail detail = RestaurantDetail.fromJson(
        body(<String, dynamic>{
          'hours': <String, dynamic>{
            'week': <dynamic>[
              <String, dynamic>{'day_of_week': 9, 'windows': <dynamic>[]},
            ],
          },
        }),
      )!;

      expect(detail.hours.week, isEmpty);
    });
  });

  group('freshness', () {
    test('the generated time is read so an offline screen can be honest', () {
      final RestaurantDetail detail = RestaurantDetail.fromJson(
        body(<String, dynamic>{'generated_at': '2026-09-07T10:00:00Z'}),
      )!;

      expect(detail.generatedAt.toUtc().hour, 10);
    });

    test('a missing generated time falls back to now rather than to null', () {
      final RestaurantDetail detail = RestaurantDetail.fromJson(body())!;

      // The screen divides by this to say "12 min ago". A null would be a
      // crash on a screen a customer is looking at.
      expect(
        DateTime.now().difference(detail.generatedAt).inSeconds,
        lessThan(5),
      );
    });
  });
}
