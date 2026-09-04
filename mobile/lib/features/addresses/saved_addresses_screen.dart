import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/network/api_error_code.dart';
import '../../core/network/api_exception.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/tokens.dart';
import '../../domain/models/saved_address.dart';
import '../../shared/state/addresses_controller.dart';
import '../../shared/widgets/app_skeleton.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/empty_state_view.dart';
import '../auth/auth_error_messages.dart';
import 'address_form_screen.dart';
import 'widgets/address_card.dart';

/// The customer's saved places.
///
/// Four states and no manual flags: the provider is an `AsyncNotifier`, so
/// loading, data and error come for free, and "empty" is data with nothing in
/// it. Row actions carry their own progress so a successful edit never blanks
/// the list back to a skeleton — a list that disappears after a save reads as a
/// failure.
class SavedAddressesScreen extends ConsumerStatefulWidget {
  const SavedAddressesScreen({super.key});

  @override
  ConsumerState<SavedAddressesScreen> createState() =>
      _SavedAddressesScreenState();
}

class _SavedAddressesScreenState extends ConsumerState<SavedAddressesScreen> {
  /// The address whose row action is in flight, if any.
  String? _busyId;

  Future<void> _run(
    String id,
    Future<void> Function() action,
    String success,
  ) async {
    if (_busyId != null) return;

    setState(() => _busyId = id);

    try {
      await action();
      if (!mounted) return;
      _toast(success);
    } on ApiException catch (error) {
      if (!mounted) return;
      _toast(_messageFor(error), isError: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _toast(String message, {bool isError = false}) {
    final ThemeData theme = Theme.of(context);

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? theme.colorScheme.error : null,
        ),
      );
  }

  String _messageFor(ApiException error) {
    final AppStrings strings = AppStrings.of(context);

    return switch (error.code) {
      ApiErrorCode.network => strings.customerErrorOffline,
      ApiErrorCode.addressNotFound => strings.customerErrorAddressGone,
      _ => authErrorMessage(strings, error),
    };
  }

  Future<void> _openForm({SavedAddress? existing}) async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) =>
            AddressFormScreen(existing: existing),
      ),
    );

    if (saved == true && mounted) {
      _toast(
        existing == null
            ? AppStrings.of(context).addressSaved
            : AppStrings.of(context).addressUpdated,
      );
    }
  }

  Future<void> _confirmDelete(SavedAddress address) async {
    final AppStrings strings = AppStrings.of(context);

    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(strings.addressDeleteTitle(address.label)),
            content: Text(strings.addressDeleteBody),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(strings.authCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(dialogContext).colorScheme.error,
                ),
                child: Text(strings.addressDelete),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;

    await _run(
      address.id,
      () => ref.read(addressesControllerProvider.notifier).remove(address.id),
      strings.addressDeleted,
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final AsyncValue<List<SavedAddress>> addresses = ref.watch(
      addressesControllerProvider,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.addressesTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(Routes.profile),
        ),
      ),
      floatingActionButton: addresses.hasValue && addresses.value!.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add_rounded),
              label: Text(strings.addressesAdd),
            )
          : null,
      body: SafeArea(
        child: addresses.when(
          loading: () => const _AddressListSkeleton(),
          error: (Object error, StackTrace _) => _AddressesError(
            message: error is ApiException
                ? _messageFor(error)
                : strings.customerErrorGeneric,
            onRetry: () =>
                ref.read(addressesControllerProvider.notifier).reload(),
          ),
          data: (List<SavedAddress> list) => list.isEmpty
              ? _EmptyAddresses(onAdd: () => _openForm())
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(addressesControllerProvider.notifier).reload(),
                  child: ListView.separated(
                    padding: const EdgeInsets.only(
                      top: FotgSpacing.x2,
                      // Clear of the extended FAB, so the last row is reachable.
                      bottom: FotgSpacing.x16 + FotgSpacing.x6,
                    ),
                    itemCount: list.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: FotgSpacing.x16),
                    itemBuilder: (BuildContext context, int index) {
                      final SavedAddress address = list[index];

                      return AddressListItem(
                        address: address,
                        busy: _busyId == address.id,
                        onEdit: () => _openForm(existing: address),
                        onDelete: () => _confirmDelete(address),
                        onMakeDefault: () => _run(
                          address.id,
                          () => ref
                              .read(addressesControllerProvider.notifier)
                              .makeDefault(address.id),
                          strings.addressDefaultChanged,
                        ),
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }
}

/// The empty state.
///
/// It says what saving an address *buys* rather than reporting that there are
/// none. A customer looking at "No saved addresses" learns nothing they did not
/// already know.
class _EmptyAddresses extends StatelessWidget {
  const _EmptyAddresses({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);

    return EmptyStateView(
      icon: Icons.bookmark_border_rounded,
      title: strings.addressesEmptyTitle,
      body: strings.addressesEmptyBody,
      action: PrimaryButton(
        label: strings.addressesAddFirst,
        icon: Icons.add_rounded,
        expand: false,
        onPressed: onAdd,
      ),
    );
  }
}

/// Content-shaped, not a spinner: the list is about to appear here, and a
/// skeleton in its shape means nothing jumps when it does.
class _AddressListSkeleton extends StatelessWidget {
  const _AddressListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: FotgSpacing.x2),
      itemCount: 3,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: FotgSpacing.x16),
      itemBuilder: (_, _) => const Padding(
        padding: EdgeInsets.symmetric(
          horizontal: FotgSpacing.x5,
          vertical: FotgSpacing.x3,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppSkeleton(width: 44, height: 44, radius: FotgRadius.md),
            SizedBox(width: FotgSpacing.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AppSkeleton(width: 90, height: 16),
                  SizedBox(height: FotgSpacing.x2),
                  AppSkeleton(height: 14),
                  SizedBox(height: FotgSpacing.x1),
                  AppSkeleton(width: 160, height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressesError extends StatelessWidget {
  const _AddressesError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppStrings strings = AppStrings.of(context);
    final ThemeData theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FotgSpacing.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.cloud_off_rounded,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: FotgSpacing.x4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: FotgSpacing.x6),
            SecondaryButton(label: strings.customerRetry, onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
