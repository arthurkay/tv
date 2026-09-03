import 'package:flutter/foundation.dart';

/// No-op store: there is no filesystem to persist frames to on the web, so the
/// in-memory cache is the whole cache there.
class ThumbnailStore {
  Future<(Uint8List, DateTime)?> read(String key) async => null;

  Future<void> write(String key, Uint8List bytes) async {}
}
