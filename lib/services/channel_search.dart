import '../models/channel.dart';

/// Ranked channel search shared by the typed search box and by queries handed
/// to the app by the TV's assistant.
class ChannelSearch {
  ChannelSearch._();

  /// Spoken queries arrive as commands — "play cnn", "watch bbc news on vieo
  /// tv" — so the framing words are stripped before matching.
  static final _spokenPrefix = RegExp(
    r'^(please\s+)?(play|watch|open|start|find|search\s+for|search|show(\s+me)?|'
    r'tune\s+(in\s+)?to|switch\s+to|go\s+to)\s+',
    caseSensitive: false,
  );
  static final _spokenSuffix = RegExp(
    r'\s+(channel|live|on\s+vieo(\s+tv)?)$',
    caseSensitive: false,
  );

  static String normalize(String raw) {
    var query = raw.trim().toLowerCase();
    query = query.replaceFirst(_spokenPrefix, '');
    query = query.replaceFirst(_spokenSuffix, '');
    return query.trim();
  }

  /// Best matches first: exact name, then name prefix, then name substring,
  /// then all words somewhere in the name, then words spilling into category.
  static List<Channel> run(List<Channel> channels, String rawQuery) {
    final query = normalize(rawQuery);
    if (query.isEmpty) return const [];

    final terms = query.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final matches = <(int, Channel)>[];

    for (final channel in channels) {
      final name = channel.name.toLowerCase();
      final category = channel.category.toLowerCase();

      int? rank;
      if (name == query) {
        rank = 0;
      } else if (name.startsWith(query)) {
        rank = 1;
      } else if (name.contains(query)) {
        rank = 2;
      } else if (terms.every((t) => name.contains(t))) {
        rank = 3;
      } else if (terms.every((t) => name.contains(t) || category.contains(t))) {
        rank = 4;
      }

      if (rank != null) matches.add((rank, channel));
    }

    matches.sort((a, b) {
      final byRank = a.$1.compareTo(b.$1);
      return byRank != 0 ? byRank : a.$2.name.compareTo(b.$2.name);
    });
    return matches.map((match) => match.$2).toList();
  }
}
