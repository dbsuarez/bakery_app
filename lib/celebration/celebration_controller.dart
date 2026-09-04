import 'package:confetti/confetti.dart';

/// A single shared confetti burst, triggered from wherever a meaningful
/// milestone happens (a batch selling out, a remittance closing, a new
/// personal-best revenue day/week) - see spec section 12, "Fun UX: ...
/// meaningful confetti".
class CelebrationController {
  final ConfettiController confetti =
      ConfettiController(duration: const Duration(seconds: 2));

  void celebrate() => confetti.play();

  void dispose() => confetti.dispose();
}
