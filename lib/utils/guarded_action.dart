import 'package:flutter/material.dart';

/// Runs [action] and shows a SnackBar with the error if it throws, instead
/// of letting the failure disappear silently (an unawaited/uncaught
/// exception in an async void handler shows nothing to the user). Use for
/// every button/dialog action that calls the repository.
Future<void> runGuarded(
  BuildContext context,
  Future<void> Function() action, {
  String Function(Object error)? errorMessage,
}) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(errorMessage?.call(e) ?? 'Something went wrong: $e'),
      ));
    }
  }
}
