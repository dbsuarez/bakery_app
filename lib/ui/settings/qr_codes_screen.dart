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
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 2000,
      maxHeight: 2000,
    );
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
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
      if (mounted) {
        final business = context.read<BusinessSettingsController>();
        await business.setEnabledQrSlots(
          business.enabledQrSlots.where((value) => value != slot).toList(),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  Future<void> _preview(QrPhotoFile file, String label) async {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 700),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: CachedNetworkImage(
                      imageUrl: file.publicUrl,
                      fit: BoxFit.contain,
                      placeholder: (_, _) => const AspectRatio(
                        aspectRatio: 1,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (_, _, _) => const AspectRatio(
                        aspectRatio: 1,
                        child: Center(
                          child: Icon(Icons.broken_image_outlined, size: 48),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Pinch to zoom. Keep the full QR visible when scanning.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _rename(int slot, String currentLabel) async {
    final controller = TextEditingController(text: currentLabel);
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename payment QR'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'e.g. GCash, Maya, HelloMoney',
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (label == null || label.trim().isEmpty || !mounted) return;
    await context.read<BusinessSettingsController>().setQrLabel(slot, label);
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
          final files = [...?snapshot.data]
            ..sort((a, b) => a.slot.compareTo(b.slot));
          final nextSlot = files.isEmpty ? 1 : files.last.slot + 1;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Add payment QR codes for different banks or wallets. '
                'Toggle which ones are enabled - enabled QR codes are the ones '
                'printed on statement PDFs, customer SOAs, and shown by the '
                'quick QR button. Add as many as you need.',
              ),
              const SizedBox(height: 16),
              for (var index = 0; index < files.length; index++)
                _QrSlotTile(
                  slot: files[index].slot,
                  file: files[index],
                  label: business.qrLabel(files[index].slot),
                  enabled: business.enabledQrSlots.contains(files[index].slot),
                  uploading: _uploading.contains(files[index].slot),
                  onPreview: () => _preview(
                    files[index],
                    business.qrLabel(files[index].slot),
                  ),
                  onRename: () => _rename(
                    files[index].slot,
                    business.qrLabel(files[index].slot),
                  ),
                  onUpload: () => _upload(files[index].slot),
                  onDelete: () => _delete(files[index].slot),
                  onEnabledChanged: (v) {
                    final slots = Set<int>.from(business.enabledQrSlots);
                    if (v) {
                      slots.add(files[index].slot);
                    } else {
                      slots.remove(files[index].slot);
                    }
                    business.setEnabledQrSlots(slots.toList());
                  },
                ),
              const SizedBox(height: 4),
              FilledButton.icon(
                onPressed: _uploading.isEmpty ? () => _upload(nextSlot) : null,
                icon: const Icon(Icons.add),
                label: const Text('Add payment QR'),
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
  final String label;
  final bool enabled;
  final bool uploading;
  final VoidCallback onPreview;
  final VoidCallback onRename;
  final VoidCallback onUpload;
  final VoidCallback onDelete;
  final ValueChanged<bool> onEnabledChanged;

  const _QrSlotTile({
    required this.slot,
    required this.file,
    required this.label,
    required this.enabled,
    required this.uploading,
    required this.onPreview,
    required this.onRename,
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
            Tooltip(
              message: 'Preview QR',
              child: InkWell(
                onTap: onPreview,
                borderRadius: BorderRadius.circular(8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: file == null
                        ? Container(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
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
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        onPressed: onRename,
                        tooltip: 'Rename',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.drive_file_rename_outline),
                      ),
                    ],
                  ),
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
                icon: Icon(
                  file == null ? Icons.upload_outlined : Icons.edit_outlined,
                ),
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
