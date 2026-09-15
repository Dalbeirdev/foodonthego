// The Module 04 end-to-end run: this app's own network layer against a running
// Laravel backend and a real MySQL database. No mocks, no fakes, no stubs.
//
// It walks the complete example the module specification asks for — Rahul edits
// his profile, saves Home and Work, moves the default, edits, deletes, then
// Ananya tries to reach his addresses and is refused every way.
//
// Run it with the backend serving and OTP_PROVIDER=log:
//
//   php artisan serve --host=127.0.0.1 --port=8000
//   dart run tool/profile_addresses_smoke.dart
//
// Deliberately a `dart run` and not a `flutter test`: flutter_test replaces
// HttpClient with a mock, so a "test" there could never make a real request.

import 'dart:convert';
import 'dart:io';

import 'package:foodonthego/core/config/api_config.dart';
import 'package:foodonthego/core/network/api_client.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/data/repositories/api_auth_repository.dart';
import 'package:foodonthego/data/repositories/api_customer_repository.dart';
import 'package:foodonthego/domain/models/auth_models.dart';
import 'package:foodonthego/domain/models/customer.dart';
import 'package:foodonthego/domain/models/saved_address.dart';

/// Numbers from the Indian range reserved for testing and documentation, so a
/// code can never reach a real handset even if a real provider were configured.
const String _rahulPhone = '9999900201';
const String _ananyaPhone = '9999900202';
const String _countryCode = '91';

const String _otpLog = '../backend/storage/logs/otp-development.log';

int _passed = 0;
int _failed = 0;

/// One signed-in customer: their own client, repositories and token.
class Session {
  Session(this.name, this.token)
    : client = ApiClient(tokenReader: () async => token),
      _repository = null;

  final String name;
  final String token;
  final ApiClient client;
  ApiCustomerRepository? _repository;

  ApiCustomerRepository get customer =>
      _repository ??= ApiCustomerRepository(client);

  void close() => client.close();
}

