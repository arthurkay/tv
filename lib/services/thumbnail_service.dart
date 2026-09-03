import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/channel.dart';
import 'thumbnail_store.dart';

/// Live thumbnails for channel cards.
///
/// The playlist carries no `tvg-logo` attributes, so the only artwork a channel
/// has is its own picture: a throwaway [Player] opens the stream, waits for the
/// first decoded frame, screenshots it, and shuts down again. That costs
/// bandwidth and a decoder, so captures only start for channels whose cards are
/// actually built, at most [_maxConcurrent] at a time, most-recently-requested
/// first (what the user just scrolled to wins the slot).
///
/// Frames are cached in memory and, on platforms with a filesystem, written to
/// the app cache directory so a previously seen channel has a picture straight
/// away on the next launch.
///
/// A cached frame is served for [ttl] and is only ever swapped out once a newer
/// capture has actually landed — a refresh that is slow, or that fails because
/// the feed is dead or geo-blocked, leaves the previous frame on screen.
class ThumbnailService {
  ThumbnailService._();

  /// How long a frame is served before a refresh is queued behind it.
  static const ttl = Duration(minutes: 30);

  /// Backoff before re-attempting a channel that failed to yield a frame. It
  /// doubles per consecutive failure up to [_maxBackoffDoublings], so a dead or
  /// geo-blocked feed is not re-dialled every couple of minutes forever.
  static const _retryAfterFailure = Duration(minutes: 2);
  static const _maxBackoffDoublings = 4;

  /// Generous on purpose: these HLS feeds have been measured taking ~17s to
  /// deliver a first decoded frame over a slow link, and a timeout under that
  /// means never caching anything.
  static const _captureTimeout = Duration(seconds: 30);

  /// Captures run one at a time through a single shared player (see
  /// [_capture]), so this is fixed at one.
  static const _maxConcurrent = 1;

  /// Whether to open streams in the background purely to harvest a frame.
  ///
  /// Only on the TV target. On Linux desktop, media_kit falls back to software
  /// video output ("EGL display or context is invalid") and a background
  /// player's `open()` never returns, so pre-capture is disabled there and
  /// cards fall back to generated tiles plus frames harvested for free from the
  /// watch screen. Android TV drives video through a SurfaceTexture instead,
  /// which is the path this is meant for — worth confirming on the device.
  static bool backgroundCaptureEnabled =
      defaultTargetPlatform == TargetPlatform.android;

  /// Opening a dead or geo-fenced feed can hang rather than fail, so the open
  /// is bounded separately from the wait for a frame.
  static const _openTimeout = Duration(seconds: 20);

  /// mpv screenshots come back at full stream resolution (~1.1 MB for 1080p),
  /// which is far more than a card needs, so frames are scaled to this width
  /// before being cached.
  static const _frameWidth = 480;

  /// Backstop on retained JPEG bytes. The bundled playlist (88 channels at
  /// roughly 40 KB a frame) never reaches this; a much larger playlist would.
  static const _maxCachedBytes = 8 * 1024 * 1024;

  static final ThumbnailStore _store = ThumbnailStore();

  /// One reusable capture player. Creating and disposing a [Player] plus
  /// [VideoController] per channel wedges libmpv when video output falls back
  /// to software rendering — `open()` and `screenshot()` then never return.
  /// Reusing one player and one video output avoids that churn entirely.
  static Player? _capturePlayer;
  static VideoController? _captureController;
  static final Map<String, _Entry> _entries = {};
  static final List<Channel> _pending = [];
  static int _running = 0;
  static bool _pumpScheduled = false;
  static bool _settled = false;
  static bool _suspended = false;

  /// The newest frame for [channel], or `null` until the first one lands.
  static ValueListenable<Uint8List?> frameOf(Channel channel) => _entryFor(channel).frame;

  /// Ask for a frame. Reads the on-disk copy first and only captures when
  /// there is nothing cached, what is cached has aged past [ttl], or the last
  /// attempt's backoff has elapsed. Cheap enough to call from `build`.
  static void request(Channel channel) {
    final entry = _entryFor(channel);
    if (entry.hydrated) {
      _considerCapture(channel, entry);
      return;
    }
    if (entry.hydrating) return;

    entry.hydrating = true;
    _hydrate(channel, entry).whenComplete(() {
      entry.hydrating = false;
      entry.hydrated = true;
      _considerCapture(channel, entry);
    });
  }

  /// Adopt a frame captured elsewhere — the watch screen already has the
  /// channel decoded, so its screenshots are free.
  static void put(Channel channel, Uint8List bytes) {
    if (bytes.isEmpty) return;
    _publish(channel, _entryFor(channel), bytes);
  }

  static _Entry _entryFor(Channel channel) =>
      _entries.putIfAbsent(channel.url, () => _Entry());

