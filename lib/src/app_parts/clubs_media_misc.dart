part of '../app.dart';

class ClubSummary {
  const ClubSummary({
    required this.name,
    required this.city,
    required this.tournamentsCount,
    this.address = '',
    this.latitude,
    this.longitude,
  });

  final String name;
  final String city;
  final int tournamentsCount;
  final String address;
  final double? latitude;
  final double? longitude;

  String get searchText => '$name $city $address'.toLowerCase();
  String get mapQuery =>
      address.isEmpty ? '$name, $city' : '$name, $address, $city';
}

enum _ClubsView { map, list }

enum ClubMapProvider {
  osm('osm', 'OSM'),
  mapbox('mapbox', 'Mapbox');

  const ClubMapProvider(this.storageKey, this.label);

  final String storageKey;
  final String label;

  static ClubMapProvider fromStorage(String? raw) {
    for (final provider in values) {
      if (provider.storageKey == raw) {
        return provider;
      }
    }
    return ClubMapProvider.osm;
  }
}

class ClubsPage extends StatefulWidget {
  const ClubsPage({
    super.key,
    required this.clubs,
    required this.initialCity,
    required this.mapProvider,
  });

  final List<ClubSummary> clubs;
  final String initialCity;
  final ClubMapProvider mapProvider;

  @override
  State<ClubsPage> createState() => _ClubsPageState();
}

