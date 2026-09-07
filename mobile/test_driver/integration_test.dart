// The host half of an `integration_test` run.
//
// `flutter test integration_test/` needs an attached handset. `flutter drive`
// does not: it pairs this file with a target under `integration_test/` and can
// run the same code against a browser, which is how these drivers are checked
// on a machine with no Android SDK and no emulator.
//
// A browser run proves the driver and the flow; it does not prove Android or
// iOS, and nothing here should be read as if it did.

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
