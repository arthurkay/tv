import 'package:flutter/services.dart';

/// Whether this Android device is a television (declares the leanback
/// feature). False everywhere the platform side is absent.
class TvDevice {
  TvDevice._();

  static const _channel = MethodChannel('vieo/device');
  static Future<bool>? _cached;

  static Future<bool> isTelevision() => _cached ??= _query();

  static Future<bool> _query() async {
    try {
      return await _channel.invokeMethod<bool>('isTelevision') ?? false;
    } catch (_) {
      return false;
    }
  }
}
