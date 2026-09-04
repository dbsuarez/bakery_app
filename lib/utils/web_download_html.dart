import 'dart:typed_data';
// ignore: deprecated_member_use
import 'dart:html' as html;

/// Triggers a straight browser download (no share sheet) - used because
/// share_plus on web calls the Web Share API when the browser supports it,
/// which pops a share dialog instead of just saving the file.
void downloadBytes(Uint8List bytes, String filename, String mimeType) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}
