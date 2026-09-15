import '../../domain/models/customer_summary.dart';
import '../../domain/models/home_dashboard.dart';
import '../../domain/repositories/home_repository.dart';

/// The production implementation — until an API exists.
///
/// It returns a dashboard with no journey and no order rather than pretending:
/// a real customer sees the new-customer home, which is the truthful state for
/// an account with nothing in it. It never invents a trip or an order.
///
/// **The APIs it was waiting for now exist (KI-035).** This comment used to say
/// Module 08 would replace it; Module 08 was search and ranking, and this is
/// still here. `ApiTripRepository.currentTrip()` has answered the journey
/// question since Module 05 and `ApiOrderRepository.mine()` has answered the
/// order question since Module 16.
///
/// So this class is no longer refusing to invent data — it is withholding data
/// the app already has, which is a different thing and a worse one. A customer
/// whose food is being cooked sees the new-customer home while the Orders tab
/// lists that order and the tracking screen tracks it.
///
/// It stays until three product questions are answered, because wiring it
/// without them would mean this screen inventing a policy: which of several
/// active orders a single card shows, how old a trip may be and still be
/// "current", and whether the card may show a countdown at all before Module 18
/// builds an ETA. Read the name as "waiting for a decision", not "waiting for
/// an API".
class UnconfiguredHomeRepository implements HomeRepository {
  const UnconfiguredHomeRepository({this.customerName = 'there'});

  final String customerName;

  @override
  Future<HomeDashboard> loadDashboard() async {
    return HomeDashboard(customer: CustomerSummary(fullName: customerName));
  }
}