class _ClubsPageState extends State<ClubsPage> {
  final TextEditingController searchController = TextEditingController();
  final ScrollController cityScrollController = ScrollController();
  final Map<String, GlobalKey> cityChipKeys = {};
  late ClubSummary? selectedClub = _initialClub();
  late String selectedCity = widget.initialCity;
  _ClubsView view = _ClubsView.map;
  String search = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToSelectedCity(),
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    cityScrollController.dispose();
    super.dispose();
  }

  ClubSummary? _initialClub() {
    for (final club in widget.clubs) {
      if (club.city.toLowerCase() == widget.initialCity.toLowerCase()) {
        return club;
      }
    }
    return widget.clubs.isEmpty ? null : widget.clubs.first;
  }

  List<ClubSummary> get visibleClubs {
    final normalized = search.trim().toLowerCase();
    return widget.clubs.where((club) {
      final matchesCity =
          selectedCity.trim().isEmpty ||
          club.city.toLowerCase() == selectedCity.toLowerCase();
      final matchesSearch =
          normalized.isEmpty || club.searchText.contains(normalized);
      return matchesCity && matchesSearch;
    }).toList();
  }

  List<String> get availableCities {
    final cities = widget.clubs
        .map((club) => club.city.trim())
        .where((city) => city.isNotEmpty)
        .toSet()
        .toList();
    cities.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final selectedIndex = cities.indexWhere(
      (city) => city.toLowerCase() == selectedCity.toLowerCase(),
    );
    if (selectedIndex > 0) {
      final selected = cities.removeAt(selectedIndex);
      cities.insert(0, selected);
    }
    return cities;
  }

  void _scrollToSelectedCity() {
    final key = cityChipKeys[selectedCity.toLowerCase()];
    final context = key?.currentContext;
    if (context == null) {
      return;
    }
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _selectCity(String city) {
    setState(() {
      selectedCity = city;
      final cityClubs = widget.clubs.where(
        (club) => club.city.toLowerCase() == city.toLowerCase(),
      );
      selectedClub = cityClubs.isEmpty ? null : cityClubs.first;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToSelectedCity(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clubs = visibleClubs;
    final cityChips = availableCities;

    return Scaffold(
      appBar: AppBar(title: const Text('Клубы')),
      body: clubs.isEmpty
          ? _EmptyState(
              icon: Icons.store_mall_directory_outlined,
              title: 'Клубы не найдены',
              text: 'Для города $selectedCity клубы пока не загружены.',
            )
          : view == _ClubsView.map
          ? Stack(
              children: [
                Positioned.fill(
                  child: _ClubMapPreview(
                    clubs: clubs,
                    selectedClub: selectedClub,
                    mapProvider: widget.mapProvider,
                    onClubSelected: (club) {
                      setState(() => selectedClub = club);
                    },
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: 12,
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      children: [
                        _MapOverlayPanel(
                          child: SearchBar(
                            controller: searchController,
                            hintText: 'Клуб в городе $selectedCity',
                            elevation: const WidgetStatePropertyAll(0),
                            constraints: const BoxConstraints(minHeight: 48),
                            leading: const Icon(Icons.search),
                            trailing: [
                              if (search.isNotEmpty)
                                IconButton(
                                  tooltip: 'Очистить',
                                  onPressed: () {
                                    searchController.clear();
                                    setState(() => search = '');
                                  },
                                  icon: const Icon(Icons.close),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => search = value),
                          ),
                        ),
                        if (cityChips.length > 1) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 40,
                            child: ListView.separated(
                              controller: cityScrollController,
                              scrollDirection: Axis.horizontal,
                              itemCount: cityChips.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final city = cityChips[index];
                                final key = cityChipKeys.putIfAbsent(
                                  city.toLowerCase(),
                                  GlobalKey.new,
                                );
                                return KeyedSubtree(
                                  key: key,
                                  child: _MapOverlayPanel(
                                    child: ChoiceChip(
                                      label: Text(city),
                                      selected:
                                          selectedCity.toLowerCase() ==
                                          city.toLowerCase(),
                                      onSelected: (_) => _selectCity(city),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _MapOverlayPanel(
                            child: SegmentedButton<_ClubsView>(
                              segments: const [
                                ButtonSegment(
                                  value: _ClubsView.map,
                                  icon: Icon(Icons.map_outlined),
                                  label: Text('Карта'),
                                ),
                                ButtonSegment(
                                  value: _ClubsView.list,
                                  icon: Icon(Icons.format_list_bulleted),
                                  label: Text('Список'),
                                ),
                              ],
                              selected: {view},
                              onSelectionChanged: (value) =>
                                  setState(() => view = value.single),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  child: Column(
                    children: [
                      SearchBar(
                        controller: searchController,
                        hintText: 'Клуб в городе $selectedCity',
                        elevation: const WidgetStatePropertyAll(0),
                        constraints: const BoxConstraints(minHeight: 48),
                        leading: const Icon(Icons.search),
                        trailing: [
                          if (search.isNotEmpty)
                            IconButton(
                              tooltip: 'Очистить',
                              onPressed: () {
                                searchController.clear();
                                setState(() => search = '');
                              },
                              icon: const Icon(Icons.close),
                            ),
                        ],
                        onChanged: (value) => setState(() => search = value),
                      ),
                      if (cityChips.length > 1) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 40,
                          child: ListView.separated(
                            controller: cityScrollController,
                            scrollDirection: Axis.horizontal,
                            itemCount: cityChips.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final city = cityChips[index];
                              final key = cityChipKeys.putIfAbsent(
                                city.toLowerCase(),
                                GlobalKey.new,
                              );
                              return KeyedSubtree(
                                key: key,
                                child: ChoiceChip(
                                  label: Text(city),
                                  selected:
                                      selectedCity.toLowerCase() ==
                                      city.toLowerCase(),
                                  onSelected: (_) => _selectCity(city),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: clubs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final club = clubs[index];
                      final selected =
                          selectedClub?.name == club.name &&
                          selectedClub?.city == club.city;
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: selected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                            foregroundColor: selected
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                            child: const Icon(Icons.store_outlined),
                          ),
                          title: Text(
                            club.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${club.city} · турниров: ${club.tournamentsCount}',
                          ),
                          trailing: selected ? const Icon(Icons.map) : null,
                          onTap: () => setState(() => selectedClub = club),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _ClubMapPreview extends StatefulWidget {
  const _ClubMapPreview({
    required this.clubs,
    required this.selectedClub,
    required this.mapProvider,
    required this.onClubSelected,
  });

  final List<ClubSummary> clubs;
  final ClubSummary? selectedClub;
  final ClubMapProvider mapProvider;
  final ValueChanged<ClubSummary> onClubSelected;

  @override
  State<_ClubMapPreview> createState() => _ClubMapPreviewState();
}

class _ClubMapPreviewState extends State<_ClubMapPreview> {
  static const _mapboxToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: '',
  );

  Future<_ClubMapData>? pointsFuture;

  @override
  void initState() {
    super.initState();
    pointsFuture = _loadMapData(widget.clubs);
  }

  @override
  void didUpdateWidget(covariant _ClubMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_clubsSignature(oldWidget.clubs) != _clubsSignature(widget.clubs)) {
      pointsFuture = _loadMapData(widget.clubs);
    }
  }

  String _clubsSignature(List<ClubSummary> clubs) => clubs
      .map(
        (club) =>
            '${club.mapQuery}:${club.latitude ?? ''}:${club.longitude ?? ''}',
      )
      .join('|');

  Future<_ClubMapData> _loadMapData(List<ClubSummary> clubs) async {
    final token = await _loadMapboxToken();
    final city = clubs.firstOrNull?.city.trim() ?? '';
    final poiPoints = city.isEmpty || token.isEmpty
        ? const <_PoiMapPoint>[]
        : await _loadPoiPoints(city, token);
    final clubPoints = await Future.wait(
      clubs.take(25).map((club) => _resolveClubPoint(club, token, poiPoints)),
    );
    final resolvedClubPoints = clubPoints.whereType<_ClubMapPoint>().toList();
    final enrichedPoiPoints = _linkPois(poiPoints, resolvedClubPoints);
    return _ClubMapData(
      token: token,
      clubPoints: resolvedClubPoints,
      poiPoints: enrichedPoiPoints,
    );
  }

  Future<String> _loadMapboxToken() async {
    if (_mapboxToken.isNotEmpty) {
      return _mapboxToken;
    }
    final uri = Uri.parse(
      'https://llb.panfilius.ru/llb-api/',
    ).replace(queryParameters: {'resource': 'app_config'});
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return '';
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return '${data['mapbox_access_token'] ?? ''}'.trim();
    } catch (_) {
      return '';
    }
  }

  Future<_ClubMapPoint?> _resolveClubPoint(
    ClubSummary club,
    String token,
    List<_PoiMapPoint> poiPoints,
  ) async {
    if (club.latitude != null && club.longitude != null) {
      return _ClubMapPoint(
        club: club,
        point: _MapPoint(latitude: club.latitude!, longitude: club.longitude!),
      );
    }
    final poiMatch = _matchPoiToClub(club, poiPoints);
    if (poiMatch != null) {
      return _ClubMapPoint(club: club, point: poiMatch.point);
    }
    if (token.isEmpty) {
      return _searchPointWithNominatim(club);
    }
    final searchboxPoint = await _searchPointWithSearchBox(club, token);
    if (searchboxPoint != null) {
      return searchboxPoint;
    }
    final geocodedPoint = await _geocodeClub(club, token);
    if (geocodedPoint != null) {
      return geocodedPoint;
    }
    return _searchPointWithNominatim(club);
  }

  Future<_ClubMapPoint?> _geocodeClub(ClubSummary club, String token) async {
    for (final query in _clubSearchQueries(club)) {
      final uri = Uri.parse(
        'https://api.mapbox.com/geocoding/v5/mapbox.places/'
        '${Uri.encodeComponent(query)}.json'
        '?${Uri(queryParameters: {'access_token': token, 'limit': '1', 'language': 'ru', 'country': 'ru'}).query}',
      );
      try {
        final response = await http
            .get(uri, headers: const {'User-Agent': 'LLB-Mobile/1.0'})
            .timeout(const Duration(seconds: 8));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final features = data['features'] as List<dynamic>? ?? const [];
        if (features.isEmpty) {
          continue;
        }
        final feature = features.first as Map<String, dynamic>;
        if (!_isSpecificFeature(feature, club, query: query)) {
          continue;
        }
        final center = feature['center'];
        if (center is! List || center.length < 2) {
          continue;
        }
        return _ClubMapPoint(
          club: club,
          point: _MapPoint(
            latitude: (center[1] as num).toDouble(),
            longitude: (center[0] as num).toDouble(),
          ),
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<_ClubMapPoint?> _searchPointWithSearchBox(
    ClubSummary club,
    String token,
  ) async {
    for (final query in _clubSearchQueries(club)) {
      final uri = Uri.https('api.mapbox.com', '/search/searchbox/v1/forward', {
        'q': query,
        'language': 'ru',
        'limit': '5',
        'access_token': token,
      });
      try {
        final response = await http
            .get(uri, headers: const {'User-Agent': 'LLB-Mobile/1.0'})
            .timeout(const Duration(seconds: 8));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final features = data['features'] as List<dynamic>? ?? const [];
        for (final feature in features.whereType<Map<String, dynamic>>()) {
          if (!_matchesSearchboxClub(feature, club, query)) {
            continue;
          }
          final point = _searchboxPoint(feature);
          if (point == null) {
            continue;
          }
          return _ClubMapPoint(club: club, point: point);
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<_ClubMapPoint?> _searchPointWithNominatim(ClubSummary club) async {
    for (final query in _clubSearchQueries(club)) {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'jsonv2',
        'limit': '1',
      });
      try {
        final response = await http
            .get(uri, headers: const {'User-Agent': 'LLB-Mobile/1.0'})
            .timeout(const Duration(seconds: 8));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }
        final items = jsonDecode(response.body) as List<dynamic>;
        if (items.isEmpty) {
          continue;
        }
        final item = items.first as Map<String, dynamic>;
        final lat = double.tryParse('${item['lat'] ?? ''}');
        final lon = double.tryParse('${item['lon'] ?? ''}');
        if (lat == null || lon == null) {
          continue;
        }
        final label = '${item['display_name'] ?? item['name'] ?? ''}'
            .toLowerCase();
        if (!_queryLooksPrecise(query) && !_matchesClubText(club, label)) {
          continue;
        }
        return _ClubMapPoint(
          club: club,
          point: _MapPoint(latitude: lat, longitude: lon),
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<List<_PoiMapPoint>> _loadPoiPoints(String city, String token) async {
    final uri = Uri.https('api.mapbox.com', '/search/searchbox/v1/forward', {
      'q': 'бильярд $city',
      'language': 'ru',
      'limit': '12',
      'access_token': token,
    });
    try {
      final response = await http
          .get(uri, headers: const {'User-Agent': 'LLB-Mobile/1.0'})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _loadPoiPointsFromNominatim(city);
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>? ?? const [];
      final points = <_PoiMapPoint>[];
      for (final feature in features.whereType<Map<String, dynamic>>()) {
        final point = _searchboxPoint(feature);
        if (point == null) {
          continue;
        }
        final properties =
            feature['properties'] as Map<String, dynamic>? ?? const {};
        final poiName =
            '${properties['name'] ?? properties['name_preferred'] ?? ''}'
                .trim();
        if (poiName.isEmpty) {
          continue;
        }
        final fullAddress =
            '${properties['full_address'] ?? properties['place_formatted'] ?? properties['address'] ?? ''}'
                .trim();
        points.add(
          _PoiMapPoint(name: poiName, address: fullAddress, point: point),
        );
      }
      if (points.isEmpty) {
        return _loadPoiPointsFromNominatim(city);
      }
      return points;
    } catch (_) {
      return _loadPoiPointsFromNominatim(city);
    }
  }

  Future<List<_PoiMapPoint>> _loadPoiPointsFromNominatim(String city) async {
    final points = <_PoiMapPoint>[];
    final seen = <String>{};
    for (final query in ['бильярд $city', 'бильярдный клуб $city']) {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'jsonv2',
        'limit': '8',
      });
      try {
        final response = await http
            .get(uri, headers: const {'User-Agent': 'LLB-Mobile/1.0'})
            .timeout(const Duration(seconds: 8));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }
        final items = jsonDecode(response.body) as List<dynamic>;
        for (final item in items.whereType<Map<String, dynamic>>()) {
          final lat = double.tryParse('${item['lat'] ?? ''}');
          final lon = double.tryParse('${item['lon'] ?? ''}');
          if (lat == null || lon == null) {
            continue;
          }
          final name = '${item['name'] ?? item['display_name'] ?? ''}'.trim();
          final address = '${item['display_name'] ?? ''}'.trim();
          if (name.isEmpty || address.isEmpty) {
            continue;
          }
          final key =
              '${name.toLowerCase()}|${lat.toStringAsFixed(5)}|${lon.toStringAsFixed(5)}';
          if (!seen.add(key)) {
            continue;
          }
          points.add(
            _PoiMapPoint(
              name: name,
              address: address,
              point: _MapPoint(latitude: lat, longitude: lon),
            ),
          );
        }
      } catch (_) {
        continue;
      }
    }
    return points;
  }

  bool _isSpecificFeature(
    Map<String, dynamic> feature,
    ClubSummary club, {
    required String query,
  }) {
    final placeTypes = (feature['place_type'] as List<dynamic>? ?? const [])
        .map((item) => '$item'.toLowerCase())
        .toList();
    final label = '${feature['text'] ?? ''} ${feature['place_name'] ?? ''}'
        .toLowerCase();
    if (_queryLooksPrecise(query)) {
      return true;
    }
    final compactLabel = label.replaceAll(RegExp(r'[^a-zа-я0-9]+'), '');
    final compactClub = _compactClubName(club.name);
    if (compactClub.isNotEmpty && compactLabel.contains(compactClub)) {
      return true;
    }
    if (placeTypes.contains('poi') || placeTypes.contains('address')) {
      return true;
    }
    return false;
  }

  _MapPoint? _searchboxPoint(Map<String, dynamic> feature) {
    final properties =
        feature['properties'] as Map<String, dynamic>? ?? const {};
    final coordinates =
        properties['coordinates'] as Map<String, dynamic>? ?? const {};
    final lat = coordinates['latitude'];
    final lon = coordinates['longitude'];
    if (lat is num && lon is num) {
      return _MapPoint(latitude: lat.toDouble(), longitude: lon.toDouble());
    }
    final geometry = feature['geometry'] as Map<String, dynamic>? ?? const {};
    final center = geometry['coordinates'];
    if (center is List && center.length >= 2) {
      return _MapPoint(
        latitude: (center[1] as num).toDouble(),
        longitude: (center[0] as num).toDouble(),
      );
    }
    return null;
  }

  bool _matchesSearchboxClub(
    Map<String, dynamic> feature,
    ClubSummary club,
    String query,
  ) {
    if (_queryLooksPrecise(query)) {
      return true;
    }
    final properties =
        feature['properties'] as Map<String, dynamic>? ?? const {};
    final label =
        '${properties['name'] ?? ''} ${properties['name_preferred'] ?? ''} ${properties['full_address'] ?? ''}'
            .toLowerCase();
    return _matchesClubText(club, label);
  }

  bool _matchesClubText(ClubSummary club, String label) {
    final normalizedLabel = _normalizeClubName(label);
    final compactLabel = _compactClubName(label);
    final normalizedClub = _normalizeClubName(club.name);
    final compactClub = _compactClubName(club.name);
    if (normalizedClub.isNotEmpty &&
        (normalizedLabel == normalizedClub ||
            normalizedLabel.contains(normalizedClub) ||
            normalizedClub.contains(normalizedLabel))) {
      return true;
    }
    if (compactClub.isNotEmpty &&
        compactLabel.isNotEmpty &&
        (compactLabel == compactClub ||
            compactLabel.contains(compactClub) ||
            compactClub.contains(compactLabel))) {
      return true;
    }
    for (final alias in _clubAliases(club)) {
      if (alias.isNotEmpty && label.contains(alias)) {
        return true;
      }
    }
    return false;
  }

  bool _queryLooksPrecise(String query) {
    final normalized = query.toLowerCase();
    return RegExp(r'\d').hasMatch(normalized) ||
        normalized.contains('просп') ||
        normalized.contains('шоссе') ||
        normalized.contains('набереж') ||
        normalized.contains('улиц') ||
        normalized.contains('ул.') ||
        normalized.contains('к.') ||
        normalized.contains('корп');
  }

  List<String> _clubSearchQueries(ClubSummary club) {
    final queries = <String>{};
    if (club.address.trim().isNotEmpty) {
      queries.add('${club.address.trim()}, ${club.city}');
      queries.add('${club.name}, ${club.address.trim()}, ${club.city}');
    }
    final hint = _clubAddressHint(club);
    if (hint.isNotEmpty) {
      queries.add(hint);
    }
    for (final alias in _clubAliases(club)) {
      queries.add('$alias, ${club.city}');
      queries.add('бильярдный клуб $alias, ${club.city}');
    }
    queries.add('${club.name}, ${club.city}');
    return queries.where((query) => query.trim().isNotEmpty).toList();
  }

  String _clubAddressHint(ClubSummary club) {
    final key = _compactClubName(club.name);
    final city = club.city.toLowerCase();
    const hints = <String, String>{
      'frbs': 'набережная Обводного канала, 118С, Санкт-Петербург',
      'playpool': 'Коломяжский проспект, 19 к2, Санкт-Петербург',
      'цбсольгино': 'Приморское шоссе, 4 к1, Санкт-Петербург',
      'ольгино': 'Приморское шоссе, 4 к1, Санкт-Петербург',
      'легендапитер': 'проспект Просвещения, 43, Санкт-Петербург',
      'maximatic': 'проспект Космонавтов, 55, Санкт-Петербург',
      'максиматик': 'проспект Космонавтов, 55, Санкт-Петербург',
      'зебра': 'проспект Косыгина, 30 к1, Санкт-Петербург',
    };
    if (city.contains('санкт-петербург')) {
      return hints[key] ?? '';
    }
    return '';
  }

  List<String> _clubAliases(ClubSummary club) {
    final normalized = _normalizeClubName(club.name);
    final aliases = <String>{club.name.trim()};
    final special = _clubAlias(normalized);
    if (special.isNotEmpty) {
      aliases.add(special);
    }
    if (normalized.contains('maximatic') || normalized.contains('максиматик')) {
      aliases.add('MAXImatic');
      aliases.add('Максиматик');
    }
    if (normalized.contains('frbs')) {
      aliases.add('FRBS-club');
      aliases.add('FRBS club');
    }
    if (normalized.contains('ольгино')) {
      aliases.add('ЦБС Ольгино');
      aliases.add('Центр бильярдного спорта Ольгино');
    }
    if (normalized.contains('playpool') || normalized.contains('play pool')) {
      aliases.add('PLAYPOOL');
      aliases.add('Play Pool');
    }
    if (normalized.contains('зебра')) {
      aliases.add('Zebra');
    }
    if (normalized.contains('легенда')) {
      aliases.add('Легенда-Питер');
      aliases.add('Легенда Питер');
    }
    return aliases.where((value) => value.trim().isNotEmpty).toList();
  }

  _PoiMapPoint? _matchPoiToClub(
    ClubSummary club,
    List<_PoiMapPoint> poiPoints,
  ) {
    final normalizedClub = _normalizeClubName(club.name);
    final compactClub = _compactClubName(club.name);
    for (final poi in poiPoints) {
      final normalizedPoi = _normalizeClubName(poi.name);
      final compactPoi = _compactClubName(poi.name);
      final addressText = '${poi.name} ${poi.address}'.toLowerCase();
      if (normalizedClub.isNotEmpty &&
          (normalizedPoi == normalizedClub ||
              normalizedPoi.contains(normalizedClub) ||
              normalizedClub.contains(normalizedPoi))) {
        return poi;
      }
      if (compactClub.isNotEmpty &&
          compactPoi.isNotEmpty &&
          (compactPoi == compactClub ||
              compactPoi.contains(compactClub) ||
              compactClub.contains(compactPoi))) {
        return poi;
      }
      final alias = _clubAlias(normalizedClub);
      if (alias.isNotEmpty && addressText.contains(alias)) {
        return poi;
      }
    }
    return null;
  }

  List<_PoiMapPoint> _linkPois(
    List<_PoiMapPoint> poiPoints,
    List<_ClubMapPoint> clubPoints,
  ) {
    return [
      for (final poi in poiPoints)
        poi.copyWith(linkedClubKey: _matchClub(poi.name, clubPoints)),
    ];
  }

  String? _matchClub(String poiName, List<_ClubMapPoint> clubPoints) {
    final normalizedPoi = _normalizeClubName(poiName);
    final compactPoi = _compactClubName(poiName);
    if (normalizedPoi.isEmpty) {
      return null;
    }
    for (final item in clubPoints) {
      final normalizedClub = _normalizeClubName(item.club.name);
      final compactClub = _compactClubName(item.club.name);
      if (normalizedClub.isEmpty) {
        continue;
      }
      if (normalizedPoi == normalizedClub ||
          normalizedPoi.contains(normalizedClub) ||
          normalizedClub.contains(normalizedPoi)) {
        return '${item.club.city.toLowerCase()}::${item.club.name.toLowerCase()}';
      }
      if (compactPoi.isNotEmpty &&
          compactClub.isNotEmpty &&
          (compactPoi == compactClub ||
              compactPoi.contains(compactClub) ||
              compactClub.contains(compactPoi))) {
        return '${item.club.city.toLowerCase()}::${item.club.name.toLowerCase()}';
      }
    }
    return null;
  }

  String _compactClubName(String value) =>
      _normalizeClubName(value).replaceAll(' ', '');

  String _clubAlias(String normalizedClub) {
    if (normalizedClub.contains('ольгино')) {
      return 'ольгино';
    }
    if (normalizedClub.contains('frbs')) {
      return 'frbs';
    }
    if (normalizedClub.contains('playpool') ||
        normalizedClub.contains('play pool')) {
      return 'play pool';
    }
    if (normalizedClub.contains('alibi') || normalizedClub.contains('алиби')) {
      return 'алиби';
    }
    return normalizedClub;
  }

  String _normalizeClubName(String value) {
    final common = RegExp(
      r'\b(бильярд|бильярдный|клуб|club|pool|billiard|центр|академия)\b',
      caseSensitive: false,
    );
    return value
        .toLowerCase()
        .replaceAll(common, ' ')
        .replaceAll(RegExp(r'[^a-zа-я0-9]+', caseSensitive: false), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: FutureBuilder<_ClubMapData>(
        future: pointsFuture,
        builder: (context, snapshot) {
          final data =
              snapshot.data ??
              const _ClubMapData(token: '', clubPoints: [], poiPoints: []);
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (data.clubPoints.isEmpty && data.poiPoints.isEmpty) {
            return const _EmptyState(
              icon: Icons.map_outlined,
              title: 'Точек на карте пока нет',
              text: 'Не нашлись ни наши клубы, ни бильярдные POI.',
            );
          }
          return _LiveClubMap(
            data: data,
            selectedClub: widget.selectedClub,
            mapProvider: widget.mapProvider,
            onClubSelected: widget.onClubSelected,
          );
        },
      ),
    );
  }
}

class _MapPoint {
  const _MapPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

class _ClubMapPoint {
  const _ClubMapPoint({required this.club, required this.point});

  final ClubSummary club;
  final _MapPoint point;
}

class _PoiMapPoint {
  const _PoiMapPoint({
    required this.name,
    required this.address,
    required this.point,
    this.linkedClubKey,
  });

  final String name;
  final String address;
  final _MapPoint point;
  final String? linkedClubKey;

  _PoiMapPoint copyWith({String? linkedClubKey}) {
    return _PoiMapPoint(
      name: name,
      address: address,
      point: point,
      linkedClubKey: linkedClubKey ?? this.linkedClubKey,
    );
  }
}

class _ClubMapData {
  const _ClubMapData({
    required this.token,
    required this.clubPoints,
    required this.poiPoints,
  });

  final String token;
  final List<_ClubMapPoint> clubPoints;
  final List<_PoiMapPoint> poiPoints;
}

class _LiveClubMap extends StatefulWidget {
  const _LiveClubMap({
    required this.data,
    required this.selectedClub,
    required this.mapProvider,
    required this.onClubSelected,
  });

  final _ClubMapData data;
  final ClubSummary? selectedClub;
  final ClubMapProvider mapProvider;
  final ValueChanged<ClubSummary> onClubSelected;

  @override
  State<_LiveClubMap> createState() => _LiveClubMapState();
}

class _LiveClubMapState extends State<_LiveClubMap> {
  final MapController mapController = MapController();
  _PoiMapPoint? selectedPoi;

  String _clubKey(ClubSummary club) =>
      '${club.city.toLowerCase()}::${club.name.toLowerCase()}';

  @override
  void didUpdateWidget(covariant _LiveClubMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data && selectedPoi != null) {
      final stillExists = widget.data.poiPoints.any(
        (poi) =>
            poi.name == selectedPoi!.name &&
            poi.point.latitude == selectedPoi!.point.latitude &&
            poi.point.longitude == selectedPoi!.point.longitude,
      );
      if (!stillExists) {
        selectedPoi = null;
      }
    }
    final oldKey = oldWidget.selectedClub == null
        ? null
        : _clubKey(oldWidget.selectedClub!);
    final newKey = widget.selectedClub == null
        ? null
        : _clubKey(widget.selectedClub!);
    if (oldKey != newKey) {
      final focus = _focusPoint();
      if (focus != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          mapController.move(LatLng(focus.latitude, focus.longitude), 13.6);
        });
      }
    }
  }

  _MapPoint? _focusPoint() {
    final selected = widget.selectedClub;
    if (selected != null) {
      for (final item in widget.data.clubPoints) {
        if (_clubKey(item.club) == _clubKey(selected)) {
          return item.point;
        }
      }
    }
    if (widget.data.clubPoints.isNotEmpty) {
      return widget.data.clubPoints.first.point;
    }
    if (widget.data.poiPoints.isNotEmpty) {
      return widget.data.poiPoints.first.point;
    }
    return null;
  }

  LatLng _initialCenter() {
    final focus = _focusPoint();
    if (focus == null) {
      return const LatLng(59.9386, 30.3141);
    }
    return LatLng(focus.latitude, focus.longitude);
  }

  double _initialZoom() => widget.selectedClub == null ? 11.0 : 13.0;

  ClubSummary? _linkedClub(_PoiMapPoint poi) {
    final key = poi.linkedClubKey;
    if (key == null) {
      return null;
    }
    for (final item in widget.data.clubPoints) {
      if (_clubKey(item.club) == key) {
        return item.club;
      }
    }
    return null;
  }

  List<Marker> _buildMarkers(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedKey = widget.selectedClub == null
        ? null
        : _clubKey(widget.selectedClub!);
    final selectedPoi = this.selectedPoi;
    final markers = <Marker>[
      for (final poi in widget.data.poiPoints)
        Marker(
          point: LatLng(poi.point.latitude, poi.point.longitude),
          width: selectedPoi == poi ? 40 : 32,
          height: selectedPoi == poi ? 40 : 32,
          child: GestureDetector(
            onTap: () {
              setState(() => this.selectedPoi = poi);
              mapController.move(
                LatLng(poi.point.latitude, poi.point.longitude),
                mapController.camera.zoom < 13 ? 13 : mapController.camera.zoom,
              );
            },
            child: Tooltip(
              message: poi.name,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: poi.linkedClubKey == null
                      ? const Color(0xFF3F7DFF)
                      : const Color(0xFFF2A51A),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: selectedPoi == poi ? 3 : 2.5,
                  ),
                  boxShadow: const [
                    BoxShadow(color: Color(0x40000000), blurRadius: 8),
                  ],
                ),
                child: Icon(
                  poi.linkedClubKey == null
                      ? Icons.info_outline
                      : Icons.storefront,
                  size: selectedPoi == poi ? 21 : 17,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      for (final item in widget.data.clubPoints)
        Marker(
          point: LatLng(item.point.latitude, item.point.longitude),
          width: _clubKey(item.club) == selectedKey ? 40 : 34,
          height: _clubKey(item.club) == selectedKey ? 40 : 34,
          child: GestureDetector(
            onTap: () {
              setState(() => this.selectedPoi = null);
              widget.onClubSelected(item.club);
            },
            child: Tooltip(
              message: item.club.name,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _clubKey(item.club) == selectedKey
                      ? const Color(0xFF0B5F49)
                      : scheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: const [
                    BoxShadow(color: Color(0x33000000), blurRadius: 6),
                  ],
                ),
                child: Icon(
                  Icons.storefront,
                  size: _clubKey(item.club) == selectedKey ? 22 : 18,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
    ];
    return markers;
  }

  TileLayer _tileLayer() {
    if (widget.mapProvider == ClubMapProvider.mapbox &&
        widget.data.token.isNotEmpty) {
      return TileLayer(
        urlTemplate:
            'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/'
            '{z}/{x}/{y}@2x?access_token=${widget.data.token}',
        userAgentPackageName: 'su.llb.llb_mobile',
      );
    }
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'su.llb.llb_mobile',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: _initialCenter(),
            initialZoom: _initialZoom(),
            onTap: (_, _) => setState(() => selectedPoi = null),
          ),
          children: [
            _tileLayer(),
            MarkerLayer(markers: _buildMarkers(context)),
          ],
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: selectedPoi == null
              ? _MapSummaryCard(data: widget.data)
              : _MapFeatureCard(
                  poi: selectedPoi!,
                  linkedClub: _linkedClub(selectedPoi!),
                  onOpenClub: (club) {
                    setState(() => selectedPoi = null);
                    widget.onClubSelected(club);
                  },
                ),
        ),
      ],
    );
  }
}

class _MapFeatureCard extends StatelessWidget {
  const _MapFeatureCard({
    required this.poi,
    required this.linkedClub,
    required this.onOpenClub,
  });

  final _PoiMapPoint poi;
  final ClubSummary? linkedClub;
  final ValueChanged<ClubSummary> onOpenClub;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 12)],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: linkedClub == null
                    ? const Color(0xFF3F7DFF)
                    : const Color(0xFFF2A51A),
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  linkedClub == null ? Icons.info_outline : Icons.storefront,
                  color: Colors.white,
                  size: 25,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    poi.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (poi.address.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      poi.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (linkedClub != null) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        foregroundColor: scheme.primary,
                      ),
                      onPressed: () => onOpenClub(linkedClub!),
                      icon: const Icon(Icons.storefront, size: 18),
                      label: Text(
                        'Наш клуб: ${linkedClub!.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapSummaryCard extends StatelessWidget {
  const _MapSummaryCard({required this.data});

  final _ClubMapData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${data.clubPoints.length} наших клубов · ${data.poiPoints.length} POI',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _LegendDot(
                  color: Theme.of(context).colorScheme.primary,
                  icon: Icons.storefront,
                  label: 'Наш клуб',
                ),
                const _LegendDot(
                  color: Color(0xFFF7B32B),
                  icon: Icons.link_outlined,
                  label: 'Похожий POI',
                ),
                const _LegendDot(
                  color: Color(0xFF4C82FB),
                  icon: Icons.place_outlined,
                  label: 'Внешний POI',
                ),
              ],
            ),
            if (data.poiPoints.any((item) => item.linkedClubKey != null))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Оранжевые точки похожи на наши клубы и помогают уточнять координаты',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: Icon(icon, size: 10, color: Colors.white),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _MapOverlayPanel extends StatelessWidget {
  const _MapOverlayPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class MediaLibraryPage extends StatefulWidget {
  const MediaLibraryPage({super.key, required this.repository});

  final LeagueRepository repository;

  @override
  State<MediaLibraryPage> createState() => _MediaLibraryPageState();
}

class _MediaLibraryPageState extends State<MediaLibraryPage> {
  final List<_TournamentMediaEntry> entries = [];
  TournamentMediaKind? filter;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(loadMedia());
  }

  Future<void> loadMedia() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final nextEntries = <_TournamentMediaEntry>[];
      for (final tournament in widget.repository.tournaments()) {
        final media = tournament.media.isNotEmpty
            ? tournament.media
            : await widget.repository.tournamentMedia(tournament);
        for (final item in media) {
          nextEntries.add(
            _TournamentMediaEntry(tournament: tournament, media: item),
          );
        }
      }
      nextEntries.sort((a, b) {
        return b.media.createdAt.compareTo(a.media.createdAt);
      });
      if (!mounted) {
        return;
      }
      setState(() {
        entries
          ..clear()
          ..addAll(nextEntries);
      });
    } catch (exception) {
      if (mounted) {
        setState(() => error = 'Не удалось загрузить медиа: $exception');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  List<_TournamentMediaEntry> get visibleEntries {
    final selected = filter;
    if (selected == null) {
      return entries;
    }
    return entries.where((entry) => entry.media.kind == selected).toList();
  }

  @override
  Widget build(BuildContext context) {
    final visible = visibleEntries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Медиа'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: loading ? null : loadMedia,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (loading) const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('Все (${entries.length})'),
                    selected: filter == null,
                    onSelected: (_) => setState(() => filter = null),
                  ),
                  ChoiceChip(
                    label: Text(
                      'Фото (${entries.where((entry) => !entry.media.isVideo).length})',
                    ),
                    selected: filter == TournamentMediaKind.photo,
                    onSelected: (_) =>
                        setState(() => filter = TournamentMediaKind.photo),
                  ),
                  ChoiceChip(
                    label: Text(
                      'Видео (${entries.where((entry) => entry.media.isVideo).length})',
                    ),
                    selected: filter == TournamentMediaKind.video,
                    onSelected: (_) =>
                        setState(() => filter = TournamentMediaKind.video),
                  ),
                ],
              ),
            ),
          ),
          if (error != null)
            MaterialBanner(
              leading: const Icon(Icons.cloud_off_outlined),
              content: Text(error!),
              actions: [
                TextButton(onPressed: loadMedia, child: const Text('Еще раз')),
              ],
            ),
          Expanded(
            child: visible.isEmpty && !loading
                ? const _EmptyState(
                    icon: Icons.perm_media_outlined,
                    title: 'Медиа пока нет',
                    text: 'Фото и видео появятся после загрузки в турнирах.',
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.76,
                        ),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      return _MediaLibraryTile(entry: visible[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _TournamentMediaEntry {
  const _TournamentMediaEntry({required this.tournament, required this.media});

  final Tournament tournament;
  final TournamentMedia media;
}

class _MediaLibraryTile extends StatelessWidget {
  const _MediaLibraryTile({required this.entry});

  final _TournamentMediaEntry entry;

  @override
  Widget build(BuildContext context) {
    final media = entry.media;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: media.url.isEmpty
            ? null
            : () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _MediaLibraryViewer(entry: entry),
                  ),
                );
              },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (!media.isVideo && media.url.isNotEmpty)
                    Image.network(
                      media.url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _MediaLibraryFallback(media: media),
                    )
                  else
                    _MediaLibraryFallback(media: media),
                  if (media.isVideo)
                    Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.scrim.withValues(alpha: 0.52),
                          shape: BoxShape.circle,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    media.title.isEmpty ? media.kind.label : media.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    entry.tournament.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaLibraryFallback extends StatelessWidget {
  const _MediaLibraryFallback({required this.media});

  final TournamentMedia media;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          media.isVideo ? Icons.videocam_outlined : Icons.image_outlined,
          color: scheme.onSurfaceVariant,
          size: 42,
        ),
      ),
    );
  }
}

class _MediaLibraryViewer extends StatelessWidget {
  const _MediaLibraryViewer({required this.entry});

  final _TournamentMediaEntry entry;

  @override
  Widget build(BuildContext context) {
    final media = entry.media;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          media.title.isEmpty ? media.kind.label : media.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: media.isVideo
          ? WebViewWidget(
              controller: WebViewController()
                ..setJavaScriptMode(JavaScriptMode.unrestricted)
                ..loadRequest(Uri.parse(media.url)),
            )
          : InteractiveViewer(
              child: Center(
                child: Image.network(
                  media.url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      _MediaLibraryFallback(media: media),
                ),
              ),
            ),
    );
  }
}

class NewsPage extends StatelessWidget {
  const NewsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Новости')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(
                    Icons.article_outlined,
                    color: scheme.onPrimaryContainer,
                    size: 34,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Раздел в разработке',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Новости Лиги появятся здесь после подключения источника.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.onPrimaryContainer),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const _CuePlaceholderTile(
            icon: Icons.campaign_outlined,
            title: 'Анонсы',
            subtitle: 'Новые турниры, клубы и изменения расписания',
          ),
          const _CuePlaceholderTile(
            icon: Icons.emoji_events_outlined,
            title: 'Итоги турниров',
            subtitle: 'Короткие заметки по завершенным событиям',
          ),
          const _CuePlaceholderTile(
            icon: Icons.notifications_none,
            title: 'Уведомления',
            subtitle: 'Важные новости для игроков и организаторов',
          ),
        ],
      ),
    );
  }
}

class CuesPage extends StatelessWidget {
  const CuesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Кии')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Icon(
                    Icons.construction_outlined,
                    color: scheme.onPrimaryContainer,
                    size: 34,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Раздел в разработке',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Каталог киев появится позже.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.onPrimaryContainer),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const _CuePlaceholderTile(
            icon: Icons.inventory_2_outlined,
            title: 'Каталог',
            subtitle: 'Марка, модель, длина, вес и материал',
          ),
          const _CuePlaceholderTile(
            icon: Icons.tune_outlined,
            title: 'Подбор',
            subtitle: 'Фильтры по дисциплине и параметрам',
          ),
          const _CuePlaceholderTile(
            icon: Icons.bookmark_border,
            title: 'Избранное',
            subtitle: 'Сохраненные варианты для сравнения',
          ),
        ],
      ),
    );
  }
}

class _CuePlaceholderTile extends StatelessWidget {
  const _CuePlaceholderTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        enabled: false,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}
