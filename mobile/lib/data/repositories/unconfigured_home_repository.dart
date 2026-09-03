import '../../domain/models/customer_summary.dart';
import '../../domain/models/home_dashboard.dart';
import '../../domain/repositories/home_repository.dart';

/// The production implementation — until an API exists.
///
/// It returns a dashboard with no journey and no order rather than pretending:
/// a real customer sees the new-customer home, which is the truthful state for
/// an account with nothing in it. It never invents a trip or an order.
///
/// Module 08 replaces this with an implementation backed by `/api/v1`. The name
/// is deliberate — anyone reading a stack trace should see immediately that no
/// backend is wired up.
class UnconfiguredHomeRepository implements HomeRepository {
  const UnconfiguredHomeRepository({this.customerName = 'there'});

  final String customerName;

  @override
  Future<HomeDashboard> loadDashboard() async {
    return HomeDashboard(customer: CustomerSummary(fullName: customerName));
  }
}
