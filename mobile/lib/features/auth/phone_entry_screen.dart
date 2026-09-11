import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/network/api_exception.dart';
import '../../core/phone/supported_country.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/tokens.dart';
import '../../domain/models/auth_models.dart';
import '../../shared/state/providers.dart';
import '../../shared/widgets/buttons.dart';
import 'auth_error_messages.dart';
import 'otp_verification_screen.dart';
import 'widgets/country_picker.dart';

/// Where the customer types their number.
///
/// One field and one action. It asks for nothing else — no device id, no
/// referral code, no marketing opt-in — because none of that is needed to send
/// an SMS, and a sign-in screen that collects extras is a sign-in screen people
/// abandon.
class PhoneEntryScreen extends ConsumerStatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  ConsumerState<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends ConsumerState<PhoneEntryScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  SupportedCountry _country = SupportedCountry.fallback;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _digits => normalizeNationalDigits(_controller.text);

  bool get _canSubmit => !_submitting && _country.looksPlausible(_digits);

  Future<void> _submit() async {
    if (!_canSubmit) return;

    // Dismissed so the customer can see the error, which would otherwise appear
    // behind the keyboard on a short device.
    _focus.unfocus();

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final OtpRequestResult result = await ref
          .read(authRepositoryProvider)
          .requestOtp(phone: _digits, countryCode: _country.callingCode);

      if (!mounted) return;

      context.go(
        Routes.authOtp,
        extra: OtpScreenArguments(
          phoneDigits: _digits,
          countryCode: _country.callingCode,
          maskedPhone: result.maskedPhone,
          otpLength: result.otpLength,
          expiresInSeconds: result.expiresInSeconds,
          resendAvailableInSeconds: result.resendAvailableInSeconds,
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = authErrorMessage(AppStrings.of(context), error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(leading: const _BackToWelcome()),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            FotgSpacing.x6,
            FotgSpacing.x2,
            FotgSpacing.x6,
            FotgSpacing.x6,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                strings.authPhoneTitle,
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: FotgSpacing.x3),
              Text(
                strings.authPhoneBody,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: FotgSpacing.x8),
              _PhoneField(
                controller: _controller,
                focusNode: _focus,
                country: _country,
                errorText: _error,
                enabled: !_submitting,
                onCountryChanged: (SupportedCountry country) =>
                    setState(() => _country = country),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: FotgSpacing.x8),
              PrimaryButton(
                label: strings.authPhoneCta,
                isLoading: _submitting,
                onPressed: _canSubmit ? _submit : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Back goes to the welcome screen explicitly.
///
/// `context.pop()` would be wrong: the auth routes are reached with `go`, so
/// there may be nothing to pop — on a cold start into the phone screen, popping
/// leaves a black page.
class _BackToWelcome extends StatelessWidget {
  const _BackToWelcome();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: () => context.go(Routes.welcome),
    );
  }
}

class _PhoneField extends StatelessWidget {
  const _PhoneField({
    required this.controller,
    required this.focusNode,
    required this.country,
    required this.enabled,
    required this.onCountryChanged,
    required this.onChanged,
    required this.onSubmitted,
    this.errorText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final SupportedCountry country;
  final bool enabled;
  final String? errorText;
  final ValueChanged<SupportedCountry> onCountryChanged;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: true,
      // The numeric keypad, and the OS's own "this is a phone number" hint so
      // the platform can offer the handset's own number to fill in.
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      autofillHints: const <String>[AutofillHints.telephoneNumberNational],
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
        // A little over the longest supported national number, so a pasted
        // "+91 98765 43210" is not silently truncated before normalization.
        LengthLimitingTextInputFormatter(15),
      ],
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: strings.authPhoneLabel,
        errorText: errorText,
        // Wraps rather than clipping, because several of these messages are a
        // full sentence and a clipped error is not an error message.
        errorMaxLines: 3,
        // `prefix`, not `prefixIcon`. A prefixIcon is centred over the whole
        // decoration box, which leaves the dial code floating above the number's
        // baseline once the label has floated up. `prefix` sits inside the input
        // row itself, so "+91" and the digits share a baseline and read as one
        // number.
        //
        // Flutter only renders a prefix when the field is focused or filled,
        // hence the always-floating label: the country code has to be visible
        // before anybody has typed, or the field looks like it takes a full
        // international number.
        prefix: CountryPickerButton(
          selected: country,
          onChanged: onCountryChanged,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
    );
  }
}
