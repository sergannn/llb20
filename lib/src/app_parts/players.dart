part of '../app.dart';

class _PlayersPage extends StatefulWidget {
  const _PlayersPage({
    required this.repository,
    required this.searchController,
    required this.search,
    required this.searchHint,
    required this.selectedCity,
    required this.selectedDiscipline,
    required this.sort,
    required this.sortAscending,
    required this.onSortChanged,
    required this.onSearchChanged,
    required this.onCityTap,
    required this.onDisciplineTap,
    required this.onRefresh,
  });

  final LeagueRepository repository;
  final TextEditingController searchController;
  final String search;
  final String searchHint;
  final String selectedCity;
  final DisciplineFilter selectedDiscipline;
  final PlayerSort sort;
  final bool sortAscending;
  final ValueChanged<PlayerSort> onSortChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onCityTap;
  final VoidCallback onDisciplineTap;
  final Future<void> Function() onRefresh;

  @override
  State<_PlayersPage> createState() => _PlayersPageState();
}

class _PlayersPageState extends State<_PlayersPage> {
  static const _pageSize = 200;

  Timer? searchDebounce;
  final ScrollController scrollController = ScrollController();
  List<Player>? listedPlayers;
  bool searching = false;
  bool loadingMore = false;
  bool hasMorePlayers = true;
  String? searchError;
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    scrollController.addListener(_onScroll);
    scheduleSearch(immediate: true);
  }

  @override
  void didUpdateWidget(covariant _PlayersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.search != widget.search ||
        oldWidget.selectedCity != widget.selectedCity ||
        oldWidget.selectedDiscipline != widget.selectedDiscipline ||
        oldWidget.sort != widget.sort ||
        oldWidget.sortAscending != widget.sortAscending) {
      scheduleSearch();
    }
  }

  @override
  void dispose() {
    searchDebounce?.cancel();
    scrollController.dispose();
    super.dispose();
  }

  void scheduleSearch({bool immediate = false}) {
    searchDebounce?.cancel();
    searchDebounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 350),
      () => loadPlayers(widget.search.trim(), reset: true),
    );
  }

  void _onScroll() {
    if (!scrollController.hasClients ||
        loadingMore ||
        searching ||
        !hasMorePlayers) {
      return;
    }
    final position = scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 360) {
      loadPlayers(widget.search.trim());
    }
  }

  Future<void> loadPlayers(String query, {bool reset = false}) async {
    final token = reset ? ++_searchToken : _searchToken;
    final currentOffset = reset ? 0 : (listedPlayers?.length ?? 0);
    setState(() {
      if (reset) {
        searching = true;
        searchError = null;
        hasMorePlayers = true;
        listedPlayers = null;
      } else {
        loadingMore = true;
      }
    });
    try {
      final results = await widget.repository.searchPlayers(
        query,
        discipline: widget.selectedDiscipline,
        city: widget.selectedCity,
        sort: widget.sort,
        sortAscending: widget.sortAscending,
        limit: _pageSize,
        offset: currentOffset,
      );
      if (!mounted || token != _searchToken || widget.search.trim() != query) {
        return;
      }
      setState(() {
        if (reset) {
          listedPlayers = results;
        } else {
          listedPlayers = [...?listedPlayers, ...results];
        }
        hasMorePlayers = results.length >= _pageSize;
      });
    } catch (error) {
      if (mounted) {
        setState(() => searchError = '$error');
      }
    } finally {
      if (mounted) {
        setState(() {
          searching = false;
          loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final players =
        (listedPlayers ??
                widget.repository
                    .players()
                    .where(
                      (player) =>
                          player.matchesDiscipline(widget.selectedDiscipline),
                    )
                    .where(_matchesSelectedCity)
                    .where((player) => player.matchesNameQuery(widget.search)))
            .toList();
    players.sort((a, b) {
      final compare = switch (widget.sort) {
        PlayerSort.surname => a.surnameKey.compareTo(b.surnameKey),
        PlayerSort.russianBilliards => _eloValue(
          a.russianBilliardsElo,
        ).compareTo(_eloValue(b.russianBilliardsElo)),
        PlayerSort.pool => _eloValue(a.poolElo).compareTo(_eloValue(b.poolElo)),
        PlayerSort.tournaments => a.tournamentsCount.compareTo(
          b.tournamentsCount,
        ),
      };
      return widget.sortAscending ? compare : -compare;
    });

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: widget.searchController,
                  onChanged: widget.onSearchChanged,
                  decoration: InputDecoration(
                    hintText: widget.searchHint,
                    prefixIcon: const Icon(Icons.search, size: 26),
                    suffixIcon: widget.search.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Очистить',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              widget.searchController.clear();
                              widget.onSearchChanged('');
                            },
                          ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: LlbAppTheme.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: LlbAppTheme.border),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _FilterChipsRow(
                  chips: [
                    _FilterChipData(
                      icon: Icons.place_outlined,
                      label: widget.selectedCity,
                      onPressed: widget.onCityTap,
                    ),
                    _FilterChipData(
                      icon: Icons.sports_outlined,
                      label: widget.selectedDiscipline.label,
                      onPressed: widget.onDisciplineTap,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                if (searching) const LinearProgressIndicator(minHeight: 2),
                if (searchError != null)
                  MaterialBanner(
                    leading: const Icon(Icons.cloud_off_outlined),
                    content: const Text('Не удалось выполнить поиск игроков.'),
                    actions: [
                      TextButton(
                        onPressed: () => loadPlayers(widget.search.trim()),
                        child: const Text('Еще раз'),
                      ),
                    ],
                  ),
                _PlayersTableHeader(
                  sort: widget.sort,
                  sortAscending: widget.sortAscending,
                  onSortChanged: widget.onSortChanged,
                ),
                const SizedBox(height: 12),
                for (final player in players)
                  _PlayerTile(
                    repository: widget.repository,
                    player: player,
                    showMeta: true,
                    selectedCity: widget.selectedCity,
                  ),
                if (loadingMore)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (players.isEmpty)
                  const _EmptyState(
                    icon: Icons.person_search,
                    title: 'Игрок не найден',
                    text: 'Поиск на этом экране идет только по имени игрока.',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _matchesSelectedCity(Player player) {
    final selected = widget.selectedCity.trim().toLowerCase();
    if (selected.isEmpty) {
      return true;
    }
    return player.city.trim().toLowerCase() == selected;
  }

  int _eloValue(int? value) => value ?? -1;
}

class _PlayersTableHeader extends StatelessWidget {
  const _PlayersTableHeader({
    required this.sort,
    required this.sortAscending,
    required this.onSortChanged,
  });

  final PlayerSort sort;
  final bool sortAscending;
  final ValueChanged<PlayerSort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: Border.all(color: const Color(0xffd7dbd2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SortHeaderButton(
              label: 'Игрок',
              icon: Icons.sort_by_alpha,
              active: sort == PlayerSort.surname,
              ascending: sortAscending,
              onPressed: () => onSortChanged(PlayerSort.surname),
            ),
          ),
          Container(width: 1, height: 44, color: const Color(0xffd7dbd2)),
          SizedBox(
            width: 64,
            child: _SortHeaderButton(
              label: 'РБ',
              icon: Icons.leaderboard_outlined,
              active: sort == PlayerSort.russianBilliards,
              ascending: sortAscending,
              showIcon: false,
              onPressed: () => onSortChanged(PlayerSort.russianBilliards),
            ),
          ),
          Container(width: 1, height: 44, color: const Color(0xffd7dbd2)),
          SizedBox(
            width: 64,
            child: _SortHeaderButton(
              label: 'Пул',
              icon: Icons.leaderboard_outlined,
              active: sort == PlayerSort.pool,
              ascending: sortAscending,
              showIcon: false,
              onPressed: () => onSortChanged(PlayerSort.pool),
            ),
          ),
          Container(width: 1, height: 44, color: const Color(0xffd7dbd2)),
          SizedBox(
            width: 72,
            child: _SortHeaderButton(
              label: 'Турн.',
              icon: Icons.emoji_events_outlined,
              active: sort == PlayerSort.tournaments,
              ascending: sortAscending,
              showIcon: false,
              onPressed: () => onSortChanged(PlayerSort.tournaments),
            ),
          ),
        ],
      ),
    );
  }
}

class _SortHeaderButton extends StatelessWidget {
  const _SortHeaderButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.ascending,
    required this.onPressed,
    this.showIcon = true,
  });

  final String label;
  final IconData icon;
  final bool active;
  final bool ascending;
  final VoidCallback onPressed;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      fontWeight: active ? FontWeight.w900 : FontWeight.w700,
    );

    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        padding: EdgeInsets.symmetric(
          horizontal: showIcon ? 12 : 6,
          vertical: 10,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: textStyle,
            ),
          ),
          if (active) ...[
            const SizedBox(width: 4),
            Icon(
              ascending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16,
            ),
          ],
        ],
      ),
    );
  }
}

