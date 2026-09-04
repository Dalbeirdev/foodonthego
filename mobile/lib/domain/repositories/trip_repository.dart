import '../models/trip.dart';

/// Everything the app can do with a customer's journeys.
///
/// Note what is absent: there is no `delete`. A journey is cancelled, never
/// removed — the record of what somebody planned is history, and a later
/// module's orders point at it. A client method that could delete one would be a
/// method with no endpoint behind it.
abstract interface class TripRepository {
  Future<List<Trip>> trips({TripScope scope = TripScope.upcoming});

  /// The soonest journey still ahead, or null.
  ///
  /// Null is an ordinary answer — a customer with nothing planned — and the home
  /// screen renders nothing for journeys when it gets one.
  Future<Trip?> nextTrip();

  Future<Trip> trip(String id);

  Future<Trip> planTrip(TripDraft draft);

  Future<Trip> updateTrip(String id, TripDraft draft);

  Future<Trip> cancelTrip(String id, {String? reason});
}
