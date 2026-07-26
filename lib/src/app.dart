import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'app_theme.dart';
import 'llb_auth.dart';
import 'models.dart';
import 'repositories.dart';
import 'tournament_media_section.dart';

part 'app_parts/navigation_and_media.dart';
part 'app_parts/tournaments_home.dart';
part 'app_parts/pickers.dart';
part 'app_parts/clubs_media_misc.dart';
part 'app_parts/auth_drawer_settings.dart';
part 'app_parts/tournament_details.dart';
part 'app_parts/players.dart';
part 'app_parts/player_details_common.dart';

class LlbApp extends StatelessWidget {
  const LlbApp({super.key, this.repository});

  final LeagueRepository? repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LLB',
      builder: LlbAppTheme.mediaQueryBuilder,
      theme: LlbAppTheme.light(),
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
  static const _clubMapProviderKey = 'club_map_provider';
  static const _llbUsernameKey = 'llb_username';
  static const _llbCookiesKey = 'llb_cookies';
  static const _llbPlayerIdKey = 'llb_player_id';
  static const _appUserIdKey = 'app_user_id';
  static const _appUsernameKey = 'app_username';
  static const _appDisplayNameKey = 'app_display_name';
  static const _appCityKey = 'app_city';
  static const _appTokenKey = 'app_token';
  static const _initialSearch = String.fromEnvironment('LLB_INITIAL_SEARCH');
  static const _initialTournamentId = String.fromEnvironment(
    'LLB_OPEN_TOURNAMENT_ID',
  );
  static const _initialScreen = String.fromEnvironment('LLB_INITIAL_SCREEN');
  static const _initialTab = int.fromEnvironment(
    'LLB_INITIAL_TAB',
    defaultValue: 0,
  );

  final AppLinks appLinks = AppLinks();
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
  ClubMapProvider selectedClubMapProvider = ClubMapProvider.osm;
  List<String> recentCities = const [];
  PlayerSort playerSort = PlayerSort.russianBilliards;
  bool playerSortAscending = false;
  String? llbUsername;
  String? llbPlayerId;
  bool llbSessionValid = false;
  bool loading = true;
  bool initialDataLoaded = false;
  bool initialTournamentOpened = false;
  bool initialScreenOpened = false;
  String? pendingTournamentLinkId;
  StreamSubscription<Uri>? linkSubscription;
  String? loadError;

  @override
  void initState() {
    super.initState();
    setupIncomingLinks();
    loadSavedPreferences();
    loadSavedLlbSession();
    loadLeagueData();
  }

  @override
  void dispose() {
    linkSubscription?.cancel();
    searchController.dispose();
    repository.dispose();
    super.dispose();
  }

  Future<void> setupIncomingLinks() async {
    try {
      final initialLink = await appLinks.getInitialLink();
      if (initialLink != null) {
        unawaited(handleIncomingLink(initialLink));
      }
    } catch (_) {
      // Deep links are an optional entry point; the regular app start must
      // remain quiet if the OS cannot provide the initial link.
    }
    linkSubscription = appLinks.uriLinkStream.listen((uri) {
      unawaited(handleIncomingLink(uri));
    });
  }

  Future<void> handleIncomingLink(Uri uri) async {
    final telegramCode = telegramLinkCodeFromLink(uri);
    if (telegramCode != null) {
      await claimTelegramLink(telegramCode);
      return;
    }
    final id = tournamentIdFromLink(uri);
    if (id == null || id == pendingTournamentLinkId) {
      return;
    }
    pendingTournamentLinkId = id;
    await openTournamentById(id);
  }

