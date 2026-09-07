import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../products/qr_photo_service.dart';
import '../../settings/business_settings_controller.dart';

class QrCodesScreen extends StatefulWidget {
  const QrCodesScreen({super.key});

  @override
  State<QrCodesScreen> createState() => _QrCodesScreenState();
}

class _QrCodesScreenState extends State<QrCodesScreen> {
  Future<List<QrPhotoFile>>? _future;
  final Set<int> _uploading = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _future = _loadWithSeed());
  }

  /// One-time backfill: the app used to ship with a single bundled QR
  /// image used on every statement. Seed it into slot 1 (so it's the
  /// first entry here, already enabled) rather than making the user
  /// re-upload something they were already using.
  Future<List<QrPhotoFile>> _loadWithSeed() async {
    var files = await listQrPhotos();
    if (!files.any((f) => f.slot == 1)) {
      try {
        final data = await rootBundle.load('assets/images/qr_maribank.jpg');
        final xfile = XFile.fromData(
          data.buffer.asUint8List(),
          name: 'qr_maribank.jpg',
          mimeType: 'image/jpeg',
        );
        await uploadQrImage(slot: 1, file: xfile);
        if (mounted) {
          final business = context.read<BusinessSettingsController>();
          if (!business.enabledQrSlots.contains(1)) {
            await business.setEnabledQrSlots([...business.enabledQrSlots, 1]);
          }
        }
        files = await listQrPhotos();
      } catch (_) {
        // Best-effort - fall through with whatever listQrPhotos found.
      }
    }
    return files;
  }

  Future<void> _upload(int slot) async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (file == null || !mounted) return;
    setState(() => _uploading.add(slot));
    try {
      await uploadQrImage(slot: slot, file: file);
      _load();
      if (mounted) {
        final business = context.read<BusinessSettingsController>();
        if (!business.enabledQrSlots.contains(slot)) {
          await business.setEnabledQrSlots([...business.enabledQrSlots, slot]);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading.remove(slot));
    }
  }

  Future<void> _delete(int slot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this QR code?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await deleteQrImage(slot);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final business = context.watch<BusinessSettingsController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Payment QR Codes')),
      body: FutureBuilder<List<QrPhotoFile>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Could not load: ${snapshot.error}'));
          }
          final files = {for (final f in snapshot.data ?? <QrPhotoFile>[]) f.slot: f};

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Upload up to 3 payment QR codes (e.g. different banks/wallets). '
                'Toggle which ones are enabled - enabled QR codes are the ones '
                'printed on statement PDFs and shown by the quick QR button.',
              ),
              const SizedBox(height: 16),
              for (var slot = 1; slot <= maxQrSlots; slot++)
                _QrSlotTile(
                  slot: slot,
                  file: files[slot],
                  enabled: business.enabledQrSlots.contains(slot),
                  uploading: _uploading.contains(slot),
                  onUpload: () => _upload(slot),
                  onDelete: () => _delete(slot),
                  onEnabledChanged: (v) {
                    final slots = Set<int>.from(business.enabledQrSlots);
                    if (v) {
                      slots.add(slot);
                    } else {
                      slots.remove(slot);
                    }
                    business.setEnabledQrSlots(slots.toList());
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _QrSlotTile extends StatelessWidget {
  final int slot;
  final QrPhotoFile? file;
  final bool enabled;
  final bool uploading;
  final VoidCallback onUpload;
  final VoidCallback onDelete;
  final ValueChanged<bool> onEnabledChanged;

  const _QrSlotTile({
    required this.slot,
    required this.file,
    required this.enabled,
    required this.uploading,
    required this.onUpload,
    required this.onDelete,
    required this.onEnabledChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 64,
                height: 64,
                child: file == null
                    ? Container(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.qr_code_2, size: 32),
                      )
                    : CachedNetworkImage(
                        imageUrl: file!.publicUrl,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) =>
                            const Icon(Icons.broken_image_outlined),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('QR $slot', style: Theme.of(context).textTheme.titleMedium),
                  Text(file == null ? 'Not uploaded' : 'Uploaded'),
                ],
              ),
            ),
            if (file != null)
              Switch(value: enabled, onChanged: onEnabledChanged),
            if (uploading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else ...[
              IconButton(
                icon: Icon(file == null ? Icons.upload_outlined : Icons.edit_outlined),
                tooltip: file == null ? 'Upload' : 'Replace',
                onPressed: onUpload,
              ),
              if (file != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                  onPressed: onDelete,
                ),
            ],
          ],
        ),
      ),
    );
  }
}
