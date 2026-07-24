part of '../app.dart';

class ClubSummary {
  const ClubSummary({
    required this.name,
    required this.city,
    required this.tournamentsCount,
  });

  final String name;
  final String city;
  final int tournamentsCount;

  String get searchText => '$name $city'.toLowerCase();
  String get mapQuery => '$name, $city';
}

enum _ClubsView { map, list }

class ClubsPage extends StatefulWidget {
  const ClubsPage({super.key, required this.clubs, required this.initialCity});

  final List<ClubSummary> clubs;
  final String initialCity;

  @override
  State<ClubsPage> createState() => _ClubsPageState();
}

class _ClubsPageState extends State<ClubsPage> {
  final TextEditingController searchController = TextEditingController();
  late ClubSummary? selectedClub = _initialClub();
  late String selectedCity = widget.initialCity;
  _ClubsView view = _ClubsView.map;
  String search = '';

  @override
  void dispose() {
    searchController.dispose();
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
    return cities;
  }

  @override
  Widget build(BuildContext context) {
    final clubs = visibleClubs;

    return Scaffold(
      appBar: AppBar(title: const Text('Клубы')),
      body: Column(
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
                if (availableCities.length > 1) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: availableCities.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final city = availableCities[index];
                        return ChoiceChip(
                          label: Text(city),
                          selected:
                              selectedCity.toLowerCase() == city.toLowerCase(),
                          onSelected: (_) => setState(() {
                            selectedCity = city;
                            final cityClubs = widget.clubs.where(
                              (club) =>
                                  club.city.toLowerCase() == city.toLowerCase(),
                            );
                            selectedClub = cityClubs.isEmpty
                                ? null
                                : cityClubs.first;
                          }),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SegmentedButton<_ClubsView>(
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
              ],
            ),
          ),
          Expanded(
            child: clubs.isEmpty
                ? _EmptyState(
                    icon: Icons.store_mall_directory_outlined,
                    title: 'Клубы не найдены',
                    text: 'Для города $selectedCity клубы пока не загружены.',
                  )
                : view == _ClubsView.map
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      _ClubMapPreview(clubs: clubs, selectedClub: selectedClub),
                    ],
                  )
                : ListView.separated(
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
  const _ClubMapPreview({required this.clubs, required this.selectedClub});

  final List<ClubSummary> clubs;
  final ClubSummary? selectedClub;

  @override
  State<_ClubMapPreview> createState() => _ClubMapPreviewState();
}

class _ClubMapPreviewState extends State<_ClubMapPreview> {
  static const _mapboxToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: '',
  );

  Future<List<_ClubMapPoint>>? pointsFuture;

  @override
  void initState() {
    super.initState();
    pointsFuture = _geocodeClubs(widget.clubs);
  }

  @override
  void didUpdateWidget(covariant _ClubMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_clubsSignature(oldWidget.clubs) != _clubsSignature(widget.clubs)) {
      pointsFuture = _geocodeClubs(widget.clubs);
    }
  }

  String _clubsSignature(List<ClubSummary> clubs) =>
      clubs.map((club) => club.mapQuery).join('|');

  Future<List<_ClubMapPoint>> _geocodeClubs(List<ClubSummary> clubs) async {
    final token = await _loadMapboxToken();
    if (token.isEmpty) {
      return const [];
    }
    final points = await Future.wait(
      clubs.take(25).map((club) => _geocode(club, token)),
    );
    return points.whereType<_ClubMapPoint>().toList();
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

  Future<_ClubMapPoint?> _geocode(ClubSummary club, String token) async {
    final uri = Uri.https(
      'api.mapbox.com',
      '/geocoding/v5/mapbox.places/${Uri.encodeComponent(club.mapQuery)}.json',
      {'access_token': token, 'limit': '1', 'language': 'ru', 'country': 'ru'},
    );
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>? ?? const [];
      if (features.isEmpty) {
        return null;
      }
      final center = (features.first as Map<String, dynamic>)['center'];
      if (center is! List || center.length < 2) {
        return null;
      }
      return _ClubMapPoint(
        club: club,
        mapboxToken: token,
        point: _MapPoint(
          latitude: (center[1] as num).toDouble(),
          longitude: (center[0] as num).toDouble(),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  String _staticMapUrl(List<_ClubMapPoint> points) {
    final overlays = points
        .map((item) {
          final selected =
              widget.selectedClub?.name == item.club.name &&
              widget.selectedClub?.city == item.club.city;
          final color = selected ? '0b5f49' : '0f6f55';
          final point = item.point;
          return 'pin-s+$color(${point.longitude.toStringAsFixed(6)},'
              '${point.latitude.toStringAsFixed(6)})';
        })
        .join(',');
    return Uri.https(
      'api.mapbox.com',
      '/styles/v1/mapbox/streets-v12/static/$overlays/auto/900x700@2x',
      {'access_token': points.first.mapboxToken},
    ).toString();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: DecoratedBox(
          decoration: BoxDecoration(color: scheme.surfaceContainerHighest),
          child: FutureBuilder<List<_ClubMapPoint>>(
            future: pointsFuture,
            builder: (context, snapshot) {
              final points = snapshot.data ?? const [];
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (points.isEmpty && _mapboxToken.isEmpty) {
                return const _EmptyState(
                  icon: Icons.map_outlined,
                  title: 'Карта недоступна',
                  text: 'Не удалось получить Mapbox token.',
                );
              }
              if (points.isEmpty) {
                return const _EmptyState(
                  icon: Icons.location_off_outlined,
                  title: 'Координаты не найдены',
                  text: 'Mapbox не нашел клубы выбранного города.',
                );
              }
              return Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    _staticMapUrl(points),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _EmptyState(
                      icon: Icons.map_outlined,
                      title: 'Карта не загрузилась',
                      text: 'Не удалось загрузить карту Mapbox.',
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          '${points.length} клубов на карте',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
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
  const _ClubMapPoint({
    required this.club,
    required this.point,
    required this.mapboxToken,
  });

  final ClubSummary club;
  final _MapPoint point;
  final String mapboxToken;
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
