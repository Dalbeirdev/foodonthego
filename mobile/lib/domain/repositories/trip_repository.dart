import '../models/trip.dart';

/// Which slice of a customer's trips to ask for.
///
/// Three, matching the server's filter exactly. There is no "past": nothing in
/// Module 05 observes a journey happening, so a trip is either open or called
/// off, and inventing a third bucket the server cannot fill would put an empty
/// tab in front of somebody with no way to ever fill it.
enum TripScope {
  /// Still open — the server's `ROUTE_PENDING`.
  open('ROUTE_PENDING'),
  cancelled('CANCELLED'),

  /// No filter at all.
  all(null);

  const TripScope(this.status);

  /// The `status` query value, or null to ask for everything.
  ///
  /// Deliberately the server's own status strings rather than words of this
  /// app's own. A client vocabulary that has to be translated at the edge is a
  /// translation somebody eventually gets wrong in one direction only — which
  /// is exactly what happened here: an earlier version sent `scope=open`, the
  /// server filters on `status`, and the unknown parameter was ignored, so
  /// every list came back unfiltered and discarded trips sat in the open list.
  final String? status;
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