  String? tournamentIdFromLink(Uri uri) {
    final candidates = <String?>[
      uri.queryParameters['tournament_id'],
      uri.queryParameters['tournament'],
      uri.queryParameters['id'],
      if (uri.scheme == 'llb' && uri.host == 'tournament')
        uri.pathSegments.firstOrNull,
      if ((uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host == 'llb.panfilius.ru' &&
          uri.pathSegments.length >= 3 &&
          uri.pathSegments[0] == 'open' &&
          uri.pathSegments[1] == 'tournament')
        uri.pathSegments[2],
    ];
    for (final candidate in candidates) {
      final value = candidate?.trim();
      if (value != null && RegExp(r'^\d+$').hasMatch(value)) {
        return value;
      }
    }
    return null;
  }

  String? telegramLinkCodeFromLink(Uri uri) {
    final candidates = <String?>[
      uri.queryParameters['telegram_code'],
      uri.queryParameters['code'],
      if (uri.scheme == 'llb' && uri.host == 'telegram-link')
        uri.pathSegments.firstOrNull,
      if ((uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host == 'llb.panfilius.ru' &&
          uri.pathSegments.length >= 2 &&
          uri.pathSegments[0] == 'open' &&
          uri.pathSegments[1] == 'telegram-link')
        uri.queryParameters['code'],
    ];
    for (final candidate in candidates) {
      final value = candidate?.trim().toUpperCase();
      if (value != null && RegExp(r'^[A-F0-9]{8}$').hasMatch(value)) {
        return value;
      }
    }
    return null;
  }

  Future<void> claimTelegramLink(String code) async {
    var token = await secureStorage.read(key: _appTokenKey);
    if (token == null || token.isEmpty) {
      if (!mounted) {
        return;
      }
      final auth = await showDialog<AppAuthResult>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const _AppAuthDialog(),
      );
      if (auth == null || !mounted) {
        return;
      }
      await saveAppAuth(auth);
      token = auth.token;
    }
    final client = AppAuthClient();
    try {
      final result = await client.claimTelegramLink(code: code, token: token);
      await saveAppAuth(result);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Telegram привязан к аккаунту ${result.displayName.isEmpty ? result.username : result.displayName}',
          ),
        ),
      );
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось привязать Telegram: $exception')),
        );
      }
    } finally {
      client.close();
    }
  }

  Future<void> saveAppAuth(AppAuthResult result) async {
    await secureStorage.write(key: _appUserIdKey, value: result.id);
    await secureStorage.write(key: _appUsernameKey, value: result.username);
    await secureStorage.write(
      key: _appDisplayNameKey,
      value: result.displayName,
    );
    await secureStorage.write(key: _appCityKey, value: result.city);
    await secureStorage.write(key: _appTokenKey, value: result.token);
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
        unawaited(openInitialScreenIfNeeded());
        unawaited(openInitialTournamentIfNeeded());
      }
    }
  }

  Future<void> openInitialScreenIfNeeded() async {
    if (initialScreenOpened) {
      return;
    }
    initialScreenOpened = true;
    switch (_initialScreen.trim().toLowerCase()) {
      case 'clubs':
        if (!mounted) {
          return;
        }
        final clubs = clubSummaries();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ClubsPage(
              repository: repository,
              clubs: clubs,
              initialCity: selectedCity,
              mapProvider: selectedClubMapProvider,
            ),
          ),
        );
        break;
    }
  }

  Future<void> openInitialTournamentIfNeeded() async {
    if (initialTournamentOpened || _initialTournamentId.trim().isEmpty) {
      return;
    }
    initialTournamentOpened = true;
    await openTournamentById(_initialTournamentId.trim());
  }

  Future<void> openTournamentById(String id) async {
    final tournament =
        repository.tournaments().where((item) => item.id == id).firstOrNull ??
        tournamentShell(id);
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

  Tournament tournamentShell(String id) {
    return Tournament(
      id: id,
      title: 'Турнир',
      city: '',
      club: '',
      discipline: '',
      level: '',
      dateLabel: '',
      playersCount: 0,
      capacity: null,
      matchesCount: 0,
      status: TournamentStatus.upcoming,
      bracketUrl: 'https://www.llb.su/t/$id',
      players: const [],
      matches: const [],
    );
  }

  Future<void> loadSavedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCity = _emptyToNull(prefs.getString(_selectedCityKey));
    final savedDiscipline = DisciplineFilter.fromStorage(
      prefs.getString(_disciplineKey),
    );
    final savedClubMapProvider = ClubMapProvider.fromStorage(
      prefs.getString(_clubMapProviderKey),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      selectedCity = savedCity ?? _defaultCity;
      selectedDiscipline = savedDiscipline;
      selectedClubMapProvider = savedClubMapProvider;
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
      if (valid) {
        final freshPlayerId = await client.currentPlayerId(
          username: savedUsername,
        );
        if (freshPlayerId != null && freshPlayerId.isNotEmpty) {
          savedPlayerId = freshPlayerId;
          await secureStorage.write(key: _llbPlayerIdKey, value: freshPlayerId);
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

  Future<void> selectClubMapProvider(ClubMapProvider provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clubMapProviderKey, provider.storageKey);
    if (!mounted) {
      return;
    }
    setState(() => selectedClubMapProvider = provider);
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

  List<ClubSummary> clubSummaries() {
    final byKey = <String, ClubSummary>{};
    final storedKeys = <String>{};
    for (final club in repository.clubs()) {
      final name = club.name.trim();
      final city = club.city.trim();
      if (name.isEmpty || city.isEmpty) {
        continue;
      }
      final key = '${city.toLowerCase()}::$name'.toLowerCase();
      storedKeys.add(key);
      byKey[key] = ClubSummary(
        id: club.id,
        llbId: club.llbId,
        name: name,
        city: city,
        address: club.address,
        phone: club.phone,
        website: club.website,
        imageUrl: club.imageUrl,
        latitude: club.latitude,
        longitude: club.longitude,
        tablesPyramid: club.tablesPyramid,
        tablesPool: club.tablesPool,
        tablesSnooker: club.tablesSnooker,
        tablesTotal: club.tablesTotal,
        tournamentsCount: club.tournamentsCount,
      );
    }
    for (final tournament in repository.tournaments()) {
      final name = tournament.club.trim();
      final city = tournament.city.trim();
      if (name.isEmpty || city.isEmpty) {
        continue;
      }
      final key = '${city.toLowerCase()}::$name'.toLowerCase();
      if (storedKeys.contains(key)) {
        continue;
      }
      final previous = byKey[key];
      byKey[key] = ClubSummary(
        name: name,
        city: city,
        address: previous?.address ?? '',
        phone: previous?.phone ?? '',
        website: previous?.website ?? '',
        imageUrl: previous?.imageUrl ?? '',
        latitude: previous?.latitude,
        longitude: previous?.longitude,
        tablesPyramid: previous?.tablesPyramid,
        tablesPool: previous?.tablesPool,
        tablesSnooker: previous?.tablesSnooker,
        tablesTotal: previous?.tablesTotal,
        tournamentsCount: (previous?.tournamentsCount ?? 0) + 1,
      );
    }
    final clubs = byKey.values.toList()
      ..sort((a, b) {
        final byCity = a.city.toLowerCase().compareTo(b.city.toLowerCase());
        if (byCity != 0) {
          return byCity;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return clubs;
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
      2 => 'Медиа или турнир',
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
        searchController: searchController,
        search: search,
        searchHint: searchHint,
        selectedCity: selectedCity,
        selectedDiscipline: selectedDiscipline,
        citySuggestionsFor: citySuggestions,
        clubSuggestions: clubSuggestions(search),
        onSearchChanged: (value) => setState(() => search = value),
        onCityTap: showCityPicker,
        onDisciplineTap: showDisciplinePicker,
        onClubSelected: (club) {
          searchController.text = club;
          setState(() => search = club);
        },
        onRefresh: loadLeagueData,
      ),
      _PlayersPage(
        repository: repository,
        searchController: searchController,
        search: search,
        searchHint: searchHint,
        selectedCity: selectedCity,
        selectedDiscipline: selectedDiscipline,
        sort: playerSort,
        sortAscending: playerSortAscending,
        onSortChanged: changePlayerSort,
        onSearchChanged: (value) => setState(() => search = value),
        onCityTap: showCityPicker,
        onDisciplineTap: showDisciplinePicker,
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
    return Scaffold(
      drawer: _SettingsDrawer(
        repository: repository,
        selectedCity: selectedCity,
        selectedDiscipline: selectedDiscipline,
        selectedClubMapProvider: selectedClubMapProvider,
        clubs: clubSummaries(),
        llbUsername: llbUsername,
        llbPlayerId: llbPlayerId,
        llbSessionValid: llbSessionValid,
        citySuggestions: citySuggestions,
        onCitySelected: selectCity,
        onDisciplineSelected: selectDiscipline,
        onClubMapProviderSelected: selectClubMapProvider,
        onLlbLogin: showLlbLoginDialog,
        onLlbLogout: logoutLlb,
      ),
      appBar: AppBar(
        toolbarHeight: 56,
        leadingWidth: 56,
        leading: Builder(
          builder: (context) => Padding(
            padding: const EdgeInsets.only(left: 12),
            child: _HeaderIconButton(
              tooltip: 'Меню',
              icon: Icons.menu,
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        ),
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('Лига бильярдистов', maxLines: 1),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _HeaderIconButton(
              tooltip: 'Обновить',
              icon: Icons.refresh,
              onPressed: loading ? null : loadLeagueData,
            ),
          ),
        ],
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
      bottomNavigationBar: _AnimaBottomNavigation(
        selectedIndex: selectedTab,
        onSelected: changeTab,
      ),
    );
  }
}
