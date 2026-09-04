import 'dart:math' show pi;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'celebration_controller.dart';

/// Wraps the whole app so a confetti burst (triggered from anywhere via
/// `context.read<CelebrationController>().celebrate()`) renders above
/// every screen, not just whichever one happened to trigger it.
class CelebrationOverlay extends StatelessWidget {
  final Widget child;
  const CelebrationOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CelebrationController>().confetti;
    return Stack(
      children: [
        child,
        IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: controller,
              blastDirection: pi / 2,
              maxBlastForce: 20,
              minBlastForce: 8,
              numberOfParticles: 30,
              gravity: 0.3,
              shouldLoop: false,
            ),
          ),
        ),
      ],
    );
  }
}
