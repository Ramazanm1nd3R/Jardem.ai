/// Raster tile source of [JardemMap].
///
/// The mock-ups were drawn over CARTO Voyager, but since 2026 CARTO serves an
/// «API KEY REQUIRED» watermark tile to key-less requests, so the default is
/// the key-less OpenStreetMap standard layer, softened towards the same pale
/// look. Override at build time:
///
/// ```
/// --dart-define=JARDEM_TILE_URL=https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png?api_key=…
/// --dart-define=JARDEM_TILE_ATTRIBUTION="© OpenStreetMap contributors, © CARTO"
/// ```
class MapTiles {
  const MapTiles({
    required this.urlTemplate,
    required this.attribution,
    this.subdomains = const [],
    this.soften = false,
  });

  /// Reads `JARDEM_TILE_URL` / `JARDEM_TILE_ATTRIBUTION`; defaults to [osm].
  factory MapTiles.fromEnvironment() {
    const url = String.fromEnvironment('JARDEM_TILE_URL');
    const credit = String.fromEnvironment('JARDEM_TILE_ATTRIBUTION');
    if (url.isEmpty) return osm;
    return MapTiles(
      urlTemplate: url,
      attribution: credit.isEmpty ? osm.attribution : credit,
      subdomains: url.contains('{s}') ? const ['a', 'b', 'c', 'd'] : const [],
    );
  }

  static const MapTiles osm = MapTiles(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attribution: '© OpenStreetMap contributors',
    soften: true,
  );

  /// Needs `?api_key=…` appended to the template to render real tiles.
  static const MapTiles cartoVoyager = MapTiles(
    urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
    attribution: '© OpenStreetMap contributors, © CARTO',
    subdomains: ['a', 'b', 'c', 'd'],
  );

  final String urlTemplate;
  final String attribution;
  final List<String> subdomains;

  /// Desaturate and lighten the tiles so markers and routes stand out.
  final bool soften;
}
