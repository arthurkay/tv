import 'package:flutter/services.dart';
import '../models/channel.dart';

class M3uParser {
  /// Keyword -> category, in priority order: the first match wins, so more
  /// specific keywords have to come before broader ones.
  static const _categoryRules = [
    ('news', 'News'),
    ('sport', 'Sports'),
    ('vevo', 'Music'),
    ('music', 'Music'),
    ('kids', 'Kids'),
    ('child', 'Kids'),
    ('movie', 'Movies'),
    ('film', 'Movies'),
    ('comedy', 'Comedy'),
    ('lifestyle', 'Lifestyle'),
    ('docu', 'Documentary'),
    ('documentary', 'Documentary'),
    ('entertainment', 'Entertainment'),
  ];

  /// Keywords are matched at word starts only, so "Transport" is not Sports
  /// while "Documentaries" is still Documentary.
  static final _categoryPatterns = {
    for (final (keyword, _) in _categoryRules)
      keyword: RegExp('\\b$keyword', caseSensitive: false),
  };

  static String _inferCategory(String name) {
    for (final (keyword, category) in _categoryRules) {
      if (_categoryPatterns[keyword]!.hasMatch(name)) return category;
    }
    return 'Entertainment';
  }

  /// The display name is everything after the comma that closes the attribute
  /// list. Looking for the last quote first keeps names intact when an
  /// attribute value itself contains a comma.
  static String _extractName(String line) {
    final comma = line.indexOf(',', line.lastIndexOf('"') + 1);
    if (comma < 0) return 'Unknown';
    final name = line.substring(comma + 1).trim();
    return name.isEmpty ? 'Unknown' : name;
  }

  static Future<List<Channel>> load() async {
    final content = await rootBundle.loadString('assets/channels.m3u');
    final lines = content.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final channels = <Channel>[];
    var idx = 0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('#EXTM3U')) continue;
      if (line.startsWith('#EXTINF:')) {
        final url = (i + 1 < lines.length) ? lines[i + 1] : '';
        if (url.isEmpty || url.startsWith('#')) continue;

        final rawName = _extractName(line);
        final tvgMatch = RegExp(r'tvg-id="([^"]*)"').firstMatch(line);
        final tvgId = tvgMatch?.group(1) ?? '';
        final geoBlocked = line.contains('[Geo-blocked]');

        var name = rawName.replaceAll(RegExp(r'\s*\[[^\]]*\]\s*'), '').trim();
        name = name.replaceAll(RegExp(r'\s*\(\d+p\)$'), '').trim();

        channels.add(Channel(
          id: idx++,
          name: name,
          tvgId: tvgId,
          url: url,
          category: _inferCategory(name),
          geoBlocked: geoBlocked,
        ));
        i++;
      }
    }

    return channels;
  }
}
