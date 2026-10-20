import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../analytics/batch_calculations.dart';
import '../../analytics/customer_calculations.dart';
import '../../app_state.dart';
import '../../products/qr_photo_service.dart';

class DataHealthScreen extends StatelessWidget {
  const DataHealthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final productIds = state.products.map((p) => p.id).toSet();
    final customerIds = state.customers.map((c) => c.id).toSet();
    final batchIds = state.batches.map((b) => b.id).toSet();
    final saleIds = state.sales.map((s) => s.id).toSet();
    final issues = <String>[
      for (final b in state.batches)
        if (!productIds.contains(b.productId)) 'Batch #${b.id} has no product.',
      for (final s in state.sales)
        if (!batchIds.contains(s.batchId)) 'Transaction #${s.id} has no batch.',
      for (final s in state.sales)
        if (!customerIds.contains(s.customerId))
          'Transaction #${s.id} has no customer.',
      for (final p in state.salePayments)
        if (!saleIds.contains(p.saleId)) 'Payment #${p.id} has no transaction.',
      for (final b in state.batches)
        if (!b.isDeleted && remainingQuantity(b, state.sales) < 0)
          'Batch #${b.id} is overallocated.',
      for (final s in state.sales)
        if (!s.isDeleted && saleRemainingAmount(s, state.salePayments) < 0)
          'Transaction #${s.id} is overpaid.',
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Data Health')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: issues.isEmpty
                ? Colors.green.shade50
                : Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: Icon(
                issues.isEmpty ? Icons.verified_outlined : Icons.warning_amber,
              ),
              title: Text(
                issues.isEmpty
                    ? 'Database relationships look healthy'
                    : '${issues.length} issue(s) found',
              ),
            ),
          ),
          for (final issue in issues)
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text(issue),
            ),
          const Divider(height: 32),
          FutureBuilder<List<QrPhotoFile>>(
            future: listQrPhotos(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const ListTile(
                  leading: CircularProgressIndicator(),
                  title: Text('Checking payment QR storage...'),
                );
              }
              if (snapshot.hasError) {
                return ListTile(
                  leading: const Icon(Icons.cloud_off, color: Colors.red),
                  title: const Text('Payment QR storage unavailable'),
                  subtitle: Text('${snapshot.error}'),
                );
              }
              return ListTile(
                leading: const Icon(Icons.qr_code_2),
                title: Text(
                  '${snapshot.data!.length} payment QR image(s) available',
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: Text(
              '${state.products.where((p) => !p.isArchived && p.imageUrl == null).length} active product(s) without an image',
            ),
          ),
        ],
      ),
    );
  }
}
