import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Frames kept as JPEG files in the app cache directory, so a channel that has
/// been seen before shows its picture immediately on the next launch instead of
/// waiting on a fresh capture.
///
/// Everything here is best-effort: if the directory cannot be resolved (no
/// plugin in a widget test, sandboxing, a full disk) the store quietly reports
/// nothing and the service falls back to memory-only behaviour.
class ThumbnailStore {
  /// Frames are small (~40 KB); this is a ceiling for a very long playlist.
  static const _maxBytesOnDisk = 32 * 1024 * 1024;

  /// Prune every N writes rather than on each one.
  static const _pruneInterval = 20;

  Directory? _directory;
  Future<Directory?>? _resolving;
  int _writesSincePrune = 0;

  Future<Directory?> _resolve() {
    return _resolving ??= () async {
      try {
        final base = await getApplicationCacheDirectory();
        final directory = Directory('${base.path}/channel_thumbnails');
        await directory.create(recursive: true);
        _directory = directory;
        unawaited(_prune());
      } catch (error) {
        debugPrint('[thumbnail] on-disk cache unavailable: $error');
      }
      return _directory;
    }();
  }

  Future<(Uint8List, DateTime)?> read(String key) async {
    final directory = await _resolve();
    if (directory == null) return null;
    try {
      final file = File('${directory.path}/$key.jpg');
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return (bytes, await file.lastModified());
    } catch (error) {
      debugPrint('[thumbnail] read failed for $key: $error');
      return null;
    }
  }

  Future<void> write(String key, Uint8List bytes) async {
    final directory = await _resolve();
    if (directory == null) return;
    try {
      // Write under a temporary name and rename into place, so a frame that is
      // still being written is never read back as a truncated image.
      final partial = File('${directory.path}/$key.jpg.part');
      await partial.writeAsBytes(bytes, flush: true);
      await partial.rename('${directory.path}/$key.jpg');

      if (++_writesSincePrune >= _pruneInterval) {
        _writesSincePrune = 0;
        await _prune();
      }
    } catch (error) {
      debugPrint('[thumbnail] write failed for $key: $error');
    }
  }

  /// Drop the oldest frames until the directory is back under budget.
  Future<void> _prune() async {
    final directory = _directory;
    if (directory == null) return;
    try {
      final entries = <(File, DateTime, int)>[];
      var total = 0;
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        entries.add((entity, stat.modified, stat.size));
        total += stat.size;
      }
      if (total <= _maxBytesOnDisk) return;

      entries.sort((a, b) => a.$2.compareTo(b.$2));
      for (final (file, _, size) in entries) {
        if (total <= _maxBytesOnDisk) break;
        await file.delete();
        total -= size;
      }
    } catch (error) {
      debugPrint('[thumbnail] prune failed: $error');
    }
  }
}
