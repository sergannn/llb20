import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

abstract class LeagueRepository {
  List<Tournament> tournaments();
  List<Player> players();
  List<VideoStream> videoStreams();
  Future<void> load();
  Future<Player?> playerById(String id);
  Future<void> requestVideoStream({
    required Tournament tournament,
    required String playerId,
    required String username,
    required String provider,
  });
  Future<List<Player>> searchPlayers(
    String query, {
    required DisciplineFilter discipline,
    int limit = 100,
  });
  Future<Tournament> tournamentDetails(Tournament tournament);
  void dispose();
}

class ApiLeagueRepository implements LeagueRepository {
  ApiLeagueRepository({
    http.Client? client,
    this.baseUri = const String.fromEnvironment(
      'LLB_API_BASE_URL',
      defaultValue: 'https://llb.panfilius.ru/llb-api/',
    ),
    this.playersLimit = 1000,
    this.tournamentsLimit = 300,
    LeagueRepository? fallback,
  }) : client = client ?? http.Client(),
       fallback = fallback ?? const EmptyLeagueRepository();

  final http.Client client;
  final String baseUri;
  final int playersLimit;
  final int tournamentsLimit;
  final LeagueRepository fallback;

  List<Player> _players = const [];
  List<Tournament> _tournaments = const [];
  List<VideoStream> _videoStreams = const [];

  @override
  List<Player> players() => _players.isEmpty ? fallback.players() : _players;

  @override
  List<Tournament> tournaments() =>
      _tournaments.isEmpty ? fallback.tournaments() : _tournaments;

  @override
  List<VideoStream> videoStreams() =>
      _videoStreams.isEmpty ? fallback.videoStreams() : _videoStreams;

  @override
  Future<Tournament> tournamentDetails(Tournament tournament) async {
    final uri = Uri.parse(
      baseUri,
    ).replace(queryParameters: {'resource': 'tournament', 'id': tournament.id});
    final response = await client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return fallback.tournamentDetails(tournament);
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _tournamentFromJson({
      ...json,
      'title': json['title'] ?? tournament.title,
    });
  }

