import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foodonthego/core/network/api_error_code.dart';
import 'package:foodonthego/core/network/api_exception.dart';
import 'package:foodonthego/domain/models/customer_summary.dart';
import 'package:foodonthego/domain/models/home_dashboard.dart';

import 'support/harness.dart';

const HomeDashboard _dashboard = HomeDashboard(
  customer: CustomerSummary(fullName: 'Ravi Kumar'),
);

/// The sign-in flow as a customer walks it, and every way it can go wrong.
void main() {
  Future<FakeAuthRepository> pumpSignedOut(
    WidgetTester tester, {
    FakeAuthRepository? auth,
    String initialLocation = '/',
  }) async {
    usePhoneSurface(tester);
    final FakeAuthRepository repository = auth ?? FakeAuthRepository();

    await tester.pumpWidget(
      wrapApp(
        repository: StubHomeRepository.value(_dashboard),
        auth: repository,
        signedIn: false,
        initialLocation: initialLocation,
      ),
    );
    await tester.pumpAndSettle();

    return repository;
  }

  Future<void> enterPhone(WidgetTester tester, String number) async {
    await tester.enterText(find.byType(TextField).first, number);
    await tester.pump();
  }

  Future<void> tapSendCode(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Send code'));
    await tester.pumpAndSettle();
  }

  Future<void> enterCode(WidgetTester tester, String code) async {
    await tester.enterText(find.byType(TextField).first, code);
    await tester.pumpAndSettle();
  }

  group('the unauthenticated entry point', () {
    testWidgets('a fresh install lands on welcome, not on home', (
      WidgetTester tester,
    ) async {
      await pumpSignedOut(tester);

      expect(find.text('Eat well on the road'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('every protected route redirects to welcome', (
      WidgetTester tester,
    ) async {
      for (final String route in <String>[
        '/',
        '/trips',
        '/orders',
        '/notifications',
        '/profile',
      ]) {
        await pumpSignedOut(tester, initialLocation: route);

        expect(
          find.text('Eat well on the road'),
          findsOneWidget,
          reason: '$route should not be reachable while signed out',
        );
      }
    });

    testWidgets('welcome leads to the phone screen', (
      WidgetTester tester,
    ) async {
      await pumpSignedOut(tester);

      await tester.tap(find.text('Continue with mobile number'));
      await tester.pumpAndSettle();

      expect(find.text('What is your mobile number?'), findsOneWidget);
    });
  });

  group('phone entry', () {
    testWidgets('the action stays disabled until the number is plausible', (
      WidgetTester tester,
    ) async {
      await pumpSignedOut(tester, initialLocation: '/auth/phone');

      final Finder button = find.widgetWithText(FilledButton, 'Send code');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      await enterPhone(tester, '98765');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);

      await enterPhone(tester, '9876543210');
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    });

    testWidgets('a landline prefix is not accepted locally either', (
      WidgetTester tester,
    ) async {
      await pumpSignedOut(tester, initialLocation: '/auth/phone');

      // 2 is not an Indian mobile prefix, so the SMS could never arrive.
      await enterPhone(tester, '2876543210');

      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Send code'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('a trunk zero is stripped before the number is sent', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository auth = await pumpSignedOut(
        tester,
        initialLocation: '/auth/phone',
      );

      await enterPhone(tester, '09876543210');
      await tapSendCode(tester);

      // "09876543210" and "9876543210" are one subscriber, not two accounts.
      expect(auth.requestedPhones, <String>['+919876543210']);
    });

    testWidgets('the country can be changed', (WidgetTester tester) async {
      final FakeAuthRepository auth = await pumpSignedOut(
        tester,
        initialLocation: '/auth/phone',
      );

      await tester.tap(find.text('+91'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('United Arab Emirates'));
      await tester.pumpAndSettle();

      await enterPhone(tester, '501234567');
      await tapSendCode(tester);

      expect(auth.requestedPhones, <String>['+971501234567']);
    });

    testWidgets('a server rejection is shown against the field', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository auth = FakeAuthRepository()
        ..nextRequestError = const ApiException(
          code: ApiErrorCode.invalidPhone,
          message: 'Enter a valid mobile number.',
          status: 422,
        );

      await pumpSignedOut(tester, auth: auth, initialLocation: '/auth/phone');

      await enterPhone(tester, '9876543210');
      await tapSendCode(tester);

      expect(find.text('Enter a valid mobile number.'), findsOneWidget);
      expect(find.text('Enter the code'), findsNothing);
    });

    testWidgets(
      'losing the network says so rather than showing a stack trace',
      (WidgetTester tester) async {
        final FakeAuthRepository auth = FakeAuthRepository()
          ..nextRequestError = const ApiException.network();

        await pumpSignedOut(tester, auth: auth, initialLocation: '/auth/phone');

        await enterPhone(tester, '9876543210');
        await tapSendCode(tester);

        expect(
          find.text('No connection. Check your signal and try again.'),
          findsOneWidget,
        );
      },
    );
  });

  group('code verification', () {
    Future<FakeAuthRepository> reachOtpScreen(
      WidgetTester tester, {
      FakeAuthRepository? auth,
    }) async {
      final FakeAuthRepository repository = await pumpSignedOut(
        tester,
        auth: auth,
        initialLocation: '/auth/phone',
      );

      await enterPhone(tester, '9876543210');
      await tapSendCode(tester);

      return repository;
    }

    testWidgets('the screen confirms the masked number the server understood', (
      WidgetTester tester,
    ) async {
      await reachOtpScreen(tester);

      expect(find.text('Enter the code'), findsOneWidget);
      expect(find.text('Sent to +91 ••••••3210'), findsOneWidget);
      // Never the full number, even to its owner.
      expect(find.textContaining('9876543210'), findsNothing);
    });

    testWidgets('a correct code signs in and reveals the app', (
      WidgetTester tester,
    ) async {
      await reachOtpScreen(tester);

      await enterCode(tester, '123456');

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Enter the code'), findsNothing);
    });

    testWidgets('a wrong code is rejected without leaving the screen', (
      WidgetTester tester,
    ) async {
      await reachOtpScreen(tester);

      await enterCode(tester, '000000');

      expect(
        find.text("That code isn't correct. Check it and try again."),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('an expired code offers a resend instead of another attempt', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository auth = FakeAuthRepository();
      await reachOtpScreen(tester, auth: auth);

      auth.nextVerifyError = const ApiException(
        code: ApiErrorCode.otpExpired,
        message: 'That code has expired.',
        status: 422,
      );

      await enterCode(tester, '123456');

      expect(
        find.text('That code has expired. Request a new one.'),
        findsOneWidget,
      );
      // The countdown is cleared, so the useful action is available now.
      expect(find.text('Resend code'), findsOneWidget);
    });

    testWidgets('too many attempts is reported as its own state', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository auth = FakeAuthRepository();
      await reachOtpScreen(tester, auth: auth);

      auth.nextVerifyError = const ApiException(
        code: ApiErrorCode.otpTooManyAttempts,
        message: 'Too many incorrect attempts.',
        status: 422,
      );

      await enterCode(tester, '123456');

      expect(
        find.text('Too many incorrect attempts. Request a new code.'),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('a suspended account cannot get past a correct code', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository auth = FakeAuthRepository();
      await reachOtpScreen(tester, auth: auth);

      auth.nextVerifyError = const ApiException(
        code: ApiErrorCode.accountSuspended,
        message: 'Your account is currently unavailable.',
        status: 403,
      );

      await enterCode(tester, '123456');

      expect(
        find.text(
          'Your account is currently unavailable. Please contact support.',
        ),
        findsOneWidget,
      );
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('resend is on a countdown the customer can see', (
      WidgetTester tester,
    ) async {
      // The countdown reads a clock rather than decrementing a counter, so that
      // backgrounding the app to read the SMS does not stop it. That means the
      // test has to move the clock, not just pump frames.
      final DateTime start = DateTime(2026, 9, 3, 12);
      DateTime now = start;

      await withClock(Clock(() => now), () async {
        final FakeAuthRepository auth = FakeAuthRepository()
          ..resendAvailableInSeconds = 3;
        await reachOtpScreen(tester, auth: auth);

        expect(find.text('Resend code in 3s'), findsOneWidget);
        expect(find.text('Resend code'), findsNothing);

        now = start.add(const Duration(seconds: 3));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Resend code'), findsOneWidget);

        await tester.tap(find.text('Resend code'));
        await tester.pumpAndSettle();

        expect(auth.requestCount, 2);
      });
    });

    testWidgets('the countdown keeps running while the app is backgrounded', (
      WidgetTester tester,
    ) async {
      final DateTime start = DateTime(2026, 9, 3, 12);
      DateTime now = start;

      await withClock(Clock(() => now), () async {
        final FakeAuthRepository auth = FakeAuthRepository()
          ..resendAvailableInSeconds = 30;
        await reachOtpScreen(tester, auth: auth);

        expect(find.text('Resend code in 30s'), findsOneWidget);

        // Both platforms suspend timers for a backgrounded app, so no ticks
        // happen while the customer is in their SMS app. Wall-clock time still
        // passes, and on return the countdown must reflect that rather than
        // resuming from where it stopped.
        now = start.add(const Duration(seconds: 25));
        await tester.pump(const Duration(seconds: 1));

        expect(find.text('Resend code in 5s'), findsOneWidget);
      });
    });

    testWidgets('the server wins when it says a resend is too soon', (
      WidgetTester tester,
    ) async {
      final DateTime now = DateTime(2026, 9, 3, 12);

      await withClock(Clock(() => now), () async {
        final FakeAuthRepository auth = FakeAuthRepository()
          ..resendAvailableInSeconds = 0;
        await reachOtpScreen(tester, auth: auth);

        auth.nextRequestError = const ApiException(
          code: ApiErrorCode.otpResendTooSoon,
          message: 'Please wait.',
          status: 429,
          details: <String, dynamic>{'retry_after_seconds': 25},
        );

        await tester.tap(find.text('Resend code'));
        await tester.pumpAndSettle();

        // The device countdown is corrected to what the server said, not to
        // what this device believed.
        expect(find.text('Resend code in 25s'), findsOneWidget);
      });
    });

    testWidgets('change number returns to phone entry', (
      WidgetTester tester,
    ) async {
      await reachOtpScreen(tester);

      await tester.tap(find.text('Change number'));
      await tester.pumpAndSettle();

      expect(find.text('What is your mobile number?'), findsOneWidget);
    });

    testWidgets('the field takes digits only and stops at the code length', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository auth = FakeAuthRepository();
      await reachOtpScreen(tester, auth: auth);

      await tester.enterText(find.byType(TextField).first, 'ab12cd34ef56gh78');
      await tester.pumpAndSettle();

      // Six digits survive, and reaching six auto-submits.
      expect(auth.submittedCodes, <String>['123456']);
    });
  });

  group('registration', () {
    Future<FakeAuthRepository> reachRegistration(WidgetTester tester) async {
      final FakeAuthRepository auth = FakeAuthRepository()
        ..registrationRequired = true;

      await pumpSignedOut(tester, auth: auth, initialLocation: '/auth/phone');
      await enterPhone(tester, '9876543210');
      await tapSendCode(tester);
      await enterCode(tester, '123456');

      return auth;
    }

    testWidgets('a new number is asked for a name, not signed straight in', (
      WidgetTester tester,
    ) async {
      await reachRegistration(tester);

      expect(find.text('Tell us your name'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('the verified number is shown back but never re-entered', (
      WidgetTester tester,
    ) async {
      await reachRegistration(tester);

      expect(find.text('+91 ••••••3210'), findsOneWidget);
      // No phone field on this screen at all: there is nowhere for a caller to
      // substitute a different number.
      expect(find.widgetWithText(TextFormField, 'Mobile number'), findsNothing);
    });

    testWidgets('a first name is required and the rest is not', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository auth = await reachRegistration(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your first name.'), findsOneWidget);
      expect(auth.registeredWith, isNull);

      await tester.enterText(find.byType(TextFormField).first, 'Ravi');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();

      expect(auth.registeredWith?['first_name'], 'Ravi');
      expect(auth.registeredWith?['last_name'], isNull);
      expect(auth.registeredWith?['email'], isNull);
    });

    testWidgets('registration sends the token and no phone number', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository auth = await reachRegistration(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Ravi');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();

      expect(
        auth.registeredWith?['registration_token'],
        'test-registration-token',
      );
      expect(auth.registeredWith?.containsKey('phone'), isFalse);
    });

    testWidgets('a malformed email is caught before the request', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository auth = await reachRegistration(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Ravi');
      await tester.enterText(find.byType(TextFormField).at(2), 'not-an-email');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();

      expect(
        find.text('That email address does not look right.'),
        findsOneWidget,
      );
      expect(auth.registeredWith, isNull);
    });

    testWidgets('completing registration reveals the app', (
      WidgetTester tester,
    ) async {
      await reachRegistration(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Ravi');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('an expired registration token restarts the flow', (
      WidgetTester tester,
    ) async {
      final FakeAuthRepository auth = await reachRegistration(tester);
      auth.nextRegisterError = const ApiException(
        code: ApiErrorCode.registrationTokenExpired,
        message: 'Expired.',
        status: 401,
      );

      await tester.enterText(find.byType(TextFormField).first, 'Ravi');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();

      // Tapping the button again would never work, so the customer is sent
      // somewhere that can.
      expect(find.text('What is your mobile number?'), findsOneWidget);
    });
  });
}
