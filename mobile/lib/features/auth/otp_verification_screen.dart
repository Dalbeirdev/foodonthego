import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/network/api_exception.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/tokens.dart';
import '../../domain/models/auth_models.dart';
import '../../shared/state/auth_controller.dart';
import '../../shared/state/providers.dart';
import '../../shared/widgets/buttons.dart';
import 'auth_error_messages.dart';
import 'registration_screen.dart';

/// What the phone screen hands to the OTP screen.
///
/// Passed as route `extra` rather than as query parameters: a phone number in a
/// URL ends up in a deep-link log and in the browser history of the web build.
class OtpScreenArguments {
  const OtpScreenArguments({
    required this.phoneDigits,
    required this.countryCode,
    required this.maskedPhone,
    required this.otpLength,
    required this.expiresInSeconds,
    required this.resendAvailableInSeconds,
  });

  final String phoneDigits;
  final String countryCode;

  /// What the *server* said the number looks like. Displayed rather than the
  /// locally typed number, so the screen confirms what the server understood.
  final String maskedPhone;

  final int otpLength;
  final int expiresInSeconds;
  final int resendAvailableInSeconds;
}

class OtpVerificationScreen extends ConsumerStatefulWidget {
  const OtpVerificationScreen({required this.arguments, super.key});

  final OtpScreenArguments arguments;

  @override
  ConsumerState<OtpVerificationScreen> createState() =>
      _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends ConsumerState<OtpVerificationScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  Timer? _ticker;
  late int _resendIn;
  late int _expiresIn;

  bool _submitting = false;
  bool _resending = false;
  String? _error;
  late String _maskedPhone;