void main(List<String> args) async {
  stdout.writeln('FoodOnTheGo — Module 04 integration run');
  stdout.writeln('Backend: ${ApiConfig.baseUrl}');
  stdout.writeln('');

  final Session rahul = await _signIn('Rahul', 'Sharma', _rahulPhone);
  final Session ananya = await _signIn('Ananya', 'Mehta', _ananyaPhone);

  await _clearAddresses(rahul);
  await _clearAddresses(ananya);

  // --- 1. profile ---------------------------------------------------------
  final Customer before = await rahul.customer.profile();
  _check('the profile comes back from the real API', () {
    _expect(before.phone, '+91$_rahulPhone');
    _expect(before.phoneVerified, true);
  });

  final Customer updated = await rahul.customer.updateProfile(
    firstName: 'Rahul',
    lastName: 'S. Sharma',
    email: 'rahul.test@foodonthego.example',
  );
  _check('a profile edit persists', () {
    _expect(updated.fullName, 'Rahul S. Sharma');
    _expect(updated.email, 'rahul.test@foodonthego.example');
  });

  final Customer reread = await rahul.customer.profile();
  _check('a fresh read returns the edited profile', () {
    _expect(reread.fullName, 'Rahul S. Sharma');
  });

  await _checkAsync(
    'the verified number cannot be changed by a PATCH',
    () async {
      // Straight at the endpoint, past the app's own model, because the app has no
      // way to express this and the point is that the server refuses it anyway.
      final Map<String, dynamic> body = await rahul.client.patch(
        '/customer/profile',
        body: <String, dynamic>{
          'first_name': 'Rahul',
          'phone_e164': '+919999999999',
          'phone_verified_at': null,
          'role': 'super_admin',
          'status': 'suspended',
        },
        authenticated: true,
      );

      _expect(body['phone'], '+91$_rahulPhone');
      _expect(body['phone_verified'], true);
      _expect(body['status'], 'active');
    },
  );

  await _checkAsync('an email change never claims to be verified', () async {
    final Customer changed = await rahul.customer.updateProfile(
      firstName: 'Rahul',
      lastName: 'S. Sharma',
      email: 'rahul.new@foodonthego.example',
    );
    _expect(changed.emailVerified, false);

    await rahul.customer.updateProfile(
      firstName: 'Rahul',
      lastName: 'S. Sharma',
      email: 'rahul.test@foodonthego.example',
    );
  });

  // --- 2. first address ----------------------------------------------------
  final List<SavedAddress> empty = await rahul.customer.addresses();
  _check(
    'a new customer has no saved addresses',
    () => _expect(empty.length, 0),
  );

  final SavedAddress home = await rahul.customer.createAddress(
    const AddressDraft(
      type: AddressType.home,
      addressLine1: '12 Green Park Road',
      addressLine2: 'Green Park',
      landmark: 'Near Green Park Metro',
      city: 'New Delhi',
      state: 'Delhi',
      postalCode: '110016',
      countryCode: 'IN',
    ),
  );

  _check('the first saved address becomes the default', () {
    _expect(home.isDefault, true);
    _expect(home.label, 'Home');
    _expect(
      home.formattedAddress,
      '12 Green Park Road, Green Park, New Delhi, Delhi 110016, IN',
    );
  });

  _check('coordinates are null, not invented from the text', () {
    _expect(home.latitude, null);
    _expect(home.longitude, null);
    _expect(home.placeId, null);
  });

  // --- 3. second address ---------------------------------------------------
  final SavedAddress work = await rahul.customer.createAddress(
    const AddressDraft(
      type: AddressType.work,
      addressLine1: 'Connaught Place',
      city: 'New Delhi',
      state: 'Delhi',
      postalCode: '110001',
      countryCode: 'IN',
    ),
  );

  _check('a second address does not steal the default', () {
    _expect(work.isDefault, false);
  });

  await _checkAsync('the list is default first', () async {
    final List<SavedAddress> list = await rahul.customer.addresses();
    _expect(list.length, 2);
    _expect(list.first.label, 'Home');
    _expect(list.first.isDefault, true);
  });

  // --- 4. move the default -------------------------------------------------
  await rahul.customer.makeDefault(work.id);

  await _checkAsync('setting a new default clears the old one', () async {
    final List<SavedAddress> list = await rahul.customer.addresses();
    final int defaults = list.where((SavedAddress a) => a.isDefault).length;

    _expect(defaults, 1);
    _expect(list.first.label, 'Work');
  });

  // --- 5. edit -------------------------------------------------------------
  final SavedAddress edited = await rahul.customer.updateAddress(
    work.id,
    const AddressDraft(
      type: AddressType.work,
      addressLine1: 'Connaught Place',
      landmark: 'Block A, near the inner circle',
      city: 'New Delhi',
      state: 'Delhi',
      postalCode: '110001',
      countryCode: 'IN',
    ),
  );

  _check('an edit persists and keeps the default', () {
    _expect(edited.landmark, 'Block A, near the inner circle');
    _expect(edited.isDefault, true);
  });

  // --- 6. a third, then delete the default ---------------------------------
  final SavedAddress other = await rahul.customer.createAddress(
    const AddressDraft(
      type: AddressType.other,
      label: "Parents' House",
      addressLine1: 'Plot 14, Civil Lines',
      city: 'Jaipur',
      state: 'Rajasthan',
      postalCode: '302006',
      countryCode: 'IN',
    ),
  );
  _check('a custom label is kept as the customer wrote it', () {
    _expect(other.label, "Parents' House");
  });

  await rahul.customer.deleteAddress(edited.id);

  await _checkAsync('deleting the default promotes a replacement', () async {
    final List<SavedAddress> list = await rahul.customer.addresses();

    _expect(list.length, 2);
    _expect(list.where((SavedAddress a) => a.isDefault).length, 1);
    _expect(list.first.label, "Parents' House");
  });

  // --- 7. IDOR -------------------------------------------------------------
  final SavedAddress hers = await ananya.customer.createAddress(
    const AddressDraft(
      type: AddressType.work,
      addressLine1: 'Cyber City',
      city: 'Gurugram',
      state: 'Haryana',
      postalCode: '122002',
      countryCode: 'IN',
    ),
  );

  await _checkAsync("Rahul cannot read Ananya's address", () async {
    try {
      await rahul.customer.addresses();
      final Map<String, dynamic> leaked = await rahul.client.get(
        '/customer/addresses/${hers.id}',
        authenticated: true,
      );
      throw "Read another customer's address: $leaked";
    } on ApiException catch (error) {
      _expect(error.code, ApiErrorCode.addressNotFound);
      _expect(error.status, 404);
    }
  });

  await _checkAsync("Rahul cannot update Ananya's address", () async {
    try {
      await rahul.customer.updateAddress(
        hers.id,
        const AddressDraft(
          type: AddressType.work,
          addressLine1: 'Rewritten',
          city: 'Nowhere',
          state: 'Nowhere',
          postalCode: '110001',
          countryCode: 'IN',
        ),
      );
      throw "Updated another customer's address";
    } on ApiException catch (error) {
      _expect(error.code, ApiErrorCode.addressNotFound);
    }
  });

  await _checkAsync("Rahul cannot delete Ananya's address", () async {
    try {
      await rahul.customer.deleteAddress(hers.id);
      throw "Deleted another customer's address";
    } on ApiException catch (error) {
      _expect(error.code, ApiErrorCode.addressNotFound);
    }
  });

  await _checkAsync("Rahul cannot make Ananya's address his default", () async {
    try {
      await rahul.customer.makeDefault(hers.id);
      throw "Defaulted another customer's address";
    } on ApiException catch (error) {
      _expect(error.code, ApiErrorCode.addressNotFound);
    }
  });

  await _checkAsync("Ananya's address is untouched", () async {
    final List<SavedAddress> list = await ananya.customer.addresses();

    _expect(list.length, 1);
    _expect(list.first.addressLine1, 'Cyber City');
    _expect(list.first.isDefault, true);
  });

  await _checkAsync(
    'a create naming another customer belongs to the caller',
    () async {
      final Map<String, dynamic> created = await rahul.client.post(
        '/customer/addresses',
        body: <String, dynamic>{
          'type': 'OTHER',
          'label': 'Injected',
          'address_line_1': 'Somewhere Else',
          'city': 'New Delhi',
          'state': 'Delhi',
          'postal_code': '110001',
          'country_code': 'IN',
          // Every shape somebody might try.
          'customer_id': 999999,
          'user_id': 999999,
          'created_by': 999999,
        },
        authenticated: true,
      );

      // It came back on Rahul's list, so it is his.
      final List<SavedAddress> mine = await rahul.customer.addresses();
      _expect(mine.any((SavedAddress a) => a.id == created['id']), true);

      final List<SavedAddress> theirs = await ananya.customer.addresses();
      _expect(theirs.length, 1);

      await rahul.customer.deleteAddress(created['id'] as String);
    },
  );

  // --- 8. validation, at the real server -----------------------------------
  await _checkAsync('an invalid PIN code is refused', () async {
    try {
      await rahul.customer.createAddress(
        const AddressDraft(
          type: AddressType.home,
          addressLine1: 'A Road',
          city: 'New Delhi',
          state: 'Delhi',
          postalCode: '11001',
          countryCode: 'IN',
        ),
      );
      throw 'An invalid PIN code was accepted';
    } on ApiException catch (error) {
      _expect(error.code, ApiErrorCode.validationFailed);
      if (!error.fieldErrors.containsKey('postal_code')) {
        throw 'The error did not name the field';
      }
    }
  });

  await _checkAsync('an unnamed Other address is refused', () async {
    try {
      await rahul.customer.createAddress(
        const AddressDraft(
          type: AddressType.other,
          addressLine1: 'A Road',
          city: 'New Delhi',
          state: 'Delhi',
          postalCode: '110001',
          countryCode: 'IN',
        ),
      );
      throw 'An unnamed Other address was accepted';
    } on ApiException catch (error) {
      _expect(error.code, ApiErrorCode.validationFailed);
    }
  });

  // --- 9. session ----------------------------------------------------------
  await _checkAsync('an unauthenticated call reaches no addresses', () async {
    final ApiClient anonymous = ApiClient();
    try {
      await anonymous.getList('/customer/addresses', authenticated: true);
      throw 'A protected endpoint answered without a token';
    } on ApiException catch (error) {
      _expect(error.code, ApiErrorCode.unauthenticated);
    } finally {
      anonymous.close();
    }
  });

  await _checkAsync('a revoked session stops reaching addresses', () async {
    final Session throwaway = await _signIn('Temp', null, _rahulPhone);
    await ApiAuthRepository(throwaway.client).logout();

    try {
      await throwaway.customer.addresses();
      throw 'A revoked token still worked';
    } on ApiException catch (error) {
      _expect(error.code, ApiErrorCode.unauthenticated);
    } finally {
      throwaway.close();
    }
  });

  rahul.close();
  ananya.close();

  stdout.writeln('');
  stdout.writeln('$_passed passed, $_failed failed');
  exit(_failed == 0 ? 0 : 1);
}

