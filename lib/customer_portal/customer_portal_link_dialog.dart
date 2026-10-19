import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/customer.dart';
import '../utils/app_date_format.dart';
import 'customer_portal_service.dart';

Future<void> showCustomerPortalLinkDialog(
  BuildContext context,
  Customer customer,
) async {
  if (customer.remoteId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Customer is not synced yet. Try again shortly.'),
      ),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => _CustomerPortalLinkDialog(customer: customer),
  );
}

class _CustomerPortalLinkDialog extends StatefulWidget {
  final Customer customer;

  const _CustomerPortalLinkDialog({required this.customer});

  @override
  State<_CustomerPortalLinkDialog> createState() =>
      _CustomerPortalLinkDialogState();
}

class _CustomerPortalLinkDialogState extends State<_CustomerPortalLinkDialog> {
  late final CustomerPortalService _service;
  late Future<CustomerPortalLinkStatus> _status;
  String? _newLink;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service = CustomerPortalService(Supabase.instance.client);
    _reload();
  }

  void _reload() {
    _status = _service.status(widget.customer.remoteId!);
  }

  Future<void> _createOrRotate(bool alreadyExists) async {
    if (alreadyExists) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace the existing link?'),
          content: const Text(
            'The previous link will stop working immediately. You will need '
            'to send the new link to the customer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace link'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      final link = await _service.rotateLink(widget.customer.remoteId!);
      if (!mounted) return;
      setState(() {
        _newLink = link;
        _reload();
      });
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New portal link copied.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not create link: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke() async {
    setState(() => _busy = true);
    try {
      await _service.revokeLink(widget.customer.remoteId!);
      if (mounted) {
        setState(() {
          _newLink = null;
          _reload();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not disable link: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.customer.name}\'s SOA link'),
      content: SizedBox(
        width: 520,
        child: FutureBuilder<CustomerPortalLinkStatus>(
          future: _status,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              if (snapshot.hasError) {
                return Text('Could not load link status: ${snapshot.error}');
              }
              return const Center(child: CircularProgressIndicator());
            }
            final status = snapshot.data!;
            final visibleLink =
                _newLink ??
                (status.token == null
                    ? null
                    : _service.linkForToken(status.token!));
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  status.enabled
                      ? 'The customer portal is enabled.'
                      : 'The customer portal is disabled.',
                ),
                if (status.lastAccessedAt != null)
                  Text(
                    'Last opened: '
                    '${appDateTimeFormat.format(status.lastAccessedAt!.toLocal())}',
                  ),
                if (visibleLink != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Copy or share this permanent link. It remains available '
                    'here until you replace or disable it.',
                  ),
                  const SizedBox(height: 8),
                  SelectableText(visibleLink),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: visibleLink),
                          );
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy'),
                      ),
                      FilledButton.icon(
                        onPressed: () => SharePlus.instance.share(
                          ShareParams(
                            text:
                                'Hi ${widget.customer.name}, here is your '
                                'statement of account: $visibleLink',
                            subject: 'Your statement of account',
                          ),
                        ),
                        icon: const Icon(Icons.share),
                        label: const Text('Share'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'Anyone with this private link can view this customer\'s '
                  'statement. Replacing or disabling it immediately invalidates '
                  'the old link.',
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FutureBuilder<CustomerPortalLinkStatus>(
          future: _status,
          builder: (context, snapshot) {
            final status = snapshot.data;
            if (status?.enabled == true) {
              return TextButton(
                onPressed: _busy ? null : _revoke,
                child: const Text('Disable link'),
              );
            }
            return const SizedBox.shrink();
          },
        ),
        FutureBuilder<CustomerPortalLinkStatus>(
          future: _status,
          builder: (context, snapshot) {
            final status = snapshot.data;
            return FilledButton(
              onPressed: _busy || status == null
                  ? null
                  : () => _createOrRotate(status.exists),
              child: Text(
                status?.exists == true ? 'Replace link' : 'Create link',
              ),
            );
          },
        ),
      ],
    );
  }
}