  @override
  void initState() {
    super.initState();
    _maskedPhone = widget.arguments.maskedPhone;
    _resendIn = widget.arguments.resendAvailableInSeconds;
    _expiresIn = widget.arguments.expiresInSeconds;
    _startTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// One timer drives both countdowns.
  ///
  /// Both are a courtesy: the server enforces the resend cooldown and the code's
  /// expiry itself, so a device with a wrong clock cannot talk its way past
  /// either — it just sees a countdown that does not match.
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_resendIn > 0) _resendIn--;
        if (_expiresIn > 0) _expiresIn--;
      });

      if (_resendIn == 0 && _expiresIn == 0) timer.cancel();
    });
  }

  String get _code => _controller.text;

  bool get _isComplete => _code.length == widget.arguments.otpLength;

  bool get _canSubmit => _isComplete && !_submitting && !_resending;

  Future<void> _verify() async {
    if (!_canSubmit) return;

    _focus.unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final OtpVerifyResult result = await ref
          .read(authRepositoryProvider)
          .verifyOtp(
            phone: widget.arguments.phoneDigits,
            countryCode: widget.arguments.countryCode,
            code: _code,
          );

      if (!mounted) return;

      switch (result) {
        case OtpSignedIn(session: final AuthSession session):
          // The controller persists the session; the router guard then moves us
          // to the home screen, so there is no navigation call here.
          await ref.read(authControllerProvider.notifier).accept(session);

        case OtpRegistrationRequired(
          registrationToken: final String token,
          expiresInSeconds: final int expires,
        ):
          if (!mounted) return;
          context.go(
            Routes.authRegister,
            extra: RegistrationArguments(
              registrationToken: token,
              maskedPhone: _maskedPhone,
              expiresInSeconds: expires,
            ),
          );
      }
    } on ApiException catch (error) {
      if (!mounted) return;

      setState(() {
        _error = authErrorMessage(AppStrings.of(context), error);

        // An expired or exhausted code cannot be retyped into success, so the
        // field is cleared and the countdown ends — which turns "Resend code"
        // on, giving the customer the action that actually helps.
        if (authErrorNeedsRestart(error.code)) {
          _controller.clear();
          _expiresIn = 0;
          _resendIn = 0;
        }
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _resend() async {
    if (_resendIn > 0 || _resending || _submitting) return;

    setState(() {
      _resending = true;
      _error = null;
    });

    try {
      final OtpRequestResult result = await ref
          .read(authRepositoryProvider)
          .requestOtp(
            phone: widget.arguments.phoneDigits,
            countryCode: widget.arguments.countryCode,
          );

      if (!mounted) return;

      setState(() {
        _controller.clear();
        _maskedPhone = result.maskedPhone;
        _resendIn = result.resendAvailableInSeconds;
        _expiresIn = result.expiresInSeconds;
      });
      _startTicker();
      _focus.requestFocus();
    } on ApiException catch (error) {
      if (!mounted) return;

      setState(() {
        _error = authErrorMessage(AppStrings.of(context), error);

        // The server is authoritative about when a resend is allowed. If it
        // says "not yet", the countdown is corrected to what it said rather
        // than to what this device thought.
        final int? retryAfter = error.retryAfterSeconds;
        if (retryAfter != null && retryAfter > 0) {
          _resendIn = retryAfter;
          _startTicker();
        }
      });
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => context.go(Routes.authPhone),
        ),
      ),
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
              Text(strings.authOtpTitle, style: theme.textTheme.headlineMedium),
              const SizedBox(height: FotgSpacing.x3),
              Text(
                strings.authOtpSentTo(_maskedPhone),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: FotgSpacing.x2),
              LinkAction(
                label: strings.authOtpChangeNumber,
                onPressed: () => context.go(Routes.authPhone),
              ),
              const SizedBox(height: FotgSpacing.x8),
              OtpInputField(
                controller: _controller,
                focusNode: _focus,
                length: widget.arguments.otpLength,
                enabled: !_submitting,
                hasError: _error != null,
                onChanged: (_) {
                  setState(() => _error = null);
                  if (_isComplete) _verify();
                },
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: FotgSpacing.x4),
                _ErrorText(message: _error!),
              ],
              const SizedBox(height: FotgSpacing.x4),
              _ExpiryLine(secondsRemaining: _expiresIn),
              const SizedBox(height: FotgSpacing.x8),
              PrimaryButton(
                label: strings.authOtpCta,
                isLoading: _submitting,
                onPressed: _canSubmit ? _verify : null,
              ),
              const SizedBox(height: FotgSpacing.x4),
              Center(
                child: _resendIn > 0
                    ? Text(
                        strings.authOtpResendIn(_resendIn),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : SecondaryButton(
                        label: strings.authOtpResend,
                        isLoading: _resending,
                        expand: false,
                        onPressed: _resending ? null : _resend,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The code field.
///
/// One real `TextField` behind a row of boxes, rather than one field per digit.
/// Separate fields look the same and behave badly: they break paste, they fight
/// SMS autofill, and backspacing across them is a known accessibility problem.
/// This keeps a single editable value and draws the boxes over it.
class OtpInputField extends StatelessWidget {
  const OtpInputField({
    required this.controller,
    required this.focusNode,
    required this.length,
    required this.enabled,
    required this.onChanged,
    this.hasError = false,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;
  final bool enabled;
  final bool hasError;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: AppStrings.of(context).authOtpTitle,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        autofocus: true,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: length,
        // The platform's one-time-code hint. On Android this is what lets the
        // code be filled from the SMS without the app ever reading messages —
        // no SMS permission, which we deliberately do not request.
        autofillHints: const <String>[AutofillHints.oneTimeCode],
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(length),
        ],
        onChanged: onChanged,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
          // Wide tracking so six digits read as six digits rather than a number.
          letterSpacing: 12,
        ),
        decoration: InputDecoration(
          counterText: '',
          hintText: '·' * length,
          errorText: hasError ? '' : null,
          errorStyle: const TextStyle(height: 0, fontSize: 0),
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          Icons.error_outline,
          size: FotgSizing.iconSm,
          color: theme.colorScheme.error,
        ),
        const SizedBox(width: FotgSpacing.x2),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }
}

class _ExpiryLine extends StatelessWidget {
  const _ExpiryLine({required this.secondsRemaining});

  final int secondsRemaining;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    if (secondsRemaining <= 0) {
      return Text(
        strings.authOtpExpiredNotice,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final String minutes = (secondsRemaining ~/ 60).toString();
    final String seconds = (secondsRemaining % 60).toString().padLeft(2, '0');

    return Text(
      strings.authOtpExpiresIn('$minutes:$seconds'),
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
