import '../models/trip.dart';

/// Which slice of a customer's trips to ask for.
///
/// Three, matching the server's filter exactly. There is no "past": nothing in
/// Module 05 observes a journey happening, so a trip is either open or called
/// off, and inventing a third bucket the server cannot fill would put an empty
/// tab in front of somebody with no way to ever fill it.
enum TripScope {
  open('open'),
  cancelled('cancelled'),
  all('all');

  const TripScope(this.wire);

  final String wire;
}

/// Everything the app can do with a customer's trips.
///
/// Note the absences. There is no `delete` — a trip is discarded, never erased,
/// and later modules' orders point at it. There is no `update`: Module 05 creates
/// a trip from two chosen places and stops, and an edit method with no endpoint
/// behind it is a method somebody will call.
///
/// No method takes a customer id. Ownership is the shape of the API, not a
/// parameter of it: the signed-in session decides whose trips these are, and
/// there is nothing here a modified client could point at somebody else.
abstract interface class TripRepository {
  Future<List<Trip>> trips({TripScope scope = TripScope.open});

  /// The most recent open trip, or null.
  ///
  /// Null is an ordinary answer — a customer who has not planned anything — and
  /// the home screen renders its invitation rather than an error when it gets
  /// one.
  Future<Trip?> currentTrip();

  Future<Trip> trip(String id);

  Future<Trip> createTrip(TripDraft draft);

  /// Called off. The record stays; only its status changes.
  Future<Trip> discardTrip(String id);
}
