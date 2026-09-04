import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Native builds (phone) hide segmented-filter labels to save the limited
/// horizontal space, keeping only icons - pair with a `tooltip:` on the
/// same `ButtonSegment` so the meaning is still one long-press away. The
/// web app always shows full labels since browser windows are typically
/// wide enough.
Widget? compactLabel(String text) => kIsWeb ? Text(text) : null;
