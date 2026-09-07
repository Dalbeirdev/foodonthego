// Signs a test persona in on the host, and prints the token the on-device runs
// need.
//
// A handset cannot complete the sign-in flow by itself. The development OTP
// provider writes the code to a log file on the *server* and there is
// deliberately no endpoint that hands it back over HTTP — that absence is what
// makes that provider unusable in production, and it is not going to be
// loosened to make a test convenient. So the code is read here, on the machine
// that has the log, and the resulting session token is passed to the device.
//
// The token is an ordinary Sanctum token for an ordinary test persona. It
// carries no more authority than the customer it belongs to, and it belongs to
// somebody who exists only in a development database.
//
//   php artisan serve --host=0.0.0.0 --port=8000
//   dart run --define=FOTG_API_BASE_URL=http://127.0.0.1:8000 tool/issue_token.dart
//
// Then, with a device attached:
//
//   flutter test integration_test/ \
//     --dart-define=FOTG_API_BASE_URL=http://<the host's LAN address>:8000 \
//     --dart-define=FOTG_TEST_TOKEN=<what this printed>

import 'dart:io';

import 'package:foodonthego/core/config/api_config.dart';

import 'support/smoke_support.dart';

/// A number of its own, so a device run and a smoke run are never signing in as
/// the same person at the same time and tripping each other's OTP cooldown.
const String _phone = '9999900911';

void main(List<String> args) async {
  final String national = args.isNotEmpty ? args.first : _phone;

  stdout.writeln('FoodOnTheGo — issuing a device test token');
  stdout.writeln('Backend: ${ApiConfig.baseUrl}');
  stdout.writeln('');

  final Session session = await signIn('Rahul', 'Sharma', national);

  stdout.writeln('  persona   Rahul Sharma  +91 $national');
  stdout.writeln('  token     ${session.token}');
  stdout.writeln('');
  stdout.writeln('Run the device tests with:');
  stdout.writeln('');
  stdout.writeln('  flutter test integration_test/ \\');
  stdout.writeln(
    '    --dart-define=FOTG_API_BASE_URL=<host reachable from the device> \\',
  );
  stdout.writeln('    --dart-define=FOTG_TEST_TOKEN=${session.token}');
  stdout.writeln('');
  stdout.writeln(
    'The device needs a URL it can actually reach: 10.0.2.2 for an Android\n'
    'emulator, 127.0.0.1 for an iOS simulator, and the host machine\'s LAN\n'
    'address for a physical handset — with the backend bound to 0.0.0.0.',
  );

  session.close();
}
