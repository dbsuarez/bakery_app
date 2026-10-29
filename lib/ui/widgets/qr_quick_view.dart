import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../products/qr_photo_service.dart';
import '../../settings/business_settings_controller.dart';
import 'fullscreen_image_viewer.dart';

/// Shows every enabled payment QR code full-screen, swipeable - a quick way
/// to hold the QR up for a customer to scan without digging through Settings.
Future<void> showQrQuickView(BuildContext context) async {
  final business = context.read<BusinessSettingsController>();
  List<QrPhotoFile> files;
  try {
    files = await listQrPhotos();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not load QR codes: $e')));
    }
    return;
  }
  final enabled = files
      .where((f) => business.enabledQrSlots.contains(f.slot))
      .toList();
  if (!context.mounted) return;
  if (enabled.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No payment QR codes enabled - add some in Settings.'),
      ),
    );
    return;
  }
  showFullscreenImageGallery(
    context,
    imageUrls: enabled.map((f) => f.publicUrl).toList(),
    titles: enabled.map((f) => 'QR ${f.slot}').toList(),
  );
}
