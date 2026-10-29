import 'package:flutter/material.dart';

import 'app_lock_service.dart';
import 'lock_screen.dart';

/// Wraps [child], re-locking it whenever the app returns from the background
/// (or on first launch) if the user has turned app lock on in Settings.
class AppLockGate extends StatefulWidget {
  final AppLockService lockService;
  final Widget child;

  const AppLockGate({
    super.key,
    required this.lockService,
    required this.child,
  });

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _locked = true;
  bool _lockEnabled = false;
  bool _biometricEnabled = false;
  bool _loaded = false;
  // Bumped only when the app is genuinely in the foreground and locked, so
  // LockScreen knows it's safe to pop the biometric prompt - never at the
  // moment of backgrounding (e.g. the share sheet from a CSV export), which
  // Android can't show BiometricPrompt over and silently fails.
  int _biometricTrigger = 0;
  // Sticky for as long as the app stays locked: once the user has dismissed
  // biometric (cancelled/failed the prompt, or started typing a PIN
  // instead), stop auto-popping it on every subsequent resume - otherwise a
  // brief app-switch (checking a notification) re-triggers it and interrupts
  // PIN entry every time. Reset on a successful unlock, so the next lock
  // period starts fresh.
  bool _biometricDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    final enabled = await widget.lockService.isEnabled();
    final biometric = enabled
        ? await widget.lockService.isBiometricEnabled()
        : false;
    if (!mounted) return;
    setState(() {
      _lockEnabled = enabled;
      _biometricEnabled = biometric;
      _locked = enabled;
      _loaded = true;
    });
    if (enabled && biometric) {
      // Cold start is already foregrounded, but defer a frame so LockScreen
      // picks this up via didUpdateWidget rather than racing its own mount.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _biometricTrigger++);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_lockEnabled) return;
    if (state == AppLifecycleState.paused) {
      setState(() => _locked = true);
    } else if (state == AppLifecycleState.resumed &&
        _locked &&
        _biometricEnabled &&
        !_biometricDismissed) {
      setState(() => _biometricTrigger++);
    }
  }

  void _onBiometricDismissed() {
    if (!_biometricDismissed) setState(() => _biometricDismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    if (_locked) {
      return LockScreen(
        lockService: widget.lockService,
        biometricEnabled: _biometricEnabled,
        biometricTrigger: _biometricTrigger,
        onUnlocked: () => setState(() {
          _locked = false;
          _biometricDismissed = false;
        }),
        onBiometricDismissed: _onBiometricDismissed,
      );
    }
    return widget.child;
  }
}
