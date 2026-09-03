class Channel {
  final int id;
  final String name;
  final String tvgId;
  final String url;
  final String category;
  final bool geoBlocked;

  const Channel({
    required this.id,
    required this.name,
    required this.tvgId,
    required this.url,
    required this.category,
    required this.geoBlocked,
  });
}
