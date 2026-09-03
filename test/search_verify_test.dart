import 'package:flutter_test/flutter_test.dart';
import 'package:vieo_tv/models/channel.dart';
import 'package:vieo_tv/services/channel_search.dart';

Channel _ch(int id, String name, String category) => Channel(
      id: id,
      name: name,
      tvgId: '',
      url: 'http://x/$id',
      category: category,
      geoBlocked: false,
    );

void main() {
  final channels = [
    _ch(0, 'Bondi Vet', 'Entertainment'),
    _ch(1, 'Breaking News by LeadStory', 'News'),
    _ch(2, 'BeIN SPORTS XTRA', 'Sports'),
    _ch(3, 'Action Hollywood Movies', 'Movies'),
    _ch(4, 'News', 'News'),
  ];

  test('exact name outranks prefix and substring', () {
    final results = ChannelSearch.run(channels, 'news');
    expect(results.first.name, 'News');
    expect(results.map((c) => c.name), contains('Breaking News by LeadStory'));
  });

  test('spoken command phrasing is stripped', () {
    for (final spoken in [
      'play bondi vet',
      'watch Bondi Vet',
      'tune in to bondi vet',
      'show me bondi vet channel',
      'please open bondi vet on vieo tv',
    ]) {
      final results = ChannelSearch.run(channels, spoken);
      expect(results.isNotEmpty, isTrue, reason: spoken);
      expect(results.first.name, 'Bondi Vet', reason: spoken);
    }
  });

  test('multi-word queries match out of order', () {
    expect(ChannelSearch.run(channels, 'movies hollywood').first.name,
        'Action Hollywood Movies');
  });

  test('category is searchable', () {
    expect(ChannelSearch.run(channels, 'sports').map((c) => c.name),
        contains('BeIN SPORTS XTRA'));
  });

  test('no match and empty query return nothing', () {
    expect(ChannelSearch.run(channels, 'zzzz'), isEmpty);
    expect(ChannelSearch.run(channels, '   '), isEmpty);
    expect(ChannelSearch.run(channels, 'play'), isEmpty);
  });
}
