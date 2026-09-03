import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'tv_device.dart';

/// Playback settings that only make sense on a television.
class PlayerTuning {
  /// Highest HLS variant a TV is asked to play, in bits per second. The feeds
  /// here offer a 1080p rendition near 4.7 Mbps that TV-class chips decode
  /// with visible stutter; this steers them to the 720p rung instead. Phones
  /// keep the full ladder.
  static const tvMaxBitrate = 2500000;

  static void apply(Player player) {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final native = player.platform;
    if (native is! NativePlayer) return;
    TvDevice.isTelevision().then((isTv) {
      if (!isTv) return;
      native.setProperty('hls-bitrate', '$tvMaxBitrate');
      debugPrint('[player] television: HLS capped at $tvMaxBitrate bps');
    });
  }
}
