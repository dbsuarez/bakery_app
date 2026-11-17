import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/product_reservation.dart';
import '../../repository/bakery_repository.dart';
import '../../utils/app_date_format.dart';
import '../../utils/guarded_action.dart';

/// Reservation leads left by visitors on the public announce/reserve page
/// (web/products.html) - not tied to any customer record in this app. The
/// owner follows up outside the app (call/message using [customerContact])
/// and marks each one contacted/fulfilled/cancelled here, or converts it
/// into a real sale manually once fulfilled.
class ReservationsScreen extends StatelessWidget {
  const ReservationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final reservations = appState.productReservations.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      appBar: AppBar(title: const Text('Reservations')),
      body: reservations.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No reservations yet. These come from the "Reserve" '
                  'button on the public products page.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: reservations.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) =>
                  _ReservationTile(reservation: reservations[index]),
            ),
    );
  }
}

class _ReservationTile extends StatelessWidget {
  final ProductReservation reservation;

  const _ReservationTile({required this.reservation});

  Color? _statusColor(BuildContext context, ReservationStatus status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case ReservationStatus.pending:
        return scheme.primary;
      case ReservationStatus.contacted:
        return scheme.tertiary;
      case ReservationStatus.fulfilled:
        return Colors.green;
      case ReservationStatus.cancelled:
        return scheme.outline;
    }
  }

  Future<void> _setStatus(BuildContext context, ReservationStatus status) {
    final repo = context.read<BakeryRepository>();
    return runGuarded(
      context,
      () => repo.updateProductReservationStatus(reservation.id, status),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete reservation?'),
        content: Text(
          'Removes ${reservation.customerName}\'s reservation for '
          '${reservation.productTitle}. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final repo = context.read<BakeryRepository>();
    await runGuarded(
      context,
      () => repo.deleteProductReservation(reservation.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = reservation.status;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _statusColor(context, status)?.withValues(
          alpha: 0.15,
        ),
        child: Icon(
          switch (status) {
            ReservationStatus.pending => Icons.hourglass_empty,
            ReservationStatus.contacted => Icons.chat_bubble_outline,
            ReservationStatus.fulfilled => Icons.check_circle_outline,
            ReservationStatus.cancelled => Icons.cancel_outlined,
          },
          color: _statusColor(context, status),
        ),
      ),
      title: Text(
        '${reservation.productTitle} · ${reservation.quantity} unit(s)',
      ),
      subtitle: Text(
        '${reservation.customerName} · ${reservation.customerContact}\n'
        '${appDateFormat.format(reservation.createdAt)}'
        '${reservation.note == null || reservation.note!.isEmpty ? '' : ' · ${reservation.note}'}',
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<Object>(
        onSelected: (value) {
          if (value == 'delete') {
            _delete(context);
          } else if (value is ReservationStatus) {
            _setStatus(context, value);
          }
        },
        itemBuilder: (context) => [
          for (final option in ReservationStatus.values)
            CheckedPopupMenuItem(
              value: option,
              checked: option == status,
              child: Text('Mark ${option.value}'),
            ),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}