// ignore: unused_element
class _RatingsPage extends StatelessWidget {
  const _RatingsPage({
    required this.repository,
    required this.selectedDiscipline,
    required this.onRefresh,
  });

  final LeagueRepository repository;
  final DisciplineFilter selectedDiscipline;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final players =
        repository
            .players()
            .where((player) => player.matchesDiscipline(selectedDiscipline))
            .toList()
          ..sort((a, b) => b.rating.compareTo(a.rating));

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Рейтинг игроков',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < players.length; i++)
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(players[i].name),
                subtitle: Text('${players[i].city} · ${players[i].discipline}'),
                trailing: Text(
                  '${players[i].rating}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  final TextEditingController nameController = TextEditingController(
    text: 'LLB Test Tournament',
  );
  final TextEditingController slugController = TextEditingController();
  final TextEditingController gameController = TextEditingController(
    text: 'Billiards',
  );
  String tournamentType = 'single elimination';
  bool privateTournament = true;
  String result = 'Создайте турнир в Challonge из приложения.';
  bool loading = false;

  @override
  void dispose() {
    nameController.dispose();
    slugController.dispose();
    gameController.dispose();
    super.dispose();
  }

  Future<void> createChallongeTournament() async {
    final name = nameController.text.trim();
    final slug = slugController.text.trim();
    final game = gameController.text.trim();
    if (name.isEmpty || slug.isEmpty || game.isEmpty) {
      setState(() => result = 'Нужны название, slug и игра.');
      return;
    }

    setState(() {
      loading = true;
      result = 'Создаю турнир в Challonge...';
    });

    try {
      final client = ChallongeApiClient();
      final tournament = await client.createTournament(
        name: name,
        url: slug,
        gameName: game,
        tournamentType: tournamentType,
        private: privateTournament,
      );
      setState(() {
        result = 'Создано: ${tournament.title}\n${tournament.bracketUrl}';
      });
    } catch (error) {
      setState(() => result = 'Ошибка: $error');
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Источники данных',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'LLB: структура сайта, турниры, игроки, рейтинги. Challonge: создание сеток и управление турнирами.',
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Название турнира',
                      prefixIcon: Icon(Icons.emoji_events_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: slugController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Slug / URL',
                      prefixIcon: Icon(Icons.link),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: gameController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Игра',
                      prefixIcon: Icon(Icons.sports_esports_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: tournamentType,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Тип сетки',
                      prefixIcon: Icon(Icons.account_tree_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'single elimination',
                        child: Text('Single elimination'),
                      ),
                      DropdownMenuItem(
                        value: 'double elimination',
                        child: Text('Double elimination'),
                      ),
                      DropdownMenuItem(
                        value: 'round robin',
                        child: Text('Round robin'),
                      ),
                      DropdownMenuItem(value: 'swiss', child: Text('Swiss')),
                    ],
                    onChanged: loading
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => tournamentType = value);
                            }
                          },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Приватный турнир'),
                    value: privateTournament,
                    onChanged: loading
                        ? null
                        : (value) => setState(() => privateTournament = value),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: loading ? null : createChallongeTournament,
                    icon: loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_sync),
                    label: const Text('Создать турнир'),
                  ),
                  const SizedBox(height: 12),
                  Text(result),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({
    required this.repository,
    required this.player,
    required this.showMeta,
    required this.selectedCity,
  });

  final LeagueRepository repository;
  final Player player;
  final bool showMeta;
  final String selectedCity;

  @override
  Widget build(BuildContext context) {
    final participantSummary = player.participantSummary;
    final discipline = player.discipline.trim() == 'Заявка LLB'
        ? ''
        : player.discipline;
    final normalizedSelectedCity = selectedCity.trim().toLowerCase();
    final sameAsSelectedCity =
        normalizedSelectedCity.isNotEmpty &&
        player.city.trim().toLowerCase() == normalizedSelectedCity;
    final meta = [
      if (player.city.isNotEmpty && !sameAsSelectedCity) player.city,
      if (player.club.isNotEmpty) player.club,
      if (discipline.isNotEmpty) discipline,
      if (participantSummary.isNotEmpty) participantSummary,
    ].join(' · ');
    final canOpenProfile = player.hasRealLlbId;

    return Card(
      key: ValueKey('player-tile-${player.id}'),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: canOpenProfile
            ? () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PlayerDetailsPage(
                      repository: repository,
                      player: player,
                    ),
                  ),
                );
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 430;
              return compact
                  ? _CompactPlayerTileBody(
                      player: player,
                      meta: meta,
                      showMeta: showMeta,
                    )
                  : _WidePlayerTileBody(
                      player: player,
                      meta: meta,
                      showMeta: showMeta,
                    );
            },
          ),
        ),
      ),
    );
  }
}

