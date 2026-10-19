import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'app_lock_service.dart';

class LockScreen extends StatefulWidget {
  final AppLockService lockService;
  final VoidCallback onUnlocked;
  final bool biometricEnabled;

  /// Bumped by the parent only when it's safe to show the biometric prompt
  /// (app genuinely in the foreground) - never attempted from [initState],
  /// which can fire while still backgrounded (e.g. behind a share sheet).
  final int biometricTrigger;

  /// Called when biometric is cancelled/fails, or the user starts typing a
  /// PIN instead - lets the parent stop auto-popping biometric again for
  /// the rest of this locked stretch.
  final VoidCallback onBiometricDismissed;

  const LockScreen({
    super.key,
    required this.lockService,
    required this.onUnlocked,
    required this.biometricEnabled,
    required this.biometricTrigger,
    required this.onBiometricDismissed,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pinController = TextEditingController();
  final _pinFocusNode = FocusNode();
  String? _error;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _pinFocusNode.addListener(() {
      if (_pinFocusNode.hasFocus) widget.onBiometricDismissed();
    });
  }

  @override
  void didUpdateWidget(covariant LockScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.biometricEnabled &&
        widget.biometricTrigger != oldWidget.biometricTrigger) {
      _tryBiometric();
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _pinFocusNode.dispose();
    super.dispose();
  }

  Future<void> _tryBiometric() async {
    try {
      final auth = LocalAuthentication();
      final ok = await auth.authenticate(localizedReason: 'Unlock My Bakery');
      if (ok) {
        widget.onUnlocked();
      } else {
        widget.onBiometricDismissed();
      }
    } catch (_) {
      widget.onBiometricDismissed();
    }
  }

  Future<void> _submitPin() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    bool ok;
    try {
      ok = await widget.lockService.verifyPin(_pinController.text);
    } on PinLockedException catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error =
            'Too many attempts. Try again in '
            '${error.retryAfter.inSeconds + 1} seconds.';
      });
      return;
    }
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
    } else {
      final retryAfter = await widget.lockService.currentLockout();
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = retryAfter > Duration.zero
            ? 'Too many attempts. Try again in '
                  '${retryAfter.inSeconds + 1} seconds.'
            : 'Incorrect PIN';
        _pinController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/images/logo.png', height: 120),
                  const SizedBox(height: 16),
                  Text(
                    'Enter PIN',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _pinController,
                    focusNode: _pinFocusNode,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    decoration: InputDecoration(
                      counterText: '',
                      border: const OutlineInputBorder(),
                      errorText: _error,
                    ),
                    onSubmitted: (_) => _submitPin(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _checking ? null : _submitPin,
                    child: const Text('Unlock'),
                  ),
                  if (widget.biometricEnabled) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _tryBiometric,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Use biometrics'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
