import 'package:flutter/services.dart';

/// Bridge to the TV's system speech recognizer, and to search queries the
/// assistant hands the app ("play CNN on Vieo TV").
///
/// Every call degrades to "unavailable" instead of throwing: on desktop and
/// web there is no platform side at all, and a TV without a recognizer simply
/// reports that it has none.
class VoiceSearch {
  VoiceSearch._();

  static const _channel = MethodChannel('vieo/voice');

  /// Whether the device has something that can handle a speech request. The
  /// mic affordance is hidden entirely when it does not.
  static Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system voice prompt; resolves with the recognised text, or null
  /// if the user backed out or nothing was heard.
  static Future<String?> listen() async {
    try {
      return await _channel.invokeMethod<String>('listen');
    } catch (_) {
      return null;
    }
  }

  /// The query the app was cold-started with by the assistant. Consumed once,
  /// so a later rebuild does not replay it.
  static Future<String?> takeLaunchQuery() async {
    try {
      return await _channel.invokeMethod<String>('consumeLaunchQuery');
    } catch (_) {
      return null;
    }
  }

  /// Queries that arrive while the app is already running.
  static void onSearchIntent(void Function(String query) handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSearchIntent') {
        final query = call.arguments as String?;
        if (query != null && query.trim().isNotEmpty) handler(query);
      }
      return null;
    });
  }
}
