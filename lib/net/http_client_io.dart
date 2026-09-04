import 'dart:io';

import 'package:cronet_http/cronet_http.dart';
import 'package:http/http.dart';

/// On Android, route all Supabase HTTP traffic through Cronet - Android's
/// native network stack (the same engine Chrome uses), instead of Dart's
/// own bundled `dart:io` HttpClient. Dart's client doesn't implement Happy
/// Eyeballs (IPv4/IPv6 racing) and does its own independent TLS
/// stack/trust-chain handling separate from the OS, either of which can
/// silently hang forever on a network/device combination the OS's own
/// stack handles fine - confirmed on this project by the exact same HTTPS
/// endpoint loading instantly in Chrome while every `dart:io`-based request
/// hung indefinitely with no error. Not needed on other platforms (Cronet
/// is Android-only), where the default client is used instead.
Client? createPlatformHttpClient() {
  if (Platform.isAndroid) {
    return CronetClient.defaultCronetEngine();
  }
  return null;
}
