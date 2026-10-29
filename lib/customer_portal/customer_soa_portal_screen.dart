import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'customer_portal_service.dart';

final _money = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
final _date = DateFormat('yyyy-MM-dd');

class CustomerSoaPortalScreen extends StatefulWidget {
  final String token;

  const CustomerSoaPortalScreen({super.key, required this.token});

  @override
  State<CustomerSoaPortalScreen> createState() =>
      _CustomerSoaPortalScreenState();
}

class _CustomerSoaPortalScreenState extends State<CustomerSoaPortalScreen> {
  late final Future<Map<String, dynamic>> _statement;

  @override
  void initState() {
    super.initState();
    _statement = CustomerPortalService(
      Supabase.instance.client,
    ).loadStatement(widget.token);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Map<String, dynamic>>(
        future: _statement,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const _PortalMessage(
              icon: Icons.link_off,
              title: 'This statement link is unavailable',
              message:
                  'It may have been replaced or disabled. Please ask the '
                  'bakery for a new link.',
            );
          }
          return _StatementView(data: snapshot.data!);
        },
      ),
    );
  }
}

class _StatementView extends StatelessWidget {
  final Map<String, dynamic> data;

  const _StatementView({required this.data});

  @override
  Widget build(BuildContext context) {
    final customer = Map<String, dynamic>.from(data['customer'] as Map);
    final sales = (data['sales'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final qrPaths = (data['qr_paths'] as List? ?? const []).cast<String>();
    final balance = (data['balance'] as num?)?.toDouble() ?? 0;
    final businessName = data['business_name'] as String? ?? 'My Bakery';

    return SelectionArea(
      child: CustomScrollView(
        slivers: [
          SliverAppBar(pinned: true, title: Text(businessName)),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Statement of Account',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        customer['name'] as String? ?? 'Customer',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 20),
                      Card(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              const Text('Outstanding balance'),
                              const SizedBox(height: 4),
                              Text(
                                _money.format(balance),
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Updated ${_formatDate(data['generated_at'])}',
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Transactions',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      if (sales.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('No transactions to show.'),
                          ),
                        )
                      else
                        ...sales.map((sale) => _SaleCard(sale: sale)),
                      if (balance > 0) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Payment QR codes',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Please include your name or payment reference when '
                          'sending payment. Payment is reflected after the '
                          'bakery records it.',
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            if (qrPaths.isEmpty)
                              const _BundledQrCard()
                            else
                              for (var i = 0; i < qrPaths.length; i++)
                                _QrCard(path: qrPaths[i], number: i + 1),
                          ],
                        ),
                      ],
                      const SizedBox(height: 32),
                      Text(
                        'This is a read-only statement. Contact $businessName '
                        'if anything needs to be corrected.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null ? '' : _date.format(parsed.toLocal());
  }
}

class _SaleCard extends StatelessWidget {
  final Map<String, dynamic> sale;

  const _SaleCard({required this.sale});

  @override
  Widget build(BuildContext context) {
    final amount = (sale['amount'] as num?)?.toDouble() ?? 0;
    final remaining = (sale['remaining'] as num?)?.toDouble() ?? 0;
    final paid = sale['paid'] as bool? ?? false;
    final isSettled = paid || remaining <= 0;
    final date = DateTime.tryParse(sale['sale_date']?.toString() ?? '');
    final datePaid = DateTime.tryParse(sale['date_paid']?.toString() ?? '');
    final isCashAdvance = sale['kind'] == 'cash_advance';
    return Card(
      child: ListTile(
        title: Text(sale['product'] as String? ?? 'Order'),
        subtitle: Text(
          '${date == null ? '' : _date.format(date)}'
          '${isCashAdvance ? '' : ' · ${sale['quantity'] ?? 1} unit(s)'}\n'
          '${isSettled ? 'Paid${datePaid == null ? '' : ' on ${_date.format(datePaid)}'}' : '${_money.format(remaining)} remaining'}',
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _money.format(amount),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: isSettled
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : null,
              ),
            ),
            if (isSettled) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade700,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'PAID',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  final String path;
  final int number;

  const _QrCard({required this.path, required this.number});

  @override
  Widget build(BuildContext context) {
    final url = Supabase.instance.client.storage
        .from('qr-codes')
        .getPublicUrl(path);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CachedNetworkImage(
              imageUrl: url,
              width: 260,
              height: 260,
              fit: BoxFit.contain,
              placeholder: (_, _) => const SizedBox(
                height: 260,
                child: Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (_, _, _) => const SizedBox(
                height: 260,
                child: Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text('Payment option $number'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BundledQrCard extends StatelessWidget {
  const _BundledQrCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 260,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/qr_maribank.jpg',
              width: 260,
              height: 260,
              fit: BoxFit.contain,
            ),
            const Padding(
              padding: EdgeInsets.all(10),
              child: Text('Payment QR'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PortalMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _PortalMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
