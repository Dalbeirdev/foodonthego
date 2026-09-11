import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/network/api_error_code.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/tokens.dart';
import '../../domain/models/customer.dart';
import '../../shared/state/auth_controller.dart';
import '../../shared/state/providers.dart';
import '../../shared/widgets/buttons.dart';
import '../auth/auth_error_messages.dart';
import 'widgets/locked_phone_field.dart';

/// The only screen where a customer changes their own details.
///
/// Three editable fields and one that is deliberately not: the verified mobile
/// number is identity, established by an OTP in Module 03, and there is no
/// control here that could change it. That is enforced on the server as well —
/// the profile endpoint declares no rule for it — but a screen that offered the
/// control and then failed would be worse than one that explains why.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    final Customer? customer = ref.read(authControllerProvider).customer;
    _firstName = TextEditingController(text: customer?.firstName ?? '');
    _lastName = TextEditingController(text: customer?.lastName ?? '');
    _email = TextEditingController(text: customer?.email ?? '');
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // A submission lock, not decoration: without it a double tap on a slow
    // connection sends two updates, and the second can undo a correction made
    // between them.
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final Customer updated = await ref
          .read(customerRepositoryProvider)
          .updateProfile(
            firstName: _firstName.text,
            lastName: _lastName.text,
            email: _email.text,
            // Explicit, because Dart cannot tell an omitted named argument from
            // one passed null — and here the difference is "leave it" versus
            // "clear it".
            clearLastName: true,
            clearEmail: true,
          );

      if (!mounted) return;

      // The session is the app's single source of truth for who is signed in,
      // so the new name has to land there or the home greeting keeps the old one
      // until the next cold start.
      await ref.read(authControllerProvider.notifier).updateProfile(updated);

      if (!mounted) return;

      final AppStrings strings = AppStrings.of(context);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(strings.profileSaved)));

      context.pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageFor(AppStrings.of(context), error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Prefers the server's field-level message where it named one — "that email
  /// is already on another account" is specific in a way a generic sentence is
  /// not.
  String _messageFor(AppStrings strings, ApiException error) {
    if (error.code == ApiErrorCode.validationFailed) {
      final Map<String, List<String>> fields = error.fieldErrors;
      for (final String key in <String>['first_name', 'last_name', 'email']) {
        final List<String>? messages = fields[key];
        if (messages != null && messages.isNotEmpty) return messages.first;
      }
    }

    if (error.code == ApiErrorCode.network) {
      return strings.customerErrorSaveOffline;
    }

    return authErrorMessage(strings, error);
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);
    final Customer? customer = ref.watch(authControllerProvider).customer;

    return Scaffold(
      appBar: AppBar(title: Text(strings.profileEditTitle)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: <Widget>[
              Expanded(
                // A scrolling Column, not a ListView. ListView builds lazily, so
                // a field scrolled out of view is not in the tree — and a
                // FormField that is not in the tree is never registered with the
                // Form, so validate() silently skips it. At a large text scale
                // that means saving a name nothing ever checked.
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    FotgSpacing.x5,
                    FotgSpacing.x4,
                    FotgSpacing.x5,
                    FotgSpacing.x6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        strings.profileEditSubtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: FotgSpacing.x6),

                      TextFormField(
                        controller: _firstName,
                        enabled: !_submitting,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        autofillHints: const <String>[AutofillHints.givenName],
                        inputFormatters: <TextInputFormatter>[
                          LengthLimitingTextInputFormatter(80),
                        ],
                        decoration: InputDecoration(
                          labelText: strings.authFirstNameLabel,
                        ),
                        validator: (String? value) =>
                            (value?.trim().isEmpty ?? true)
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
                        // Still optional, exactly as Module 03 established.
                        // Plenty of people have one name, and a surname that was
                        // optional at registration cannot become required later.
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
                          // No "Verified" badge anywhere near this field: there
                          // is no email verification flow, so claiming one would
                          // be a lie.
                          helperText: strings.profileEmailUnverified,
                          helperMaxLines: 2,
                        ),
                        onFieldSubmitted: (_) => _save(),
                        validator: (String? value) {
                          final String email = value?.trim() ?? '';
                          if (email.isEmpty) return null;
                          return email.contains('@') && email.contains('.')
                              ? null
                              : strings.authEmailInvalid;
                        },
                      ),
                      const SizedBox(height: FotgSpacing.x6),

                      LockedPhoneField(
                        maskedPhone: customer?.maskedPhone ?? '',
                      ),

                      if (_error != null) ...<Widget>[
                        const SizedBox(height: FotgSpacing.x5),
                        Text(
                          _error!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Pinned, so it stays reachable at a large text scale and is never
              // the thing the keyboard covers.
              _PinnedAction(
                label: strings.profileSave,
                isLoading: _submitting,
                onPressed: _submitting ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The primary action, held at the bottom of the screen above the keyboard.
class _PinnedAction extends StatelessWidget {
  const _PinnedAction({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      // No keyboard inset arithmetic: Scaffold already shrinks its body when the
      // keyboard opens, so this bar rides up with it.
      padding: const EdgeInsets.fromLTRB(
        FotgSpacing.x5,
        FotgSpacing.x3,
        FotgSpacing.x5,
        FotgSpacing.x4,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: PrimaryButton(
        label: label,
        isLoading: isLoading,
        onPressed: onPressed,
      ),
    );
  }
}
