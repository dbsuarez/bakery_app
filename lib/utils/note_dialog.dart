import 'package:flutter/material.dart';

/// A small icon that only renders when [note] is non-null/non-empty,
/// tapping it shows the full note - used anywhere a transaction/payment's
/// note would otherwise be entered once and never seen again.
class NoteIndicator extends StatelessWidget {
  final String? note;
  const NoteIndicator({super.key, required this.note});

  @override
  Widget build(BuildContext context) {
    if (note == null || note!.trim().isEmpty) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.sticky_note_2_outlined, size: 18),
      tooltip: 'View note',
      visualDensity: VisualDensity.compact,
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Note'),
          content: Text(note!),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}
