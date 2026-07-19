import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'llb_auth.dart';
import 'models.dart';
import 'repositories.dart';

class LlbApp extends StatelessWidget {
  const LlbApp({super.key, this.repository});

  final LeagueRepository? repository;

  @override
  Widget build(BuildContext context) {
    const baize = Color(0xff0f5b46);
    const wine = Color(0xff8f243b);
    const felt = Color(0xfff3f5ee);
    const border = Color(0xffdce2d6);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LLB',
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final scale = math.min(media.textScaler.scale(1), 1.08);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(scale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: ThemeData(
        useMaterial3: true,
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: baize,
              brightness: Brightness.light,
            ).copyWith(
              primary: baize,
              secondary: wine,
              tertiary: const Color(0xffc79a2f),
              surface: const Color(0xfffffff9),
              surfaceContainerHighest: const Color(0xffe7ece3),
              outline: const Color(0xff76847a),
            ),
        scaffoldBackgroundColor: felt,
        cardTheme: CardThemeData(
          color: const Color(0xfffffff9),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: border),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: felt,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
            color: Color(0xff17201b),
            fontSize: 24,
            fontWeight: FontWeight.w500,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          height: 76,
          indicatorColor: const Color(0xffd2f3e3),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            return TextStyle(
              fontSize: 15,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              letterSpacing: 0,
            );
          }),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xfffffff9),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: baize, width: 1.4),
          ),
        ),
      ),
      home: LeagueHomePage(repository: repository),
    );
  }
}

class LeagueHomePage extends StatefulWidget {
  const LeagueHomePage({super.key, this.repository});

  final LeagueRepository? repository;

  @override
  State<LeagueHomePage> createState() => _LeagueHomePageState();
}

class _LeagueHomePageState extends State<LeagueHomePage> {
  static const _defaultCity = 'Санкт-Петербург';
  static const _selectedCityKey = 'selected_city';
  static const _recentCitiesKey = 'recent_cities';
  static const _disciplineKey = 'selected_discipline';
  static const _llbUsernameKey = 'llb_username';
  static const _llbCookiesKey = 'llb_cookies';
  static const _llbPlayerIdKey = 'llb_player_id';
  static const _initialSearch = String.fromEnvironment('LLB_INITIAL_SEARCH');
  static const _initialTournamentId = String.fromEnvironment(
    'LLB_OPEN_TOURNAMENT_ID',
  );
  static const _initialTab = int.fromEnvironment(
    'LLB_INITIAL_TAB',
    defaultValue: 0,
  );

  late final LeagueRepository repository =
      widget.repository ?? ApiLeagueRepository();
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  final TextEditingController searchController = TextEditingController(
    text: _initialSearch,
  );
  int selectedTab = _initialTab.clamp(0, 2);
  String search = _initialSearch;
  String selectedCity = _defaultCity;
  DisciplineFilter selectedDiscipline = DisciplineFilter.russianBilliards;
  List<String> recentCities = const [];
  PlayerSort playerSort = PlayerSort.russianBilliards;
  bool playerSortAscending = false;
  String? llbUsername;
  String? llbPlayerId;
  bool llbSessionValid = false;
  bool loading = true;
  bool initialDataLoaded = false;
  bool initialTournamentOpened = false;
  String? loadError;

  @override
  void initState() {
    super.initState();
    loadSavedPreferences();
    loadSavedLlbSession();
    loadLeagueData();
  }

  @override
  void dispose() {
    searchController.dispose();
    repository.dispose();
    super.dispose();
  }

