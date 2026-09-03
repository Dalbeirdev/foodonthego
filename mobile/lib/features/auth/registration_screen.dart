import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/network/api_error_code.dart';
import '../../core/network/api_exception.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/tokens.dart';
import '../../domain/models/auth_models.dart';
import '../../shared/state/auth_controller.dart';
import '../../shared/state/providers.dart';
import '../../shared/widgets/buttons.dart';
import 'auth_error_messages.dart';

/// What the OTP screen hands to registration.
///
/// The registration token, and no phone number — the number the account is
/// created for comes out of the token on the server. There is deliberately
/// nowhere in this flow for a client-supplied number to travel.
class RegistrationArguments {
  const RegistrationArguments({
    required this.registrationToken,
    required this.maskedPhone,
    required this.expiresInSeconds,
  });

  final String registrationToken;

  /// Shown for reassurance only. Never sent back.
  final String maskedPhone;

  final int expiresInSeconds;
}

class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({required this.arguments, super.key});

  final RegistrationArguments arguments;

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final AuthSession session = await ref
          .read(authRepositoryProvider)
          .register(
            registrationToken: widget.arguments.registrationToken,
            firstName: _firstName.text.trim(),
            // Blank optional fields are sent as absent, not as an empty
            // string — "" is not a surname, and storing one makes every later
            // `lastName != null` check wrong.
            lastName: _blankToNull(_lastName.text),
            email: _blankToNull(_email.text),
          );

      if (!mounted) return;

      // Accepting the session flips the router guard, which moves us to home.
      await ref.read(authControllerProvider.notifier).accept(session);
    } on ApiException catch (error) {
      if (!mounted) return;

      final AppStrings strings = AppStrings.of(context);

      // A dead token cannot be argued with from this screen — the customer has
      // to verify their number again, so send them there rather than leaving
      // them tapping a button that will never work.
      if (authErrorNeedsRestart(error.code)) {
        _showRestart(strings, authErrorMessage(strings, error));
        return;
      }

      setState(() => _error = _fieldMessage(strings, error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Prefers the server's field-level message where it named one, because it is
  /// specific ("first name is required") in a way a generic sentence is not.
  String _fieldMessage(AppStrings strings, ApiException error) {
    if (error.code == ApiErrorCode.validationFailed) {
      final Map<String, List<String>> fields = error.fieldErrors;
      for (final String key in <String>['first_name', 'last_name', 'email']) {
        final List<String>? messages = fields[key];
        if (messages != null && messages.isNotEmpty) return messages.first;
      }
    }

    return authErrorMessage(strings, error);
  }

  void _showRestart(AppStrings strings, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    context.go(Routes.authPhone);
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
          // Back returns to the number, not to the code: the code has already
          // been consumed, so the OTP screen would be a dead end.
          onPressed: () => context.go(Routes.authPhone),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
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
                  strings.authRegisterTitle,
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: FotgSpacing.x3),
                Text(
                  strings.authRegisterBody,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: FotgSpacing.x4),
                _VerifiedNumberChip(maskedPhone: widget.arguments.maskedPhone),
                const SizedBox(height: FotgSpacing.x8),
                TextFormField(
                  controller: _firstName,
                  enabled: !_submitting,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.givenName],
                  inputFormatters: <TextInputFormatter>[
                    LengthLimitingTextInputFormatter(80),
                  ],
                  decoration: InputDecoration(
                    labelText: strings.authFirstNameLabel,
                  ),
                  validator: (String? value) => (value?.trim().isEmpty ?? true)
                      ? strings.authFirstNameRequired
                      : null,
                ),
                const SizedBox(height: FotgSpacing.x4),
                TextFormField(
                  controller: _lastName,
                  enabled: !_submitting,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const <String>[AutofillHints.familyName],
                  inputFormatters: <TextInputFormatter>[
                    LengthLimitingTextInputFormatter(80),
                  ],
                  // Optional, and labelled as such: plenty of people have one
                  // name, and a required surname is a wall they cannot pass.
                  decoration: InputDecoration(
                    labelText: strings.authLastNameLabel,
                  ),
                ),
                const SizedBox(height: FotgSpacing.x4),
                TextFormField(
                  controller: _email,
                  enabled: !_submitting,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  autofillHints: const <String>[AutofillHints.email],
                  decoration: InputDecoration(
                    labelText: strings.authEmailLabel,
                    helperText: strings.authEmailHelper,
                    helperMaxLines: 2,
                  ),
                  onFieldSubmitted: (_) => _submit(),
                  validator: (String? value) {
                    final String email = value?.trim() ?? '';
                    if (email.isEmpty) return null;
                    // Deliberately loose. Email validation by regex is famously
                    // wrong at the edges, the server checks properly, and the
                    // cost of a false rejection here is a customer who cannot
                    // use their own address.
                    return email.contains('@') && email.contains('.')
                        ? null
                        : strings.authEmailInvalid;
                  },
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: FotgSpacing.x4),
                  Text(
                    _error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: FotgSpacing.x8),
                PrimaryButton(
                  label: strings.authRegisterCta,
                  isLoading: _submitting,
                  onPressed: _submitting ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VerifiedNumberChip extends StatelessWidget {
  const _VerifiedNumberChip({required this.maskedPhone});

  final String maskedPhone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FotgSpacing.x3,
          vertical: FotgSpacing.x2,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: FotgRadius.pill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.check_circle_outline,
              size: FotgSizing.iconSm,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: FotgSpacing.x2),
            Text(
              maskedPhone,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String? _blankToNull(String value) {
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
