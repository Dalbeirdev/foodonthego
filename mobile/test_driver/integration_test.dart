// The host half of an `integration_test` run.
//
// `flutter test integration_test/` needs an attached handset. `flutter drive`
// pairs this file with a target under `integration_test/` and can run it
// against a browser instead.
//
// TWO WARNINGS, BOTH LEARNED THE HARD WAY
//
// `flutter drive` was observed exiting 0 and printing "All tests passed." while
// the test body never ran at all — with `-d web-server --browser-name=chrome`
// and with `-d chrome`. See KI-013 in docs/13-known-issues.md. **Do not accept
// a pass from this path without first watching a negative control fail**:
// remove FOTG_TEST_TOKEN and confirm the run goes red before believing a run
// that goes green.
//
// And even a genuine browser pass proves the driver and the flow only. It says
// nothing about Android or iOS, and nothing here should be read as if it did.

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