  Future<void> loadLeagueData() async {
    setState(() {
      loading = true;
      loadError = null;
    });

    try {
      await repository.load();
    } catch (error) {
      loadError = '$error';
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
          initialDataLoaded = true;
        });
        unawaited(openInitialTournamentIfNeeded());
      }
    }
  }

  Future<void> openInitialTournamentIfNeeded() async {
    if (initialTournamentOpened || _initialTournamentId.trim().isEmpty) {
      return;
    }
    initialTournamentOpened = true;
    final id = _initialTournamentId.trim();
    final tournament = repository.tournaments().where((item) {
      return item.id == id;
    }).firstOrNull;
    if (tournament == null || !mounted) {
      return;
    }
    final details = await repository.tournamentDetails(tournament);
    if (!mounted) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            TournamentDetailsPage(repository: repository, tournament: details),
      ),
    );
  }

  Future<void> loadSavedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCity = _emptyToNull(prefs.getString(_selectedCityKey));
    final savedDiscipline = DisciplineFilter.fromStorage(
      prefs.getString(_disciplineKey),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      selectedCity = savedCity ?? _defaultCity;
      selectedDiscipline = savedDiscipline;
      recentCities = prefs.getStringList(_recentCitiesKey) ?? const [];
    });
  }

  Future<void> loadSavedLlbSession() async {
    final savedUsername = await secureStorage.read(key: _llbUsernameKey);
    final savedCookies = await secureStorage.read(key: _llbCookiesKey);
    var savedPlayerId = await secureStorage.read(key: _llbPlayerIdKey);
    if (savedUsername == null || savedCookies == null || savedCookies.isEmpty) {
      return;
    }

    final client = LlbWebAuthClient();
    client.loadEncodedCookies(savedCookies);
    try {
      final valid = await client.sessionValid();
      if (valid && (savedPlayerId == null || savedPlayerId.isEmpty)) {
        savedPlayerId = await client.currentPlayerId(username: savedUsername);
        if (savedPlayerId != null && savedPlayerId.isNotEmpty) {
          await secureStorage.write(key: _llbPlayerIdKey, value: savedPlayerId);
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        llbUsername = savedUsername;
        llbPlayerId = savedPlayerId;
        llbSessionValid = valid;
      });
    } finally {
      client.close();
    }
  }

  Future<void> showLlbLoginDialog() async {
    final result = await showDialog<_LlbLoginSuccess>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _LlbLoginDialog(),
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      llbUsername = result.username;
      llbPlayerId = result.playerId;
      llbSessionValid = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Вход выполнен: ${result.username}')),
    );
  }

  Future<void> logoutLlb() async {
    await secureStorage.delete(key: _llbUsernameKey);
    await secureStorage.delete(key: _llbCookiesKey);
    await secureStorage.delete(key: _llbPlayerIdKey);
    if (!mounted) {
      return;
    }
    setState(() {
      llbUsername = null;
      llbPlayerId = null;
      llbSessionValid = false;
    });
  }

  Future<void> selectCity(String city) async {
    final normalized = city.trim();
    if (normalized.isEmpty) {
      return;
    }
    final nextRecent = [
      normalized,
      ...recentCities.where(
        (item) => item.toLowerCase() != normalized.toLowerCase(),
      ),
    ].take(8).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedCityKey, normalized);
    await prefs.setStringList(_recentCitiesKey, nextRecent);
    if (!mounted) {
      return;
    }
    searchController.clear();
    setState(() {
      selectedCity = normalized;
      recentCities = nextRecent;
      search = '';
      selectedTab = 0;
    });
  }

  Future<void> selectDiscipline(DisciplineFilter discipline) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_disciplineKey, discipline.storageKey);
    if (!mounted) {
      return;
    }
    setState(() {
      selectedDiscipline = discipline;
      selectedTab = 0;
    });
  }

  List<String> citySuggestions(String query) {
    final normalized = query.trim().toLowerCase();
    final cities = <String>{};
    for (final tournament in repository.tournaments()) {
      final city = tournament.city.trim();
      if (city.isNotEmpty && _looksLikeCity(city)) {
        cities.add(city);
      }
    }
    for (final player in repository.players()) {
      final city = player.city.trim();
      if (city.isNotEmpty && _looksLikeCity(city)) {
        cities.add(city);
      }
    }

    final sorted = cities.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final matched = sorted.where((city) {
      final value = city.toLowerCase();
      return value.contains(normalized);
    }).toList();
    if (normalized.isEmpty && recentCities.isNotEmpty) {
      return [
        ...recentCities.where(cities.contains),
        ...sorted.where((city) => !recentCities.contains(city)),
      ].take(10).toList();
    }
    return matched.take(10).toList();
  }

  List<String> clubSuggestions(String query) {
    final normalized = query.trim().toLowerCase();
    if (selectedTab != 0 || normalized.length < 2) {
      return const [];
    }
    final clubs = <String>{};
    for (final tournament in repository.tournaments()) {
      final club = tournament.club.trim();
      if (club.isEmpty) {
        continue;
      }
      if (tournament.city.toLowerCase() != selectedCity.toLowerCase()) {
        continue;
      }
      if (!tournament.matchesDiscipline(selectedDiscipline)) {
        continue;
      }
      if (club.toLowerCase().contains(normalized)) {
        clubs.add(club);
      }
    }
    final sorted = clubs.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted.take(6).toList();
  }

  bool _looksLikeCity(String value) {
    final text = value.trim();
    final lower = text.toLowerCase();
    return text.length <= 32 &&
        !lower.contains('этап') &&
        !lower.contains('куб') &&
        !lower.contains('турнир') &&
        !lower.contains('чемпионат') &&
        !lower.contains('первенство');
  }

  void changeTab(int index) {
    if (index == selectedTab) {
      return;
    }
    searchController.clear();
    setState(() {
      selectedTab = index;
      search = '';
    });
  }

  void changePlayerSort(PlayerSort nextSort) {
    setState(() {
      if (playerSort == nextSort) {
        playerSortAscending = !playerSortAscending;
        return;
      }
      playerSort = nextSort;
      playerSortAscending = nextSort == PlayerSort.surname;
    });
  }

  String get searchHint {
    return switch (selectedTab) {
      0 => 'Турнир или клуб',
      1 => 'Игрок',
      2 => 'Трансляция или турнир',
      _ => 'Поиск',
    };
  }

  Future<void> showCityPicker() async {
    final city = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _CityPickerSheet(
        initialCity: selectedCity,
        suggestionsFor: citySuggestions,
      ),
    );
    if (city != null) {
      await selectCity(city);
    }
  }

  Future<void> showDisciplinePicker() async {
    final discipline = await showModalBottomSheet<DisciplineFilter>(
      context: context,
      useSafeArea: true,
      builder: (context) =>
          _DisciplinePickerSheet(selectedDiscipline: selectedDiscipline),
    );
    if (discipline != null) {
      await selectDiscipline(discipline);
    }
  }

  String? _emptyToNull(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _TournamentsPage(
        repository: repository,
        search: search,
        selectedCity: selectedCity,
        selectedDiscipline: selectedDiscipline,
        onRefresh: loadLeagueData,
      ),
      _PlayersPage(
        repository: repository,
        search: search,
        selectedCity: selectedCity,
        selectedDiscipline: selectedDiscipline,
        sort: playerSort,
        sortAscending: playerSortAscending,
        onSortChanged: changePlayerSort,
        onRefresh: loadLeagueData,
      ),
      _VideoPage(
        repository: repository,
        search: search,
        llbUsername: llbUsername,
        llbPlayerId: llbPlayerId,
        onRefresh: loadLeagueData,
      ),
      // _RatingsPage(
      //   repository: repository,
      //   selectedDiscipline: selectedDiscipline,
      //   onRefresh: loadLeagueData,
      // ),
      // _SettingsPage(onRefresh: loadLeagueData),
    ];
    final clubs = clubSuggestions(search);

    return Scaffold(
      drawer: _SettingsDrawer(
        repository: repository,
        selectedCity: selectedCity,
        selectedDiscipline: selectedDiscipline,
        llbUsername: llbUsername,
        llbPlayerId: llbPlayerId,
        llbSessionValid: llbSessionValid,
        citySuggestions: citySuggestions,
        onCitySelected: selectCity,
        onDisciplineSelected: selectDiscipline,
        onLlbLogin: showLlbLoginDialog,
        onLlbLogout: logoutLlb,
      ),
      appBar: AppBar(
        toolbarHeight: 56,
        leadingWidth: 56,
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: 'Настройки',
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Icons.menu, size: 30),
          ),
        ),
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('Лига бильярдистов', maxLines: 1),
        ),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: loading ? null : loadLeagueData,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(clubs.isEmpty ? 112 : 158),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SearchBar(
                  controller: searchController,
                  hintText: searchHint,
                  elevation: const WidgetStatePropertyAll(0),
                  constraints: const BoxConstraints(minHeight: 50),
                  backgroundColor: const WidgetStatePropertyAll(
                    Color(0xffe7ece7),
                  ),
                  side: const WidgetStatePropertyAll(
                    BorderSide(color: Color(0xffd8ded6)),
                  ),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 14),
                  ),
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
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.place_outlined, size: 18),
                          label: Text(selectedCity),
                          visualDensity: VisualDensity.compact,
                          onPressed: showCityPicker,
                        ),
                        const SizedBox(width: 8),
                        ActionChip(
                          avatar: const Icon(Icons.sports_outlined, size: 18),
                          label: Text(selectedDiscipline.label),
                          visualDensity: VisualDensity.compact,
                          onPressed: showDisciplinePicker,
                        ),
                      ],
                    ),
                  ),
                ),
                if (clubs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final club in clubs)
                          ActionChip(
                            avatar: const Icon(Icons.store_outlined, size: 18),
                            label: Text(club),
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              searchController.text = club;
                              setState(() => search = club);
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (loading) const LinearProgressIndicator(minHeight: 2),
            if (loadError != null)
              MaterialBanner(
                leading: const Icon(Icons.cloud_off_outlined),
                content: Text(
                  'Не удалось обновить данные. Показана последняя локальная копия.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  TextButton(
                    onPressed: loadLeagueData,
                    child: const Text('Еще раз'),
                  ),
                ],
              ),
            Expanded(
              child: !initialDataLoaded && loading
                  ? const _InitialLoadingView()
                  : pages[selectedTab],
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedTab,
        onDestinationSelected: changeTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events),
            label: 'Турниры',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Игроки',
          ),
          NavigationDestination(
            icon: Icon(Icons.videocam_outlined),
            selectedIcon: Icon(Icons.videocam),
            label: 'Видео',
          ),
          // NavigationDestination(
          //   icon: Icon(Icons.leaderboard_outlined),
          //   selectedIcon: Icon(Icons.leaderboard),
          //   label: 'Рейтинги',
          // ),
          // NavigationDestination(
          //   icon: Icon(Icons.tune_outlined),
          //   selectedIcon: Icon(Icons.tune),
          //   label: 'API',
          // ),
        ],
      ),
    );
  }
}