/// Signs a customer in for real, registering them if the number is new.
Future<Session> _signIn(
  String firstName,
  String? lastName,
  String national,
) async {
  final ApiClient client = ApiClient();
  final ApiAuthRepository auth = ApiAuthRepository(client);

  final int offset = await _logLength();
  await _requestCode(auth, national);
  final String code = await _readCodeAfter(offset);

  final OtpVerifyResult result = await auth.verifyOtp(
    phone: national,
    countryCode: _countryCode,
    code: code,
  );

  final AuthSession session = switch (result) {
    OtpSignedIn(session: final AuthSession s) => s,
    OtpRegistrationRequired(registrationToken: final String token) =>
      await auth.register(
        registrationToken: token,
        firstName: firstName,
        lastName: lastName,
      ),
  };

  client.close();

  return Session(firstName, session.accessToken);
}

/// Leaves each customer with a clean slate, so a re-run starts where the last
/// one did.
Future<void> _clearAddresses(Session session) async {
  for (final SavedAddress address in await session.customer.addresses()) {
    await session.customer.deleteAddress(address.id);
  }
}

Future<OtpRequestResult> _requestCode(
  ApiAuthRepository auth,
  String national,
) async {
  try {
    return await auth.requestOtp(phone: national, countryCode: _countryCode);
  } on ApiException catch (error) {
    if (error.code == ApiErrorCode.otpRateLimited) {
      stderr.writeln(
        'The per-phone request limit is spent for +91$national. It resets in '
        '${error.retryAfterSeconds ?? '?'}s.',
      );
      exit(2);
    }

    if (error.code != ApiErrorCode.otpResendTooSoon) rethrow;

    final int wait = (error.retryAfterSeconds ?? 30) + 1;
    stdout.writeln('  ..    resend cooldown is active; waiting ${wait}s');
    await Future<void>.delayed(Duration(seconds: wait));

    return auth.requestOtp(phone: national, countryCode: _countryCode);
  }
}