  @override
  Future<List<Player>> searchPlayers(
    String query, {
    required DisciplineFilter discipline,
    int limit = 100,
  }) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return players()
          .where((player) => player.matchesDiscipline(discipline))
          .toList();
    }
    final rows = await _getList('players', {
      'q': normalized,
      'limit': '$limit',
    });
    return rows
        .map(_playerFromJson)
        .where((player) => player.matchesDiscipline(discipline))
        .toList();
  }

  @override
  Future<Player?> playerById(String id) async {
    final normalized = id.trim();
    if (normalized.isEmpty) {
      return null;
    }
    Player? cachedPlayer;
    for (final player in _players) {
      if (player.id == normalized) {
        cachedPlayer = player;
        break;
      }
    }

    final uri = Uri.parse(
      baseUri,
    ).replace(queryParameters: {'resource': 'player', 'id': normalized});
    final response = await client.get(uri);
    if (response.statusCode == 404) {
      return cachedPlayer ?? fallback.playerById(normalized);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return cachedPlayer ?? fallback.playerById(normalized);
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _playerFromJson(json);
  }

  @override
  Future<void> requestVideoStream({
    required Tournament tournament,
    required String playerId,
    required String username,
    required String provider,
  }) async {
    final uri = Uri.parse(
      baseUri,
    ).replace(queryParameters: {'resource': 'video_stream_request'});
    final response = await client.post(
      uri,
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({
        'tournament_id': tournament.id,
        'player_id': playerId,
        'requested_by': username,
        'provider': provider,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('LLB API HTTP ${response.statusCode}: ${response.body}');
    }
    await loadVideoStreams();
  }

  @override
  Future<void> load() async {
    final results = await Future.wait([
      _getList('players', {'limit': '$playersLimit'}),
      _getList('tournaments', {
        'status': 'upcoming',
        'limit': '$tournamentsLimit',
      }),
      _getList('tournaments', {
        'status': 'online',
        'limit': '$tournamentsLimit',
      }),
      _getList('tournaments', {
        'status': 'finished',
        'limit': '$tournamentsLimit',
      }),
      _getList('video_streams', {'limit': '100'}),
    ]);

    _players = results[0].map(_playerFromJson).toList()
      ..sort((a, b) => b.rating.compareTo(a.rating));
    _tournaments = _mergeTournamentRows([
      ...results[1],
      ...results[2],
      ...results[3],
    ]).map(_tournamentFromJson).toList();
    _videoStreams = results[4].map(_videoStreamFromJson).toList();
  }

  Future<void> loadVideoStreams() async {
    final rows = await _getList('video_streams', {'limit': '100'});
    _videoStreams = rows.map(_videoStreamFromJson).toList();
  }

  @override
  void dispose() {
    client.close();
  }

  Future<List<Map<String, dynamic>>> _getList(
    String resource,
    Map<String, String> query,
  ) async {
    final uri = Uri.parse(
      baseUri,
    ).replace(queryParameters: {'resource': resource, ...query});
    final response = await client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('LLB API HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  List<Map<String, dynamic>> _mergeTournamentRows(
    List<Map<String, dynamic>> rows,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final id = '${row['id'] ?? ''}'.trim();
      if (id.isNotEmpty) {
        byId[id] = row;
      }
    }
    return byId.values.toList();
  }

  Player _playerFromJson(Map<String, dynamic> json) {
    final ratings = _ratingsFromJson(json);
    final ratingKeys = '${json['rating_keys'] ?? ''}';
    return Player(
      id: '${json['id']}',
      name: _text(json['name'], 'Игрок'),
      city: _text(json['city']),
      club: _text(json['country']),
      discipline: _disciplineSummary(ratings, ratingKeys),
      rating: _intValue(json['best_elo']) ?? _intValue(json['elo']) ?? 0,
      avatarUrl: _text(json['avatar_url']),
      ratings: ratings,
      stats: _playerStatsFromJson(json['stats']),
      tournamentEntries: _playerTournamentEntriesFromJson(
        json['tournament_entries'],
      ),
      contactsRaw: _text(json['contacts_raw']),
      phone: _text(json['phone']),
      email: _text(json['email']),
      telegram: _text(json['telegram']),
      whatsapp: _text(json['whatsapp']),
    );
  }

  Tournament _tournamentFromJson(Map<String, dynamic> json) {
    final id = '${json['id']}';
    final title = _text(json['title'], 'Турнир');
    final status = _statusFromTournamentJson(json);
    final compId = _intValue(json['comp_id']);
    final bracketUrl = _text(
      json['bracket_url'],
      compId == null
          ? 'https://www.llb.su/t/$id'
          : 'https://t.llb.su/competition.php?comp=$compId',
    );
    final matches = status == TournamentStatus.upcoming
        ? <MatchInfo>[]
        : (json['matches'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(_matchFromJson)
              .toList();
    return Tournament(
      id: id,
      title: title,
      city: _text(json['city'], _cityFromTitle(title)),
      club: _text(json['club']),
      discipline: _disciplineFromTitle(title),
      level: _tournamentSectionLabel(status),
      dateLabel: _text(json['date_text']),
      playersCount: _intValue(json['participants_count']) ?? 0,
      capacity: _intValue(json['participants_limit']),
      matchesCount: status == TournamentStatus.upcoming
          ? 0
          : _intValue(json['matches_count']) ?? 0,
      status: status,
      bracketUrl: bracketUrl,
      players: (json['participants'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_participantFromJson)
          .toList(),
      matches: matches,
    );
  }

  Player _participantFromJson(Map<String, dynamic> json) {
    final ratings = _ratingsFromJson(json);
    final playerId = '${json['player_id'] ?? ''}'.trim();
    return Player(
      id: playerId.isEmpty ? 'participant-${json['name'] ?? ''}' : playerId,
      name: _text(json['name'], 'Игрок'),
      city: _text(json['city']),
      club: _text(json['country']),
      discipline: ratings.isEmpty
          ? 'Заявка LLB'
          : _disciplineSummary(ratings, ''),
      rating: _intValue(json['best_elo']) ?? _intValue(json['elo']) ?? 0,
      avatarUrl: _text(json['avatar_url']),
      ratings: ratings,
      participantPoints: _text(json['points']),
      participantPlace: _text(json['place']),
      membershipNodeId: _text(json['membership_node_id']),
    );
  }

  VideoStream _videoStreamFromJson(Map<String, dynamic> json) {
    return VideoStream(
      id: '${json['id'] ?? ''}',
      tournamentId: '${json['tournament_id'] ?? ''}',
      tournamentTitle: _text(
        json['tournament_title'] ?? json['title'],
        'Трансляция',
      ),
      provider: _text(json['provider'], 'youtube'),
      status: _text(json['status'], 'requested'),
      createdAt: _text(json['created_at']),
      playerId: _text(json['player_id']),
      playerName: _text(json['player_name']),
      playbackUrl: _text(json['playback_url']),
      obsNode: _text(json['obs_node']),
    );
  }

  MatchInfo _matchFromJson(Map<String, dynamic> json) {
    final score1 = _text(json['score1']);
    final score2 = _text(json['score2']);
    final score = score1.isEmpty && score2.isEmpty ? null : '$score1:$score2';
    return MatchInfo(
      round: _text(json['round_name'], 'Матч ${json['game_no'] ?? ''}'),
      playerA: _text(json['player1_name'], 'Игрок 1'),
      playerB: _text(json['player2_name'], 'Игрок 2'),
      score: score,
      state: _text(json['status_class'], 'ожидает'),
    );
  }

  List<PlayerRating> _ratingsFromSummary(String raw) {
    if (raw.trim().isEmpty) {
      return const [];
    }
    return raw
        .split('|')
        .map((part) {
          final chunks = part.split('::');
          if (chunks.length < 3) {
            return null;
          }
          final elo = int.tryParse(chunks[1]) ?? 0;
          final compsYear = chunks.length > 4 ? int.tryParse(chunks[4]) : null;
          final compsTotal = chunks.length > 5 ? int.tryParse(chunks[5]) : null;
          if (elo <= 0 && compsYear == null && compsTotal == null) {
            return null;
          }
          return PlayerRating(
            key: chunks[0],
            elo: elo,
            discipline: _shortDiscipline(chunks[2]),
            label: chunks.length > 3 && chunks[3].isNotEmpty
                ? chunks[3]
                : 'ЭЛО',
            compsYear: compsYear,
            compsTotal: compsTotal,
          );
        })
        .whereType<PlayerRating>()
        .toList()
      ..sort((a, b) => b.elo.compareTo(a.elo));
  }

  List<PlayerRating> _ratingsFromJson(Map<String, dynamic> json) {
    final fromSummary = _ratingsFromSummary('${json['rating_summary'] ?? ''}');
    if (fromSummary.isNotEmpty) {
      return fromSummary;
    }
    return (json['ratings'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((rating) {
          final elo = _intValue(rating['elo']);
          final compsYear = _intValue(rating['comps_year']);
          final compsTotal = _intValue(rating['comps_total']);
          if ((elo == null || elo <= 0) &&
              compsYear == null &&
              compsTotal == null) {
            return null;
          }
          return PlayerRating(
            key: _text(rating['rating_key']),
            elo: elo ?? 0,
            discipline: _shortDiscipline(_text(rating['discipline'])),
            label: _text(rating['rating_label'], 'ЭЛО'),
            compsYear: compsYear,
            compsTotal: compsTotal,
          );
        })
        .whereType<PlayerRating>()
        .toList()
      ..sort((a, b) => b.elo.compareTo(a.elo));
  }

  PlayerStats _playerStatsFromJson(dynamic raw) {
    if (raw is! Map<String, dynamic>) {
      return const PlayerStats();
    }
    return PlayerStats(
      total: _intValue(raw['total']),
      pyramid: _intValue(raw['pyramid']),
      pool: _intValue(raw['pool']),
      snooker: _intValue(raw['snooker']),
    );
  }

  List<PlayerTournamentEntry> _playerTournamentEntriesFromJson(dynamic raw) {
    return (raw as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (entry) => PlayerTournamentEntry(
            tournamentId: _text(entry['tournament_id']),
            title: _text(entry['title'], 'Турнир'),
            dateLabel: _text(entry['date_text']),
            points: _text(entry['points']),
            place: _text(entry['place']),
          ),
        )
        .toList();
  }

  String _text(dynamic value, [String fallbackValue = '']) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallbackValue : text;
  }

  int? _intValue(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse('${value ?? ''}');
  }

  String _disciplineLabel(String keys) {
    final labels = <String>[];
    if (keys.contains('spyramid')) labels.add('Пирамида любым шаром');
    if (keys.contains('pyramid')) labels.add('Пирамида одним шаром');
    if (keys.contains('pool')) labels.add('Пул');
    if (keys.contains('snooker')) labels.add('Снукер');
    if (keys.contains('carom')) labels.add('Карамболь');
    return labels.isEmpty ? 'LLB' : labels.join(', ');
  }

  String _disciplineSummary(List<PlayerRating> ratings, String keys) {
    final labels = <String>[];
    void add(String label) {
      if (label.isNotEmpty && !labels.contains(label)) {
        labels.add(label);
      }
    }

    for (final rating in ratings) {
      add(_disciplineGroup('${rating.key} ${rating.discipline}'));
    }
    if (labels.isEmpty) {
      for (final label in _disciplineLabel(keys).split(',')) {
        add(_disciplineGroup(label));
      }
    }
    return labels.isEmpty ? 'LLB' : labels.join(', ');
  }

  String _disciplineGroup(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('снукер') || lower.contains('snooker')) return 'Снукер';
    if (lower.contains('пул') || lower.contains('pool')) return 'Пул';
    if (lower.contains('карамб') || lower.contains('carom')) {
      return 'Карамболь';
    }
    if (lower.contains('пирамид') ||
        lower.contains('pyramid') ||
        lower.contains('русск')) {
      return 'Пирамида';
    }
    return value.replaceFirst(RegExp(r'^ЛЛБ\s*-\s*'), '').trim();
  }

  String _shortDiscipline(String value) {
    final lower = value.toLowerCase();
    if (lower.contains('снукер')) return 'Снукер';
    if (lower.contains('пул')) return 'Пул';
    if (lower.contains('карамб')) return 'Карамболь';
    if (lower.contains('одним шаром')) return 'Пирамида (одним шаром)';
    if (lower.contains('любым шаром')) return 'Пирамида (любым шаром)';
    if (lower.contains('пирами')) return 'Пирамида';
    return value.replaceFirst(RegExp(r'^ЛЛБ\s*-\s*'), '').trim();
  }

  String _cityFromTitle(String title) {
    final lower = title.toLowerCase();
    const knownCities = [
      'Санкт-Петербург',
      'Москва',
      'Казань',
      'Йошкар-Ола',
      'Одесса',
      'Минск',
      'Екатеринбург',
      'Новосибирск',
      'Самара',
      'Краснодар',
      'Ростов-на-Дону',
      'Воронеж',
      'Пермь',
      'Уфа',
      'Омск',
      'Челябинск',
      'Сочи',
    ];
    for (final city in knownCities) {
      if (lower.contains(city.toLowerCase())) {
        return city;
      }
    }

    final parts = title
        .split('.')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    final first = parts.first;
    if (first.toLowerCase() == 'ллб 2026' && parts.length > 1) {
      return parts[1];
    }
    final candidate = first
        .replaceAll(RegExp(r'\s+20\d\d$|\s+\d{4}$'), '')
        .trim();
    final candidateLower = candidate.toLowerCase();
    final looksLikeTitle =
        candidate.length > 32 ||
        candidateLower.contains('этап') ||
        candidateLower.contains('куб') ||
        candidateLower.contains('турнир') ||
        candidateLower.contains('чемпионат') ||
        candidateLower.contains('первенство');
    return looksLikeTitle ? '' : candidate;
  }

  String _disciplineFromTitle(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('снукер')) return 'Снукер';
    if (lower.contains('пул')) return 'Пул';
    if (lower.contains('карамб')) return 'Карамболь';
    if (lower.contains('пирами')) return 'Пирамида';
    return 'Бильярд';
  }

  TournamentStatus _statusFromTournamentJson(Map<String, dynamic> json) {
    final sourceKind = '${json['source_kind'] ?? ''}'.toLowerCase();
    final statusClass = '${json['status_class'] ?? ''}'.toLowerCase();
    if (sourceKind == 'next' || statusClass == 'future') {
      return TournamentStatus.upcoming;
    }
    if (sourceKind == 'online' ||
        statusClass == 'running' ||
        statusClass == 'live') {
      return TournamentStatus.live;
    }
    return TournamentStatus.finished;
  }

  String _tournamentSectionLabel(TournamentStatus status) {
    return switch (status) {
      TournamentStatus.upcoming => 'Предстоящий',
      TournamentStatus.live => 'Идет сейчас',
      TournamentStatus.finished => 'Итоги',
    };
  }
}

class EmptyLeagueRepository implements LeagueRepository {
  const EmptyLeagueRepository();

  @override
  Future<void> load() async {}

  @override
  List<Player> players() => const [];

  @override
  List<Tournament> tournaments() => const [];

  @override
  List<VideoStream> videoStreams() => const [];

  @override
  Future<Player?> playerById(String id) async => null;

  @override
  Future<void> requestVideoStream({
    required Tournament tournament,
    required String playerId,
    required String username,
    required String provider,
  }) async {}

  @override
  Future<List<Player>> searchPlayers(
    String query, {
    required DisciplineFilter discipline,
    int limit = 100,
  }) async {
    return const [];
  }

  @override
  Future<Tournament> tournamentDetails(Tournament tournament) async {
    return tournament;
  }

  @override
  void dispose() {}
}

class MockLeagueRepository implements LeagueRepository {
  const MockLeagueRepository();

  @override
  Future<void> load() async {}

  @override
  Future<Player?> playerById(String id) async {
    for (final player in players()) {
      if (player.id == id) {
        return player;
      }
    }
    return null;
  }

  @override
  Future<List<Player>> searchPlayers(
    String query, {
    required DisciplineFilter discipline,
    int limit = 100,
  }) async {
    return players()
        .where((player) => player.matchesDiscipline(discipline))
        .where((player) => player.matchesQuery(query))
        .take(limit)
        .toList();
  }

  @override
  Future<Tournament> tournamentDetails(Tournament tournament) async {
    return tournaments().firstWhere(
      (item) => item.id == tournament.id,
      orElse: () => tournament,
    );
  }

  @override
  void dispose() {}

  @override
  List<VideoStream> videoStreams() => const [];

  @override
  Future<void> requestVideoStream({
    required Tournament tournament,
    required String playerId,
    required String username,
    required String provider,
  }) async {}

  @override
  List<Player> players() => const [
    Player(
      id: 'p1',
      name: 'Сергеев Павел',
      city: 'Санкт-Петербург',
      club: 'Ольгино',
      discipline: 'Пул, Пирамида',
      rating: 1365,
      ratings: [
        PlayerRating(key: 'llb-pool', discipline: 'Пул', elo: 1365),
        PlayerRating(key: 'llb-pyramid', discipline: 'Пирамида', elo: 1242),
      ],
      stats: PlayerStats(total: 2, pyramid: 1, pool: 1),
      tournamentEntries: [
        PlayerTournamentEntry(
          tournamentId: 'done-1',
          title: 'Санкт-Петербург 2026. Ольгино. Пирамида N 28',
          dateLabel: '09.07.2026',
          points: '420',
          place: '3',
        ),
        PlayerTournamentEntry(
          tournamentId: 'next-1',
          title: 'Санкт-Петербург 2026. Ольгино. Пирамида N 30',
          dateLabel: '16.07.2026',
          points: '0',
          place: '17 - 24',
        ),
      ],
    ),
    Player(
      id: 'p2',
      name: 'Калинин Андрей',
      city: 'Санкт-Петербург',
      club: 'ЦБС Ольгино',
      discipline: 'Пирамида',
      rating: 1420,
      ratings: [
        PlayerRating(key: 'llb-pyramid', discipline: 'Пирамида', elo: 1420),
      ],
      stats: PlayerStats(total: 8, pyramid: 8),
    ),
    Player(
      id: 'p3',
      name: 'Волков Никита',
      city: 'Москва',
      club: 'БАЗА',
      discipline: 'Пул',
      rating: 1494,
      ratings: [PlayerRating(key: 'llb-pool', discipline: 'Пул', elo: 1494)],
      stats: PlayerStats(total: 4, pool: 4),
    ),
  ];

  @override
  List<Tournament> tournaments() {
    final allPlayers = players();
    return [
      Tournament(
        id: 'done-1',
        title: 'Санкт-Петербург 2026. Ольгино. Пирамида N 28',
        city: 'Санкт-Петербург',
        club: 'ЦБС Ольгино',
        discipline: 'Пирамида',
        level: 'Региональный',
        dateLabel: '9 июля',
        playersCount: 36,
        capacity: 36,
        matchesCount: 35,
        status: TournamentStatus.finished,
        bracketUrl: 'https://www.llb.su/tournaments/results',
        players: allPlayers,
        matches: const [
          MatchInfo(
            round: 'Финал',
            playerA: 'Сергеев Павел',
            playerB: 'Калинин Андрей',
            score: '4:2',
          ),
        ],
      ),
      Tournament(
        id: 'next-1',
        title: 'Санкт-Петербург 2026. Ольгино. Пирамида N 30',
        city: 'Санкт-Петербург',
        club: 'ЦБС Ольгино',
        discipline: 'Пирамида',
        level: 'Региональный',
        dateLabel: '16 июля, 19:00',
        playersCount: 14,
        capacity: 36,
        matchesCount: 0,
        status: TournamentStatus.upcoming,
        bracketUrl: 'https://www.llb.su/tournaments/next',
        players: allPlayers,
        matches: const [],
      ),
    ];
  }
}

class ChallongeApiClient {
  ChallongeApiClient({
    http.Client? client,
    this.clientId = const String.fromEnvironment('CHALLONGE_CLIENT_ID'),
    this.clientSecret = const String.fromEnvironment('CHALLONGE_CLIENT_SECRET'),
    this.baseUrl = 'https://api.challonge.com/v2.1',
    this.tokenUrl = 'https://api.challonge.com/oauth/token',
  }) : client = client ?? http.Client();

  final http.Client client;
  final String clientId;
  final String clientSecret;
  final String baseUrl;
  final String tokenUrl;

  Future<Tournament> createTournament({
    required String name,
    required String url,
    required String gameName,
    required String tournamentType,
    required bool private,
  }) async {
    final token = await _accessToken();
    final response = await client.post(
      Uri.parse('$baseUrl/tournaments.json'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/vnd.api+json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'data': {
          'type': 'tournament',
          'attributes': {
            'name': name,
            'url': url,
            'tournament_type': tournamentType,
            'game_name': gameName,
            'private': private,
            'notifications': {
              'upon_matches_open': true,
              'upon_tournament_ends': true,
            },
            'registration_options': {'open_signup': false},
          },
        },
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('HTTP ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final tournament = data['data'] as Map<String, dynamic>;
    final attributes = tournament['attributes'] as Map<String, dynamic>;
    final challongeUrl = attributes['url']?.toString() ?? url;
    return Tournament(
      id: '${tournament['id']}',
      title: '${attributes['name'] ?? name}',
      city: '',
      club: '',
      discipline: '${attributes['game_name'] ?? gameName}',
      level: 'Challonge',
      dateLabel: '${attributes['starts_at'] ?? ''}',
      playersCount: 0,
      capacity: null,
      matchesCount: 0,
      status: TournamentStatus.upcoming,
      bracketUrl: challongeUrl.startsWith('http')
          ? challongeUrl
          : 'https://challonge.com/$challongeUrl',
      players: const [],
      matches: const [],
    );
  }

  Future<String> _accessToken() async {
    if (clientId.isEmpty || clientSecret.isEmpty) {
      throw StateError('Не заданы CHALLONGE_CLIENT_ID/CHALLONGE_CLIENT_SECRET');
    }
    final response = await client.post(
      Uri.parse(tokenUrl),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': 'curl/8.7.1',
      },
      body: {
        'grant_type': 'client_credentials',
        'client_id': clientId,
        'client_secret': clientSecret,
        'scope': 'tournaments:read tournaments:write',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('HTTP ${response.statusCode}: ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['access_token']?.toString() ?? '';
    if (token.isEmpty) {
      throw StateError('Challonge не вернул access_token');
    }
    return token;
  }
}