class _VideoPage extends StatefulWidget {
  const _VideoPage({
    required this.repository,
    required this.search,
    required this.llbUsername,
    required this.llbPlayerId,
    required this.onRefresh,
  });

  final LeagueRepository repository;
  final String search;
  final String? llbUsername;
  final String? llbPlayerId;
  final Future<void> Function() onRefresh;

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  @override
  Widget build(BuildContext context) {
    final query = widget.search.trim().toLowerCase();
    final streams = widget.repository.videoStreams().where((stream) {
      if (query.isEmpty) return true;
      return stream.tournamentTitle.toLowerCase().contains(query) ||
          stream.playerName.toLowerCase().contains(query) ||
          stream.providerLabel.toLowerCase().contains(query);
    }).toList();
    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Text(
            'Видео',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 16),
          if (streams.isEmpty)
            const _EmptyState(
              icon: Icons.videocam_outlined,
              title: 'Пока нет трансляций',
              text: '',
            )
          else ...[
            Text(
              'Трансляции',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            for (final stream in streams) _VideoStreamCard(stream: stream),
          ],
        ],
      ),
    );
  }
}

class _VideoStreamCard extends StatelessWidget {
  const _VideoStreamCard({required this.stream});

  final VideoStream stream;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: stream.playbackUrl.isEmpty
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _BracketWebViewPage(
                    title: stream.providerLabel,
                    url: stream.playbackUrl,
                  ),
                ),
              ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    stream.isLive
                        ? Icons.radio_button_checked
                        : Icons.videocam_outlined,
                    color: stream.isLive
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      stream.tournamentTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(
                    icon: Icons.sensors_outlined,
                    label: stream.statusLabel,
                  ),
                  _InfoChip(
                    icon: Icons.play_circle_outline,
                    label: stream.providerLabel,
                  ),
                  if (stream.playerName.isNotEmpty)
                    _InfoChip(
                      icon: Icons.person_outline,
                      label: stream.playerName,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TournamentsPage extends StatefulWidget {
  const _TournamentsPage({
    required this.repository,
    required this.search,
    required this.selectedCity,
    required this.selectedDiscipline,
    required this.onRefresh,
  });

  final LeagueRepository repository;
  final String search;
  final String selectedCity;
  final DisciplineFilter selectedDiscipline;
  final Future<void> Function() onRefresh;

  @override
  State<_TournamentsPage> createState() => _TournamentsPageState();
}

class _TournamentsPageState extends State<_TournamentsPage> {
  static const _tabs = [
    _TournamentTabSpec(
      status: TournamentStatus.upcoming,
      label: 'Скоро',
      icon: Icons.event_outlined,
    ),
    _TournamentTabSpec(
      status: TournamentStatus.live,
      label: 'Онлайн',
      icon: Icons.play_circle_outline,
    ),
    _TournamentTabSpec(
      status: TournamentStatus.finished,
      label: 'Итоги',
      icon: Icons.flag_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final selectedCityValue = widget.selectedCity.trim();
    final visibleTournaments = widget.repository.tournaments().where((
      tournament,
    ) {
      final cityMatches =
          tournament.city.toLowerCase() == selectedCityValue.toLowerCase();
      return cityMatches &&
          tournament.matchesDiscipline(widget.selectedDiscipline) &&
          tournament.matchesQuery(widget.search);
    }).toList();
    final initialTabIndex = _initialTabIndex(visibleTournaments);

    return DefaultTabController(
      key: ValueKey(
        '$selectedCityValue:${widget.search}:$initialTabIndex:${visibleTournaments.length}',
      ),
      length: _tabs.length,
      initialIndex: initialTabIndex,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: _TournamentTabBar(
              tabs: _tabs,
              tournaments: visibleTournaments,
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final tab in _tabs)
                  _TournamentStatusList(
                    repository: widget.repository,
                    tournaments: visibleTournaments
                        .where((tournament) => tournament.status == tab.status)
                        .toList(),
                    onRefresh: widget.onRefresh,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _initialTabIndex(List<Tournament> tournaments) {
    for (var index = 0; index < _tabs.length; index++) {
      final status = _tabs[index].status;
      if (tournaments.any((tournament) => tournament.status == status)) {
        return index;
      }
    }
    return 0;
  }
}

class _TournamentTabSpec {
  const _TournamentTabSpec({
    required this.status,
    required this.label,
    required this.icon,
  });

  final TournamentStatus status;
  final String label;
  final IconData icon;
}

class _TournamentTabBar extends StatelessWidget {
  const _TournamentTabBar({required this.tabs, required this.tournaments});

  final List<_TournamentTabSpec> tabs;
  final List<Tournament> tournaments;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: const Color(0xffd7dbd2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: TabBar(
        dividerHeight: 0,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(7),
        ),
        labelColor: scheme.onPrimaryContainer,
        unselectedLabelColor: scheme.onSurfaceVariant,
        tabs: [
          for (final tab in tabs)
            Tab(
              child: _TournamentTabLabel(
                icon: tab.icon,
                label: tab.label,
                count: tournaments
                    .where((tournament) => tournament.status == tab.status)
                    .length,
              ),
            ),
        ],
      ),
    );
  }
}

class _TournamentTabLabel extends StatelessWidget {
  const _TournamentTabLabel({
    required this.icon,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 5),
          Text('$count', style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}

class _TournamentStatusList extends StatelessWidget {
  const _TournamentStatusList({
    required this.repository,
    required this.tournaments,
    required this.onRefresh,
  });

  final LeagueRepository repository;
  final List<Tournament> tournaments;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final sortedTournaments = tournaments.toList()
      ..sort((a, b) {
        if (a.status == TournamentStatus.upcoming &&
            b.status == TournamentStatus.upcoming) {
          final aDate = a.startsAt;
          final bDate = b.startsAt;
          if (aDate != null && bDate != null) {
            final byDate = aDate.compareTo(bDate);
            if (byDate != 0) {
              return byDate;
            }
          } else if (aDate != null) {
            return -1;
          } else if (bDate != null) {
            return 1;
          }
        }
        return b.id.compareTo(a.id);
      });

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        children: [
          for (final tournament in sortedTournaments) ...[
            _TournamentCard(repository: repository, tournament: tournament),
            const SizedBox(height: 9),
          ],
          if (sortedTournaments.isEmpty)
            const _EmptyState(
              icon: Icons.search_off,
              title: 'Ничего не найдено',
              text: 'Проверьте город, поиск или соседний таб.',
            ),
        ],
      ),
    );
  }
}

class _CityPickerSheet extends StatefulWidget {
  const _CityPickerSheet({
    required this.initialCity,
    required this.suggestionsFor,
  });

  final String initialCity;
  final List<String> Function(String query) suggestionsFor;

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  late final TextEditingController controller;
  late String query;

  @override
  void initState() {
    super.initState();
    query = widget.initialCity;
    controller = TextEditingController(text: widget.initialCity);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = widget.suggestionsFor(query);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Город',
              prefixIcon: Icon(Icons.place_outlined),
            ),
            textInputAction: TextInputAction.done,
            onChanged: (value) => setState(() => query = value),
            onSubmitted: (value) {
              final city = _cityFromSubmit(value, suggestions);
              if (city != null) {
                Navigator.of(context).pop(city);
              }
            },
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: suggestions.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final city = suggestions[index];
                return ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(city),
                  onTap: () => Navigator.of(context).pop(city),
                );
              },
            ),
          ),
          if (suggestions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: _EmptyState(
                icon: Icons.place_outlined,
                title: 'Город не найден',
                text: 'Поиск идет только по городам из турниров.',
              ),
            ),
        ],
      ),
    );
  }

  String? _cityFromSubmit(String value, List<String> suggestions) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    for (final city in suggestions) {
      if (city.toLowerCase() == normalized) {
        return city;
      }
    }
    return suggestions.length == 1 ? suggestions.first : null;
  }
}

