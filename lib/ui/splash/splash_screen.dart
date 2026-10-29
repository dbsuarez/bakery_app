import 'package:flutter/material.dart';

/// Shows [child] only after a brief, fixed-duration splash with the full
/// logo. Android 12+'s native SplashScreen API only renders a small,
/// masked icon (no room for a wordmark) before Flutter's first frame -
/// this Flutter-drawn splash is what actually shows the full artwork,
/// reliably, on every platform.
class AppStartupGate extends StatefulWidget {
  final Widget child;
  const AppStartupGate({super.key, required this.child});

  @override
  State<AppStartupGate> createState() => _AppStartupGateState();
}

class _AppStartupGateState extends State<AppStartupGate> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) setState(() => _showSplash = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _showSplash ? const _SplashView() : widget.child;
  }
}

class _SplashView extends StatelessWidget {
  const _SplashView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFBF3),
      body: Center(child: Image.asset('assets/images/logo.png', width: 280)),
    );
  }
}