  /// Filenames have to survive being a filename, so key on a hash of the URL
  /// rather than the URL itself. 32-bit FNV-1a, salted with the length, stays
  /// within web's integer range and is stable across launches.
  static String _keyFor(Channel channel) {
    var hash = 0x811c9dc5;
    for (final unit in channel.url.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xFFFFFFFF;
    }
    return '${hash.toRadixString(16).padLeft(8, '0')}-${channel.url.length}';
  }

  static Future<void> _hydrate(Channel channel, _Entry entry) async {
    final stored = await _store.read(_keyFor(channel));
    if (stored == null || entry.frame.value != null) return;
    final (bytes, capturedAt) = stored;
    entry.capturedAt = capturedAt;
    entry.frame.value = bytes;
  }

  static void _considerCapture(Channel channel, _Entry entry) {
    if (!backgroundCaptureEnabled) return;
    if (entry.isFresh || entry.capturing || entry.inBackoff) return;
    // Re-queue at the top: a later request means the card is on screen now.
    _pending.removeWhere((c) => c.url == channel.url);
    _pending.add(channel);
    _schedulePump();
  }

  /// Captures are started between frames, never from inside a build. Opening a
  /// player allocates a video output over a platform channel, and doing that
  /// during the build phase deadlocks against the frame the UI is producing.
  static void _schedulePump() {
    if (_pumpScheduled) return;
    _pumpScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _pumpScheduled = false;
      if (!_settled) {
        // Let the first screen finish painting before competing for the
        // decoder and the network.
        _settled = true;
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
      _pump();
    });
  }

  /// Stop opening streams for frames. The watch screen suspends captures while
  /// it plays: the viewer's stream should have the bandwidth, and mpv routes
  /// ffmpeg's process-global error log to every player, so a capture failing in
  /// the background can otherwise surface as an error on what is playing.
  static void suspend() => _suspended = true;

  static void resume() {
    _suspended = false;
    // A beat of daylight after the watch player's teardown: two players opening
    // and closing in the same instant is what provokes native aborts in mpv.
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (!_suspended) _schedulePump();
    });
  }

  static void _pump() {
    if (_suspended) return;
    while (_running < _maxConcurrent && _pending.isNotEmpty) {
      final channel = _pending.removeLast();
      final entry = _entryFor(channel);
      if (entry.isFresh || entry.capturing) continue;

      _running++;
      entry.capturing = true;
      // A wedged capture must never hold a slot forever: this is the outer
      // guard, on top of the per-step timeouts inside _capture.
      // Outer guard, above the per-step timeouts: open + wait + screenshots +
      // scale, with headroom.
      _capture(channel)
          .timeout(const Duration(seconds: 90), onTimeout: () {
            debugPrint('[thumbnail] ${channel.name}: capture abandoned');
            return null;
          })
          .then((bytes) {
        if (bytes != null && bytes.isNotEmpty) {
          _publish(channel, entry, bytes);
        } else {
          entry.recordFailure();
        }
      }).catchError((Object error) {
        entry.recordFailure();
        debugPrint('[thumbnail] ${channel.name}: $error');
      }).whenComplete(() {
        entry.capturing = false;
        _running--;
        _evict();
        _schedulePump();
      });
    }
  }

  /// Publish a frame to listeners and persist it. This is the only path that
  /// replaces a cached frame.
  static void _publish(Channel channel, _Entry entry, Uint8List bytes) {
    entry.capturedAt = DateTime.now();
    entry.failures = 0;
    entry.failedAt = null;
    entry.frame.value = bytes;
    unawaited(_store.write(_keyFor(channel), bytes));
    _evict();
  }

  static Future<Uint8List?> _capture(Channel channel) async {
    final player = _capturePlayer ??= Player(
      configuration: const PlayerConfiguration(
        muted: true,
        bufferSize: 4 * 1024 * 1024,
      ),
    );
    // Required, not decorative: media_kit starts players with `vid=no` and only
    // turns video decoding on when a controller attaches, and a screenshot is
    // read back from the decoded frame.
    _captureController ??= VideoController(
      player,
      configuration: const VideoControllerConfiguration(width: 640, height: 360),
    );

    // A dead URL should give its slot back immediately rather than sitting out
    // the whole timeout.
    String? failure;
    final errors = player.stream.error.listen((error) => failure ??= error);

    try {
      await player.open(Media(channel.url)).timeout(_openTimeout);
      debugPrint('[thumbnail] ${channel.name}: opened, waiting for video');

      final deadline = DateTime.now().add(_captureTimeout);
      while ((player.state.height ?? 0) <= 0) {
        if (failure != null) {
          debugPrint('[thumbnail] ${channel.name}: $failure');
          return null;
        }
        if (DateTime.now().isAfter(deadline)) {
          debugPrint('[thumbnail] ${channel.name}: no video within '
              '${_captureTimeout.inSeconds}s');
          return null;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      debugPrint('[thumbnail] ${channel.name}: video is '
          '${player.state.width}x${player.state.height}');

      // Dimensions are published a beat before the first frame is renderable,
      // and mpv answers an early screenshot with nothing, so retry briefly.
      for (var attempt = 0; attempt < 3; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final bytes = await player
            .screenshot(format: 'image/jpeg')
            .timeout(const Duration(seconds: 10));
        debugPrint('[thumbnail] ${channel.name}: attempt $attempt -> '
            '${bytes?.length ?? 0} bytes');
        if (bytes != null && bytes.isNotEmpty) {
          final scaled = await scaleFrame(bytes);
          debugPrint('[thumbnail] ${channel.name}: scaled to ${scaled.length} bytes');
          return scaled;
        }
      }
      debugPrint('[thumbnail] ${channel.name}: decoded but returned no frame');
      return null;
    } on TimeoutException {
      // Do NOT dispose the player here. Tearing down a Player while mpv's core
      // thread is mid-event aborts the process with "Callback invoked after it
      // has been deleted" (an FFI callback outliving its owner). A wedged
      // player is left in place: later captures simply time out and back off.
      debugPrint('[thumbnail] ${channel.name}: timed out');
      return null;
    } finally {
      await errors.cancel();
      // Stop pulling the stream between captures; opening the next channel
      // would replace it, but there may not be a next one.
      await _capturePlayer
          ?.stop()
          .timeout(const Duration(seconds: 5), onTimeout: () {});
    }
  }

  /// Scale a full-resolution capture down to card size. Skia handles the
  /// decode and resize; only the small re-encode is Dart, and that runs in a
  /// background isolate so a landing thumbnail never hitches the UI.
  static Future<Uint8List> scaleFrame(Uint8List jpeg) async {
    try {
      final codec = await ui.instantiateImageCodec(jpeg, targetWidth: _frameWidth);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final width = image.width;
      final height = image.height;
      image.dispose();
      codec.dispose();
      if (raw == null) return jpeg;

      return await compute(
        _encodeJpeg,
        _RawFrame(
          Uint8List.view(raw.buffer, raw.offsetInBytes, raw.lengthInBytes),
          width,
          height,
        ),
      ).timeout(const Duration(seconds: 15), onTimeout: () {
        debugPrint('[thumbnail] re-encode timed out, caching full frame');
        return jpeg;
      });
    } catch (error) {
      debugPrint('[thumbnail] scale failed, caching full frame: $error');
      return jpeg;
    }
  }

  static Uint8List _encodeJpeg(_RawFrame frame) {
    final image = img.Image.fromBytes(
      width: frame.width,
      height: frame.height,
      bytes: frame.rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return img.encodeJpg(image, quality: 78, chroma: img.JpegChroma.yuv420);
  }

  static void _evict() {
    final cached = _entries.values.where((e) => e.frame.value != null).toList();
    var total = cached.fold<int>(0, (sum, e) => sum + e.frame.value!.lengthInBytes);
    if (total <= _maxCachedBytes) return;

    cached.sort((a, b) => a.capturedAt!.compareTo(b.capturedAt!));
    for (final entry in cached) {
      if (total <= _maxCachedBytes) break;
      total -= entry.frame.value!.lengthInBytes;
      entry.capturedAt = null;
      entry.frame.value = null;
      // The file is still there, so the next request should re-read it rather
      // than pull the stream again.
      entry.hydrated = false;
    }
  }
}

/// Payload for the isolate that re-encodes a scaled frame.
class _RawFrame {
  final Uint8List rgba;
  final int width;
  final int height;

  const _RawFrame(this.rgba, this.width, this.height);
}

class _Entry {
  final ValueNotifier<Uint8List?> frame = ValueNotifier<Uint8List?>(null);
  DateTime? capturedAt;
  DateTime? failedAt;
  int failures = 0;
  bool capturing = false;

  /// Whether the on-disk copy has been looked for yet.
  bool hydrated = false;
  bool hydrating = false;

  void recordFailure() {
    failures++;
    failedAt = DateTime.now();
  }

  bool get isFresh =>
      frame.value != null &&
      capturedAt != null &&
      DateTime.now().difference(capturedAt!) < ThumbnailService.ttl;

  bool get inBackoff {
    if (failedAt == null) return false;
    final doublings = (failures - 1).clamp(0, ThumbnailService._maxBackoffDoublings);
    final wait = ThumbnailService._retryAfterFailure * (1 << doublings);
    return DateTime.now().difference(failedAt!) < wait;
  }
}