class _DisciplinePickerSheet extends StatelessWidget {
  const _DisciplinePickerSheet({required this.selectedDiscipline});

  final DisciplineFilter selectedDiscipline;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(
          'Дисциплина',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        for (final discipline in DisciplineFilter.values)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(discipline.label),
            trailing: selectedDiscipline == discipline
                ? const Icon(Icons.check)
                : null,
            onTap: () => Navigator.of(context).pop(discipline),
          ),
      ],
    );
  }
}

class _LlbLoginSuccess {
  const _LlbLoginSuccess({required this.username, this.playerId});

  final String username;
  final String? playerId;
}

class _LlbLoginDialog extends StatefulWidget {
  const _LlbLoginDialog();

  @override
  State<_LlbLoginDialog> createState() => _LlbLoginDialogState();
}

class _LlbLoginDialogState extends State<_LlbLoginDialog> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  bool loading = false;
  bool obscurePassword = true;
  String? error;

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    final username = usernameController.text.trim();
    final password = passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => error = 'Введите логин и пароль LLB.');
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    final client = LlbWebAuthClient();
    try {
      final result = await client.login(username: username, password: password);
      if (!result.ok) {
        setState(() => error = 'LLB не принял логин или пароль.');
        return;
      }

      await client.saveVerifiedCredentialsToServer(
        username: username,
        password: password,
      );
      await secureStorage.write(
        key: _LeagueHomePageState._llbUsernameKey,
        value: username,
      );
      await secureStorage.write(
        key: _LeagueHomePageState._llbCookiesKey,
        value: client.encodedCookies,
      );
      final playerId = await client.currentPlayerId(username: username);
      if (playerId != null && playerId.isNotEmpty) {
        await secureStorage.write(
          key: _LeagueHomePageState._llbPlayerIdKey,
          value: playerId,
        );
      }

      if (!mounted) {
        return;
      }
      Navigator.of(
        context,
      ).pop(_LlbLoginSuccess(username: username, playerId: playerId));
    } catch (exception) {
      if (!mounted) {
        return;
      }
      setState(() => error = 'Не удалось сохранить вход: $exception');
    } finally {
      client.close();
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Авторизация LLB'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: usernameController,
              enabled: !loading,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Логин',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              enabled: !loading,
              obscureText: obscurePassword,
              onSubmitted: (_) => loading ? null : login(),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Пароль',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: obscurePassword ? 'Показать' : 'Скрыть',
                  onPressed: loading
                      ? null
                      : () =>
                            setState(() => obscurePassword = !obscurePassword),
                  icon: Icon(
                    obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: loading ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          onPressed: loading ? null : login,
          icon: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.login),
          label: const Text('Войти'),
        ),
      ],
    );
  }
}

class _SettingsDrawer extends StatelessWidget {
  const _SettingsDrawer({
    required this.repository,
    required this.selectedCity,
    required this.selectedDiscipline,
    required this.llbUsername,
    required this.llbPlayerId,
    required this.llbSessionValid,
    required this.citySuggestions,
    required this.onCitySelected,
    required this.onDisciplineSelected,
    required this.onLlbLogin,
    required this.onLlbLogout,
  });