Future<int> _logLength() async {
  final File file = File(_otpLog);
  return file.existsSync() ? file.lengthSync() : 0;
}

Future<String> _readCodeAfter(int offset) async {
  final File file = File(_otpLog);
  if (!file.existsSync()) {
    throw StateError('No development OTP log at $_otpLog.');
  }

  // Sliced as bytes then decoded: the mask characters in this log are three
  // bytes each in UTF-8 but one UTF-16 unit in a Dart string.
  final List<int> bytes = await file.readAsBytes();
  final String fresh = utf8.decode(
    bytes.sublist(offset.clamp(0, bytes.length)),
    allowMalformed: true,
  );

  final Iterable<RegExpMatch> matches = RegExp(r'"code":"(\d{6})"')
      .allMatches(fresh);

  if (matches.isEmpty) {
    throw StateError(
      'No OTP found in the development log since the run started.',
    );
  }

  return matches.last.group(1)!;
}

void _expect(Object? actual, Object? expected) {
  if (actual != expected) throw 'expected $expected, got $actual';
}

void _check(String description, void Function() body) {
  try {
    body();
    _passed++;
    stdout.writeln('  PASS  $description');
  } catch (error) {
    _failed++;
    stdout.writeln('  FAIL  $description\n        $error');
  }
}

Future<void> _checkAsync(
  String description,
  Future<void> Function() body,
) async {
  try {
    await body();
    _passed++;
    stdout.writeln('  PASS  $description');
  } catch (error) {
    _failed++;
    stdout.writeln('  FAIL  $description\n        $error');
  }
}