class _WidePlayerTileBody extends StatelessWidget {
  const _WidePlayerTileBody({
    required this.player,
    required this.meta,
    required this.showMeta,
  });

  final Player player;
  final String meta;
  final bool showMeta;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _PlayerThumbnail(player: player),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                player.name,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              if (showMeta && meta.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  meta,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.68),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        _PlayerMetricColumns(player: player),
      ],
    );
  }
}

class _CompactPlayerTileBody extends StatelessWidget {
  const _CompactPlayerTileBody({
    required this.player,
    required this.meta,
    required this.showMeta,
  });

  final Player player;
  final String meta;
  final bool showMeta;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PlayerThumbnail(player: player),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.name,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  if (showMeta && meta.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.68),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _PlayerMetricBar(player: player),
      ],
    );
  }
}

class _PlayerThumbnail extends StatelessWidget {
  const _PlayerThumbnail({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 56,
        height: 68,
        color: scheme.primaryContainer,
        child: player.avatarUrl.isEmpty
            ? Center(
                child: Text(
                  player.initials,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              )
            : Image.network(
                player.avatarUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Center(
                  child: Text(
                    player.initials,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _PlayerMetricColumns extends StatelessWidget {
  const _PlayerMetricColumns({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _PlayerMetricCell(label: 'РБ', value: player.russianBilliardsElo),
          const SizedBox(width: 4),
          _PlayerMetricCell(label: 'Пул', value: player.poolElo),
          const SizedBox(width: 4),
          _PlayerMetricCell(label: 'Турн.', value: player.tournamentsCount),
        ],
      ),
    );
  }
}

class _PlayerMetricBar extends StatelessWidget {
  const _PlayerMetricBar({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    final chips = [
      if (player.russianBilliardsElo != null && player.russianBilliardsElo! > 0)
        _MetricChipData(
          label: 'РБ',
          value: '${player.russianBilliardsElo}',
          accent: const Color(0xff0f6f55),
        ),
      if (player.poolElo != null && player.poolElo! > 0)
        _MetricChipData(
          label: 'Пул',
          value: '${player.poolElo}',
          accent: const Color(0xff2f6fb0),
        ),
      if (player.tournamentsCount > 0)
        _MetricChipData(
          label: 'Турн.',
          value: '${player.tournamentsCount}',
          accent: const Color(0xff8b6f12),
        ),
    ];

    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final chip in chips) _PlayerMetricChip(data: chip)],
      ),
    );
  }
}

class _MetricChipData {
  const _MetricChipData({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;
}

class _PlayerMetricChip extends StatelessWidget {
  const _PlayerMetricChip({required this.data});

  final _MetricChipData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 66, minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: data.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            data.label,
            maxLines: 1,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: data.accent,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            data.value,
            maxLines: 1,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerMetricCell extends StatelessWidget {
  const _PlayerMetricCell({required this.label, required this.value});

  final String label;
  final int? value;

  @override
  Widget build(BuildContext context) {
    final text = value == null || value! <= 0 ? '' : '$value';

    return SizedBox(
      width: 40,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            text,
            maxLines: 1,
            softWrap: false,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