  final LeagueRepository repository;
  final String selectedCity;
  final DisciplineFilter selectedDiscipline;
  final String? llbUsername;
  final String? llbPlayerId;
  final bool llbSessionValid;
  final List<String> Function(String query) citySuggestions;
  final ValueChanged<String> onCitySelected;
  final ValueChanged<DisciplineFilter> onDisciplineSelected;
  final VoidCallback onLlbLogin;
  final VoidCallback onLlbLogout;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  Text(
                    'Меню',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                llbSessionValid
                                    ? Icons.verified_user_outlined
                                    : Icons.login,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Аккаунт LLB',
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            llbUsername == null
                                ? 'Войдите, чтобы связать приложение с LLB.'
                                : llbSessionValid
                                ? 'Вход выполнен: $llbUsername'
                                : 'Сессия сохранена, но требует повторного входа.',
                          ),
                          if (llbUsername == null || !llbSessionValid) ...[
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                onLlbLogin();
                              },
                              icon: const Icon(Icons.login),
                              label: const Text('Авторизоваться'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (llbUsername != null) ...[
                    const SizedBox(height: 10),
                    _DrawerProfileSection(
                      repository: repository,
                      username: llbUsername!,
                      playerId: llbPlayerId,
                    ),
                  ],
                  const SizedBox(height: 18),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('Настройки'),
                    subtitle: Text(
                      '$selectedCity · ${selectedDiscipline.label}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => _DefaultSettingsPage(
                            selectedCity: selectedCity,
                            selectedDiscipline: selectedDiscipline,
                            citySuggestions: citySuggestions,
                            onCitySelected: onCitySelected,
                            onDisciplineSelected: onDisciplineSelected,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            if (llbUsername != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onLlbLogout();
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Выйти'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InitialLoadingView extends StatelessWidget {
  const _InitialLoadingView();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_bar_outlined, size: 44, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              'Загружаем данные ЛЛБ',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Игроки, турниры и рейтинги появятся через пару секунд.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            const SizedBox(
              width: 180,
              child: LinearProgressIndicator(minHeight: 3),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerProfileSection extends StatefulWidget {
  const _DrawerProfileSection({
    required this.repository,
    required this.username,
    required this.playerId,
  });

  final LeagueRepository repository;
  final String username;
  final String? playerId;

  @override
  State<_DrawerProfileSection> createState() => _DrawerProfileSectionState();
}

class _DrawerProfileSectionState extends State<_DrawerProfileSection> {
  Player? player;
  bool loading = false;
  String? loadedId;

  @override
  void initState() {
    super.initState();
    loadPlayer();
  }

  @override
  void didUpdateWidget(covariant _DrawerProfileSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playerId != widget.playerId ||
        oldWidget.repository != widget.repository) {
      loadPlayer();
    }
  }

  Future<void> loadPlayer() async {
    final id = widget.playerId?.trim();
    if (id == null || id.isEmpty) {
      setState(() {
        player = null;
        loadedId = null;
        loading = false;
      });
      return;
    }
    setState(() {
      loading = true;
      loadedId = id;
    });
    Player? loadedPlayer;
    try {
      loadedPlayer = await widget.repository.playerById(id);
    } catch (_) {
      loadedPlayer = null;
    }
    if (!mounted || loadedId != id) {
      return;
    }
    setState(() {
      player = loadedPlayer;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (player != null) {
      return _DrawerProfileCard(player: player!);
    }
    return _DrawerProfilePlaceholder(
      username: widget.username,
      playerId: widget.playerId,
      loading: loading,
    );
  }
}

class _DrawerProfileCard extends StatelessWidget {
  const _DrawerProfileCard({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    final tournaments = _tournamentsCount(player);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                _PlayerThumbnail(player: player),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        player.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      if (player.city.isNotEmpty)
                        Text(
                          player.city,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DenseFact(label: 'ЭЛО', value: player.bestEloLabel),
                ),
                Expanded(
                  child: _DenseFact(
                    label: 'Турниры',
                    value: tournaments == null ? '-' : '$tournaments',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int? _tournamentsCount(Player player) {
    final values = player.ratings
        .map((rating) => rating.compsTotal)
        .whereType<int>()
        .toList();
    if (values.isEmpty) {
      return null;
    }
    values.sort();
    return values.last;
  }
}

class _DrawerProfilePlaceholder extends StatelessWidget {
  const _DrawerProfilePlaceholder({
    required this.username,
    required this.playerId,
    required this.loading,
  });

  final String username;
  final String? playerId;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.person_outline),
        title: Text(username),
        subtitle: Text(
          loading
              ? 'Ищем профиль LLB...'
              : playerId == null || playerId!.isEmpty
              ? 'Профиль игрока пока не найден в базе.'
              : 'Профиль LLB не найден в базе: $playerId',
        ),
      ),
    );
  }
}

class _DefaultSettingsPage extends StatefulWidget {
  const _DefaultSettingsPage({
    required this.selectedCity,
    required this.selectedDiscipline,
    required this.citySuggestions,
    required this.onCitySelected,
    required this.onDisciplineSelected,
  });

  final String selectedCity;
  final DisciplineFilter selectedDiscipline;
  final List<String> Function(String query) citySuggestions;
  final ValueChanged<String> onCitySelected;
  final ValueChanged<DisciplineFilter> onDisciplineSelected;

  @override
  State<_DefaultSettingsPage> createState() => _DefaultSettingsPageState();
}

class _DefaultSettingsPageState extends State<_DefaultSettingsPage> {
  late String selectedCity = widget.selectedCity;
  late DisciplineFilter selectedDiscipline = widget.selectedDiscipline;

  Future<void> pickCity() async {
    final city = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _CityPickerSheet(
        initialCity: selectedCity,
        suggestionsFor: widget.citySuggestions,
      ),
    );
    if (city == null) {
      return;
    }
    widget.onCitySelected(city);
    if (mounted) {
      setState(() => selectedCity = city);
    }
  }

  Future<void> pickDiscipline() async {
    final discipline = await showModalBottomSheet<DisciplineFilter>(
      context: context,
      useSafeArea: true,
      builder: (context) =>
          _DisciplinePickerSheet(selectedDiscipline: selectedDiscipline),
    );
    if (discipline == null) {
      return;
    }
    widget.onDisciplineSelected(discipline);
    if (mounted) {
      setState(() => selectedDiscipline = discipline);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: const Text('Город по умолчанию'),
                  subtitle: Text(selectedCity),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: pickCity,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.sports_outlined),
                  title: const Text('Дисциплина по умолчанию'),
                  subtitle: Text(selectedDiscipline.label),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: pickDiscipline,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TournamentCard extends StatelessWidget {
  const _TournamentCard({required this.repository, required this.tournament});

  final LeagueRepository repository;
  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final spots = tournament.capacity == null
        ? '${tournament.playersCount}'
        : '${tournament.playersCount} / ${tournament.capacity}';

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TournamentDetailsPage(
                repository: repository,
                tournament: tournament,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      tournament.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _StatusBadge(status: tournament.status),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(icon: Icons.place_outlined, label: tournament.city),
                  _InfoChip(
                    icon: Icons.pool_outlined,
                    label: tournament.discipline,
                  ),
                  _InfoChip(icon: Icons.store_outlined, label: tournament.club),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _DenseFact(
                      label: 'Дата',
                      value: tournament.dateLabel,
                    ),
                  ),
                  Expanded(
                    child: _DenseFact(label: 'Участники', value: spots),
                  ),
                  if (tournament.status != TournamentStatus.upcoming)
                    Expanded(
                      child: _DenseFact(
                        label: 'Матчи',
                        value: '${tournament.matchesCount}',
                      ),
                    )
                  else
                    const Spacer(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TournamentDetailsPage extends StatefulWidget {
  const TournamentDetailsPage({
    super.key,
    required this.repository,
    required this.tournament,
  });

  final LeagueRepository repository;
  final Tournament tournament;

  @override
  State<TournamentDetailsPage> createState() => _TournamentDetailsPageState();
}

class _TournamentDetailsPageState extends State<TournamentDetailsPage> {
  static const _registrationStatePrefix = 'llb_tournament_registration_';

  late Tournament tournament = widget.tournament;
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  bool loading = true;
  bool registrationLoading = false;
  bool llbSessionValid = false;
  String? llbUsername;
  String? llbPlayerId;
  String? registrationState;
  String? registrationMessage;
  String? error;

  @override
  void initState() {
    super.initState();
    loadDetails();
    loadRegistrationSession();
  }

  Future<void> loadDetails() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final details = await widget.repository.tournamentDetails(
        widget.tournament,
      );
      if (mounted) {
        setState(() => tournament = details);
      }
    } catch (exception) {
      if (mounted) {
        setState(() => error = '$exception');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> loadRegistrationSession() async {
    final username = await secureStorage.read(
      key: _LeagueHomePageState._llbUsernameKey,
    );
    var playerId = await secureStorage.read(
      key: _LeagueHomePageState._llbPlayerIdKey,
    );
    final cookies = await secureStorage.read(
      key: _LeagueHomePageState._llbCookiesKey,
    );
    final savedState = await secureStorage.read(
      key: '$_registrationStatePrefix${widget.tournament.id}',
    );
    if (username == null || cookies == null || cookies.isEmpty) {
      if (mounted) {
        setState(() {
          llbUsername = null;
          llbPlayerId = null;
          llbSessionValid = false;
          registrationState = savedState;
        });
      }
      return;
    }

    final client = LlbWebAuthClient();
    client.loadEncodedCookies(cookies);
    try {
      final valid = await client.sessionValid();
      if (valid && (playerId == null || playerId.isEmpty)) {
        playerId = await client.currentPlayerId(username: username);
        if (playerId != null && playerId.isNotEmpty) {
          await secureStorage.write(
            key: _LeagueHomePageState._llbPlayerIdKey,
            value: playerId,
          );
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        llbUsername = username;
        llbPlayerId = playerId;
        llbSessionValid = valid;
        registrationState = savedState;
      });
    } finally {
      client.close();
    }
  }

  Future<void> showLoginDialog() async {
    final result = await showDialog<_LlbLoginSuccess>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _LlbLoginDialog(),
    );
    if (result != null) {
      await loadRegistrationSession();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Вход выполнен: ${result.username}')),
        );
      }
    }
  }

  Future<void> submitRegistrationAction(String action) async {
    final cookies = await secureStorage.read(
      key: _LeagueHomePageState._llbCookiesKey,
    );
    if (cookies == null || cookies.isEmpty) {
      await showLoginDialog();
      return;
    }

    setState(() {
      registrationLoading = true;
      registrationMessage = null;
    });

    final client = LlbWebAuthClient();
    client.loadEncodedCookies(cookies);
    try {
      final result = await client.directTournamentRegistrationAction(
        tournamentId: tournament.id,
        action: action,
      );
      if (!result.ok) {
        setState(() => registrationMessage = result.message);
        return;
      }

      final nextState = action == 'unregister'
          ? 'not_registered'
          : 'registered';
      await secureStorage.write(
        key: '$_registrationStatePrefix${tournament.id}',
        value: nextState,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        llbSessionValid = true;
        registrationState = nextState;
        registrationMessage = result.message;
      });
      await loadDetails();
    } catch (exception) {
      if (mounted) {
        setState(() => registrationMessage = 'Ошибка LLB: $exception');
      }
    } finally {
      client.close();
      if (mounted) {
        setState(() => registrationLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveRegistrationState = _effectiveRegistrationState();
    final participantsKnown =
        tournament.players.isNotEmpty || tournament.playersCount == 0;
    final loadedParticipants = tournament.players.length;
    final participantsLabel = loadedParticipants > 0
        ? tournament.playersCount > loadedParticipants
              ? '$loadedParticipants из ${tournament.playersCount}'
              : '$loadedParticipants'
        : tournament.playersCount > 0
        ? '${tournament.playersCount}'
        : '0';

    return Scaffold(
      appBar: AppBar(title: const Text('Турнир')),
      body: RefreshIndicator(
        onRefresh: loadDetails,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              tournament.title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            if (loading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              MaterialBanner(
                leading: const Icon(Icons.cloud_off_outlined),
                content: const Text('Не удалось загрузить участников и матчи.'),
                actions: [
                  TextButton(
                    onPressed: loadDetails,
                    child: const Text('Еще раз'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusBadge(status: tournament.status),
                _InfoChip(icon: Icons.place_outlined, label: tournament.city),
                _InfoChip(
                  icon: Icons.pool_outlined,
                  label: tournament.discipline,
                ),
                _InfoChip(icon: Icons.store_outlined, label: tournament.club),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    _DetailRow(label: 'Дата', value: tournament.dateLabel),
                    _DetailRow(
                      label: 'Участники',
                      value: tournament.capacity == null
                          ? participantsLabel
                          : '$participantsLabel / ${tournament.capacity}',
                    ),
                    _DetailRow(
                      label: 'Сетка',
                      value: 'Открыть',
                      onTap: () => openBracket(context),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _TournamentRegistrationCard(
              tournament: tournament,
              username: llbUsername,
              playerId: llbPlayerId,
              sessionValid: llbSessionValid,
              state: effectiveRegistrationState,
              participantsKnown: participantsKnown,
              loading: registrationLoading,
              message: registrationMessage,
              onLogin: showLoginDialog,
              onRegister: () => submitRegistrationAction('register'),
              onUnregister: () => submitRegistrationAction('unregister'),
            ),
            const SizedBox(height: 12),
            Text(
              'Участники',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            for (final player in tournament.players)
              _PlayerTile(
                repository: widget.repository,
                player: player,
                showMeta: true,
              ),
            if (!loading && tournament.players.isEmpty)
              _EmptyState(
                icon: Icons.groups_outlined,
                title: tournament.playersCount > 0
                    ? 'Список участников не загружен'
                    : 'Участников пока нет',
                text: tournament.playersCount > 0
                    ? 'На странице турнира указано участников: ${tournament.playersCount}.'
                    : 'Для этого турнира еще нет списка участников.',
              ),
            if (tournament.status != TournamentStatus.upcoming) ...[
              const SizedBox(height: 12),
              Text(
                'Матчи',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              for (final match in tournament.matches) _MatchTile(match: match),
              if (!loading && tournament.matches.isEmpty)
                const _EmptyState(
                  icon: Icons.sports_score_outlined,
                  title: 'Матчей пока нет',
                  text: 'Для этого турнира еще нет списка встреч.',
                ),
            ],
          ],
        ),
      ),
    );
  }

  String? _effectiveRegistrationState() {
    if (registrationState == 'registered' ||
        registrationState == 'not_registered') {
      return registrationState;
    }
    final id = llbPlayerId?.trim();
    if (id == null || id.isEmpty) {
      return null;
    }
    if (tournament.players.any((player) => player.id == id)) {
      return 'registered';
    }
    if (tournament.players.isNotEmpty || tournament.playersCount == 0) {
      return 'not_registered';
    }
    return null;
  }

  void openBracket(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _BracketWebViewPage(
          title: tournament.title,
          url: tournament.bracketUrl,
        ),
      ),
    );
  }
}

class _TournamentRegistrationCard extends StatelessWidget {
  const _TournamentRegistrationCard({
    required this.tournament,
    required this.username,
    required this.playerId,
    required this.sessionValid,
    required this.state,
    required this.participantsKnown,
    required this.loading,
    required this.message,
    required this.onLogin,
    required this.onRegister,
    required this.onUnregister,
  });

  final Tournament tournament;
  final String? username;
  final String? playerId;
  final bool sessionValid;
  final String? state;
  final bool participantsKnown;
  final bool loading;
  final String? message;
  final VoidCallback onLogin;
  final VoidCallback onRegister;
  final VoidCallback onUnregister;

  @override
  Widget build(BuildContext context) {
    final canRegister = tournament.status == TournamentStatus.upcoming;
    if (!canRegister) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Запись доступна только для предстоящих турниров.'),
              ),
            ],
          ),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final isRegistered = state == 'registered';
    final known = state == 'registered' || state == 'not_registered';
    final stateText = username == null
        ? 'Войдите в LLB, чтобы записаться на турнир.'
        : isRegistered
        ? 'Вы записаны на этот турнир.'
        : state == 'not_registered'
        ? 'Вы не записаны на этот турнир.'
        : playerId == null || playerId!.isEmpty
        ? 'Не удалось определить ваш профиль LLB.'
        : participantsKnown
        ? 'Вы не записаны на этот турнир.'
        : 'Список участников пока не загружен, статус уточняется.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isRegistered
                      ? Icons.how_to_reg_outlined
                      : Icons.app_registration_outlined,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Запись на турнир',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(stateText),
            if (username != null) ...[
              const SizedBox(height: 4),
              Text(
                sessionValid
                    ? 'Аккаунт: $username${playerId == null || playerId!.isEmpty ? '' : ' · id $playerId'}'
                    : 'Сессия LLB истекла.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: TextStyle(
                  color: message!.toLowerCase().contains('ошибка')
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (username == null || !sessionValid)
              FilledButton.icon(
                onPressed: loading ? null : onLogin,
                icon: const Icon(Icons.login),
                label: const Text('Войти в LLB'),
              )
            else if (known || participantsKnown)
              isRegistered
                  ? OutlinedButton.icon(
                      onPressed: loading ? null : onUnregister,
                      icon: loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.person_remove_outlined),
                      label: const Text('Отменить запись'),
                    )
                  : FilledButton.icon(
                      onPressed: loading ? null : onRegister,
                      icon: loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.how_to_reg),
                      label: const Text('Записаться'),
                    ),
          ],
        ),
      ),
    );
  }
}

class _PlayersPage extends StatefulWidget {
  const _PlayersPage({
    required this.repository,
    required this.search,
    required this.selectedCity,
    required this.selectedDiscipline,
    required this.sort,
    required this.sortAscending,
    required this.onSortChanged,
    required this.onRefresh,
  });

  final LeagueRepository repository;
  final String search;
  final String selectedCity;
  final DisciplineFilter selectedDiscipline;
  final PlayerSort sort;
  final bool sortAscending;
  final ValueChanged<PlayerSort> onSortChanged;
  final Future<void> Function() onRefresh;

  @override
  State<_PlayersPage> createState() => _PlayersPageState();
}

class _PlayersPageState extends State<_PlayersPage> {
  Timer? searchDebounce;
  List<Player>? searchedPlayers;
  bool searching = false;
  String? searchError;

  @override
  void initState() {
    super.initState();
    scheduleSearch(immediate: true);
  }

  @override
  void didUpdateWidget(covariant _PlayersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.search != widget.search ||
        oldWidget.selectedCity != widget.selectedCity ||
        oldWidget.selectedDiscipline != widget.selectedDiscipline) {
      scheduleSearch();
    }
  }

  @override
  void dispose() {
    searchDebounce?.cancel();
    super.dispose();
  }

  void scheduleSearch({bool immediate = false}) {
    searchDebounce?.cancel();
    final query = widget.search.trim();
    if (query.length < 2) {
      setState(() {
        searchedPlayers = null;
        searching = false;
        searchError = null;
      });
      return;
    }
    searchDebounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 350),
      () => runSearch(query),
    );
  }

  Future<void> runSearch(String query) async {
    setState(() {
      searching = true;
      searchError = null;
    });
    try {
      final results = await widget.repository.searchPlayers(
        query,
        discipline: widget.selectedDiscipline,
      );
      if (!mounted || widget.search.trim() != query) {
        return;
      }
      setState(
        () => searchedPlayers = results
            .where((player) => player.matchesNameQuery(query))
            .where(_matchesSelectedCity)
            .toList(),
      );
    } catch (error) {
      if (mounted) {
        setState(() => searchError = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => searching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final players =
        (searchedPlayers ??
                widget.repository
                    .players()
                    .where(
                      (player) =>
                          player.matchesDiscipline(widget.selectedDiscipline),
                    )
                    .where(_matchesSelectedCity)
                    .where((player) => player.matchesQuery(widget.search)))
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
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (searching) const LinearProgressIndicator(minHeight: 2),
          if (searchError != null)
            MaterialBanner(
              leading: const Icon(Icons.cloud_off_outlined),
              content: const Text('Не удалось выполнить поиск игроков.'),
              actions: [
                TextButton(
                  onPressed: () => runSearch(widget.search.trim()),
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
            ),
          if (players.isEmpty)
            const _EmptyState(
              icon: Icons.person_search,
              title: 'Игрок не найден',
              text: 'Поиск на этом экране идет только по имени игрока.',
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
  });

  final LeagueRepository repository;
  final Player player;
  final bool showMeta;

  @override
  Widget build(BuildContext context) {
    final participantSummary = player.participantSummary;
    final meta = [
      if (player.city.isNotEmpty) player.city,
      if (player.club.isNotEmpty) player.club,
      if (player.discipline.isNotEmpty) player.discipline,
      if (participantSummary.isNotEmpty) participantSummary,
    ].join(' · ');
    final canOpenProfile = player.hasRealLlbId;

    return Card(
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
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _PlayerThumbnail(player: player),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      player.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (showMeta && meta.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        meta,
                        maxLines: 3,
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
              const SizedBox(width: 8),
              _PlayerMetricColumns(player: player),
            ],
          ),
        ),
      ),
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
        width: 44,
        height: 44,
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
      width: 148,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _PlayerMetricCell(label: 'РБ', value: player.russianBilliardsElo),
          const SizedBox(width: 6),
          _PlayerMetricCell(label: 'Пул', value: player.poolElo),
          const SizedBox(width: 6),
          _PlayerMetricCell(label: 'Турн.', value: player.tournamentsCount),
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
    final text = value == null || value! <= 0 ? '-' : '$value';

    return SizedBox(
      width: 44,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          Text(
            label,
            maxLines: 1,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class PlayerDetailsPage extends StatefulWidget {
  const PlayerDetailsPage({
    super.key,
    required this.repository,
    required this.player,
  });

  final LeagueRepository repository;
  final Player player;

  @override
  State<PlayerDetailsPage> createState() => _PlayerDetailsPageState();
}

class _PlayerDetailsPageState extends State<PlayerDetailsPage> {
  late Player player = widget.player;
  bool loading = false;
  String? error;
  bool sortEntriesByPlace = false;

  @override
  void initState() {
    super.initState();
    loadPlayer();
  }

  Future<void> loadPlayer() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final loaded = await widget.repository.playerById(widget.player.id);
      if (!mounted) return;
      setState(() {
        if (loaded != null) {
          player = loaded;
        }
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() => error = '$exception');
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ratings = player.ratings;
    final entries = _sortedTournamentEntries();

    return Scaffold(
      appBar: AppBar(title: const Text('Игрок')),
      body: RefreshIndicator(
        onRefresh: loadPlayer,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Не удалось обновить игрока',
                  text: error!,
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 76,
                        height: 76,
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: player.avatarUrl.isEmpty
                            ? Center(
                                child: Text(
                                  player.initials,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              )
                            : Image.network(
                                player.avatarUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Center(
                                  child: Text(
                                    player.initials,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            player.name,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _InfoChip(
                                icon: Icons.badge_outlined,
                                label: 'LLB ID ${player.id}',
                              ),
                              if (player.city.isNotEmpty)
                                _InfoChip(
                                  icon: Icons.place_outlined,
                                  label: player.city,
                                ),
                              if (player.club.isNotEmpty)
                                _InfoChip(
                                  icon: Icons.public,
                                  label: player.club,
                                ),
                              if (player.discipline.isNotEmpty)
                                _InfoChip(
                                  icon: Icons.pool_outlined,
                                  label: player.discipline,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: _DenseFact(
                        label: 'Лучший ЭЛО',
                        value: player.bestEloLabel,
                      ),
                    ),
                    Expanded(
                      child: _DenseFact(
                        label: 'Участий',
                        value:
                            player.stats.total?.toString() ??
                            '${player.tournamentEntries.length}',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (!player.stats.isEmpty) ...[
              _PlayerStatsCard(stats: player.stats),
              const SizedBox(height: 12),
            ],
            if (player.hasContacts) ...[
              _PlayerContactsCard(player: player),
              const SizedBox(height: 12),
            ],
            Text(
              'ЭЛО по дисциплинам',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            if (ratings.isEmpty)
              const _EmptyState(
                icon: Icons.leaderboard_outlined,
                title: 'ЭЛО не найден',
                text: 'В карточке игрока нет рейтинговых строк.',
              )
            else
              for (final rating in ratings) _PlayerRatingCard(rating: rating),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'История участий',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.schedule_outlined),
                      label: Text('Дата'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.emoji_events_outlined),
                      label: Text('Место'),
                    ),
                  ],
                  selected: {sortEntriesByPlace},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) {
                    setState(() => sortEntriesByPlace = value.first);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              const _EmptyState(
                icon: Icons.emoji_events_outlined,
                title: 'История участий не загружена',
                text: 'Этот список берется с персональной страницы LLB игрока.',
              )
            else
              for (final entry in entries.take(40))
                _PlayerTournamentEntryTile(
                  repository: widget.repository,
                  entry: entry,
                ),
            if (entries.length > 40)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Показаны первые 40 из ${entries.length}.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<PlayerTournamentEntry> _sortedTournamentEntries() {
    final entries = player.tournamentEntries.toList();
    if (!sortEntriesByPlace) {
      return entries;
    }
    entries.sort((a, b) {
      final placeCompare = _placeSortValue(
        a.place,
      ).compareTo(_placeSortValue(b.place));
      if (placeCompare != 0) {
        return placeCompare;
      }
      return a.title.compareTo(b.title);
    });
    return entries;
  }

  int _placeSortValue(String value) {
    final match = RegExp(r'\d+').firstMatch(value);
    if (match == null) {
      return 999999;
    }
    return int.tryParse(match.group(0) ?? '') ?? 999999;
  }
}

class _PlayerStatsCard extends StatelessWidget {
  const _PlayerStatsCard({required this.stats});

  final PlayerStats stats;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Статистика LLB',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DenseFact(
                    label: 'Турниров',
                    value: stats.total?.toString() ?? '-',
                  ),
                ),
                Expanded(
                  child: _DenseFact(
                    label: 'Пирамида',
                    value: stats.pyramid?.toString() ?? '-',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _DenseFact(
                    label: 'Пул',
                    value: stats.pool?.toString() ?? '-',
                  ),
                ),
                Expanded(
                  child: _DenseFact(
                    label: 'Снукер',
                    value: stats.snooker?.toString() ?? '-',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerContactsCard extends StatelessWidget {
  const _PlayerContactsCard({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    final items = _dedupeContactItems([
      if (player.phone.isNotEmpty)
        _ContactItem(Icons.phone_outlined, 'Телефон', player.phone),
      if (player.whatsapp.isNotEmpty)
        _ContactItem(Icons.chat_outlined, 'WhatsApp', player.whatsapp),
      if (player.telegram.isNotEmpty)
        _ContactItem(Icons.send_outlined, 'Telegram', player.telegram),
      if (player.email.isNotEmpty)
        _ContactItem(Icons.mail_outline, 'Email', player.email),
    ]);
    final raw = player.contactsRaw.trim();
    final shouldShowRaw =
        raw.isNotEmpty &&
        !items.any((item) => _sameContactValue(raw, item.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Контакты',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            for (final item in items) _ContactRow(item: item),
            if (shouldShowRaw)
              _ContactRow(
                item: _ContactItem(
                  Icons.notes_outlined,
                  'Дополнительно',
                  player.contactsRaw,
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<_ContactItem> _dedupeContactItems(List<_ContactItem> items) {
    final result = <_ContactItem>[];
    for (final item in items) {
      if (result.any(
        (existing) => _sameContactValue(existing.value, item.value),
      )) {
        continue;
      }
      result.add(item);
    }
    return result;
  }

  bool _sameContactValue(String left, String right) {
    final leftText = left.trim().toLowerCase();
    final rightText = right.trim().toLowerCase();
    if (leftText.isEmpty || rightText.isEmpty) {
      return false;
    }
    if (leftText == rightText) {
      return true;
    }
    final leftDigits = leftText.replaceAll(RegExp(r'\D'), '');
    final rightDigits = rightText.replaceAll(RegExp(r'\D'), '');
    return leftDigits.length >= 7 &&
        rightDigits.length >= 7 &&
        leftDigits == rightDigits;
  }
}

class _ContactItem {
  const _ContactItem(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.item});

  final _ContactItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            item.icon,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 84,
            child: Text(
              item.label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              item.value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerTournamentEntryTile extends StatelessWidget {
  const _PlayerTournamentEntryTile({
    required this.repository,
    required this.entry,
  });

  final LeagueRepository repository;
  final PlayerTournamentEntry entry;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (entry.dateLabel.isNotEmpty) entry.dateLabel,
      if (entry.place.isNotEmpty) 'место: ${entry.place}',
      if (entry.points.isNotEmpty) 'очки: ${entry.points}',
    ].join(' · ');

    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: entry.tournamentId.isEmpty
            ? null
            : () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TournamentDetailsPage(
                      repository: repository,
                      tournament: _tournamentFromEntry(entry),
                    ),
                  ),
                );
              },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      entry.place.isEmpty ? '-' : entry.place,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    Text(
                      'место',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(subtitle),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Tournament _tournamentFromEntry(PlayerTournamentEntry entry) {
    return Tournament(
      id: entry.tournamentId,
      title: entry.title,
      city: _cityFromEntryTitle(entry.title),
      club: '',
      discipline: _disciplineFromEntryTitle(entry.title),
      level: '',
      dateLabel: entry.dateLabel,
      playersCount: 0,
      capacity: null,
      matchesCount: 0,
      status: TournamentStatus.finished,
      bracketUrl: 'https://www.llb.su/t/${entry.tournamentId}',
      players: const [],
      matches: const [],
    );
  }

  String _cityFromEntryTitle(String title) {
    final parts = title
        .split('.')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '';
    }
    final first = parts.first;
    if (first.toLowerCase().startsWith('ллб') && parts.length > 1) {
      return parts[1];
    }
    return first.replaceAll(RegExp(r'\s+20\d\d$'), '').trim();
  }

  String _disciplineFromEntryTitle(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('снукер')) return 'Снукер';
    if (lower.contains('пул')) return 'Пул';
    if (lower.contains('пирами')) return 'Пирамида';
    return 'Бильярд';
  }
}

class _PlayerRatingCard extends StatelessWidget {
  const _PlayerRatingCard({required this.rating});

  final PlayerRating rating;

  @override
  Widget build(BuildContext context) {
    final compsText = [
      if (rating.compsYear != null) 'год: ${rating.compsYear}',
      if (rating.compsTotal != null) 'всего: ${rating.compsTotal}',
    ].join(' · ');

    return Card(
      child: ListTile(
        leading: const Icon(Icons.leaderboard_outlined),
        title: Text(rating.discipline),
        subtitle: compsText.isEmpty ? Text(rating.label) : Text(compsText),
        trailing: Text(
          rating.elo > 0 ? '${rating.elo}' : 'нет',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.match});

  final MatchInfo match;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text('${match.playerA} — ${match.playerB}'),
        subtitle: Text(match.round),
        trailing: Text(
          match.score ?? match.state,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final TournamentStatus status;

  @override
  Widget build(BuildContext context) {
    final (text, color, icon) = switch (status) {
      TournamentStatus.live => (
        'идет',
        const Color(0xff2a9d8f),
        Icons.play_arrow,
      ),
      TournamentStatus.upcoming => (
        'скоро',
        const Color(0xff33658a),
        Icons.schedule,
      ),
      TournamentStatus.finished => (
        'итоги',
        const Color(0xff7d7c84),
        Icons.flag,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide.none,
      backgroundColor: const Color(0xffeef0e8),
    );
  }
}

class _DenseFact extends StatelessWidget {
  const _DenseFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: const Color(0xff4c564f),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(child: Text(value)),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            const Icon(Icons.open_in_new, size: 18),
          ],
        ],
      ),
    );
    if (onTap == null) {
      return row;
    }
    return InkWell(onTap: onTap, child: row);
  }
}

class _BracketWebViewPage extends StatefulWidget {
  const _BracketWebViewPage({required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<_BracketWebViewPage> createState() => _BracketWebViewPageState();
}

class _BracketWebViewPageState extends State<_BracketWebViewPage> {
  late final WebViewController controller;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) {
              setState(() => loading = false);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: () {
              setState(() => loading = true);
              controller.reload();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: controller),
          if (loading) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(text, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}
