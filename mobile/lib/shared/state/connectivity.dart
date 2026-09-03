import 'dart:async';

/// Whether the device believes it can reach FoodOnTheGo.
enum ConnectivityStatus { online, offline }

/// The connectivity boundary.
///
/// FoodOnTheGo is used on highways, where losing signal is normal rather than
/// exceptional — so the shell treats offline as a first-class state from the
/// start instead of retrofitting it later.
///
/// Module 02 ships the abstraction and a manually-driven implementation. A real
/// one (platform connectivity plus a reachability probe, because "connected to
/// Wi-Fi" is not "can reach the API") arrives with the offline module. Nothing
/// in the UI changes when it does.
abstract interface class ConnectivityService {
  ConnectivityStatus get status;
  Stream<ConnectivityStatus> get changes;
  void dispose();
}

/// Always online. The safe production default until real detection exists —
/// claiming offline when we do not know would hide working functionality.
class AlwaysOnlineConnectivity implements ConnectivityService {
  const AlwaysOnlineConnectivity();

  @override
  ConnectivityStatus get status => ConnectivityStatus.online;

  @override
  Stream<ConnectivityStatus> get changes =>
      const Stream<ConnectivityStatus>.empty();

  @override
  void dispose() {}
}

/// Driven from code — used by the development harness and by tests to exercise
/// the offline banner without unplugging anything.
class ControllableConnectivity implements ConnectivityService {
  ControllableConnectivity([this._status = ConnectivityStatus.online]);

  ConnectivityStatus _status;
  final StreamController<ConnectivityStatus> _controller =
      StreamController<ConnectivityStatus>.broadcast();

  @override
  ConnectivityStatus get status => _status;

  @override
  Stream<ConnectivityStatus> get changes => _controller.stream;

  void set(ConnectivityStatus next) {
    if (_status == next) return;
    _status = next;
    _controller.add(next);
  }

  void toggle() => set(
    _status == ConnectivityStatus.online
        ? ConnectivityStatus.offline
        : ConnectivityStatus.online,
  );

  @override
  void dispose() => _controller.close();
}
