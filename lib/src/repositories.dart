import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

abstract class LeagueRepository {
  List<Tournament> tournaments();
  List<Player> players();
  List<VideoStream> videoStreams();
  List<ClubSummaryData> clubs();
  Future<void> load();
  Future<Player?> playerById(String id);
  Future<Tournament> createTournament({
    required String title,
    required String city,
    required String club,
    required String dateText,
    required String discipline,
    required String tournamentType,
    required int? capacity,
    required String createdBy,
  });
  Future<TournamentRegistrationResult> tournamentRegistrationAction({
    required Tournament tournament,
    required String action,
    required String username,
    required String? playerId,
    required String name,
    required String city,
  });
  Future<List<ClubSummaryData>> loadClubs({String city = ''});
  Future<ClubSummaryData> createClub({
    required String name,
    required String city,
    String address = '',
    String phone = '',
    String website = '',
    String createdBy = '',
  });
  Future<List<TournamentMedia>> tournamentMedia(Tournament tournament);
  Future<TournamentMedia> uploadTournamentMedia({
    required Tournament tournament,
    required TournamentMediaKind kind,
    required String filename,
    required List<int> bytes,
    required String uploadedBy,
    String title = '',
  });
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

class TournamentRegistrationResult {
  const TournamentRegistrationResult({
    required this.ok,
    required this.state,
    required this.message,
    required this.participants,
    required this.participantsCount,
  });

  final bool ok;
  final String state;
  final String message;
  final List<Player> participants;
  final int participantsCount;
}

class ClubSummaryData {
  const ClubSummaryData({
    required this.name,
    required this.city,
    this.id = '',
    this.address = '',
    this.phone = '',
    this.website = '',
    this.latitude,
    this.longitude,
    this.tournamentsCount = 0,
  });

  final String id;
  final String name;
  final String city;
  final String address;
  final String phone;
  final String website;
  final double? latitude;
  final double? longitude;
  final int tournamentsCount;

  String get searchText => '$name $city $address'.toLowerCase();
  String get mapQuery =>
      address.isEmpty ? '$name, $city' : '$name, $address, $city';
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
  static const _cacheKey = 'llb_api_repository_cache_v1';
  static const _requestTimeout = Duration(seconds: 8);

  List<Player> _players = const [];
  List<Tournament> _tournaments = const [];
  List<VideoStream> _videoStreams = const [];
  List<ClubSummaryData> _clubs = const [];

  @override
  List<Player> players() => _players.isEmpty ? fallback.players() : _players;

  @override
  List<Tournament> tournaments() =>
      _tournaments.isEmpty ? fallback.tournaments() : _tournaments;

  @override
  List<VideoStream> videoStreams() =>
      _videoStreams.isEmpty ? fallback.videoStreams() : _videoStreams;

  @override
  List<ClubSummaryData> clubs() => _clubs.isEmpty ? fallback.clubs() : _clubs;

  @override
  Future<List<ClubSummaryData>> loadClubs({String city = ''}) async {
    try {
      final rows = await _getList('clubs', {
        if (city.trim().isNotEmpty) 'city': city.trim(),
        'limit': '300',
      });
      _clubs = rows.map(_clubFromJson).toList();
      return _clubs;
    } catch (_) {
      return clubs();
    }
  }

  @override
  Future<ClubSummaryData> createClub({
    required String name,
    required String city,
    String address = '',
    String phone = '',
    String website = '',
    String createdBy = '',
  }) async {
    final uri = Uri.parse(
      baseUri,
    ).replace(queryParameters: {'resource': 'clubs'});
    final response = await client
        .post(
          uri,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({
            'name': name,
            'city': city,
            'address': address,
            'phone': phone,
            'website': website,
            'created_by': createdBy,
          }),
        )
        .timeout(_requestTimeout);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('LLB API ${json['error'] ?? response.statusCode}');
    }
    final club = _clubFromJson((json['item'] as Map<String, dynamic>?) ?? json);
    _clubs = [
      club,
      ..._clubs.where(
        (item) =>
            item.name.toLowerCase() != club.name.toLowerCase() ||
            item.city.toLowerCase() != club.city.toLowerCase(),
      ),
    ];
    return club;
  }

  @override
  Future<Tournament> tournamentDetails(Tournament tournament) async {
    try {
      final uri = Uri.parse(baseUri).replace(
        queryParameters: {'resource': 'tournament', 'id': tournament.id},
      );
      final response = await client.get(uri).timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return fallback.tournamentDetails(tournament);
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return _tournamentFromJson({
        ...json,
        'title': json['title'] ?? tournament.title,
      });
    } catch (_) {
      return fallback.tournamentDetails(tournament);
    }
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
    try {
      final rows = await _getList('players', {
        'q': normalized,
        'limit': '$limit',
      });
      return rows
          .map(_playerFromJson)
          .where((player) => player.matchesDiscipline(discipline))
          .toList();
    } catch (_) {
      return players()
          .where((player) => player.matchesDiscipline(discipline))
          .where((player) => player.matchesQuery(normalized))
          .take(limit)
          .toList();
    }
  }

  @override
  Future<List<TournamentMedia>> tournamentMedia(Tournament tournament) async {
    try {
      final uri = Uri.parse(baseUri).replace(
        queryParameters: {
          'resource': 'tournament_media',
          'tournament_id': tournament.id,
          'limit': '100',
        },
      );
      final response = await client.get(uri).timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return tournament.media;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return (data['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_tournamentMediaFromJson)
          .toList();
    } catch (_) {
      return tournament.media;
    }
  }

  @override
  Future<TournamentMedia> uploadTournamentMedia({
    required Tournament tournament,
    required TournamentMediaKind kind,
    required String filename,
    required List<int> bytes,
    required String uploadedBy,
    String title = '',
  }) async {
    final uri = Uri.parse(
      baseUri,
    ).replace(queryParameters: {'resource': 'tournament_media'});
    final request = http.MultipartRequest('POST', uri)
      ..fields['tournament_id'] = tournament.id
      ..fields['kind'] = kind.storageKey
      ..fields['uploaded_by'] = uploadedBy
      ..fields['title'] = title
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );
    final streamedResponse = await client
        .send(request)
        .timeout(_requestTimeout);
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('LLB API HTTP ${response.statusCode}: ${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _tournamentMediaFromJson(
      (json['item'] as Map<String, dynamic>?) ?? json,
    );
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

    try {
      final uri = Uri.parse(
        baseUri,
      ).replace(queryParameters: {'resource': 'player', 'id': normalized});
      final response = await client.get(uri).timeout(_requestTimeout);
      if (response.statusCode == 404) {
        return cachedPlayer ?? fallback.playerById(normalized);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return cachedPlayer ?? fallback.playerById(normalized);
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return _playerFromJson(json);
    } catch (_) {
      return cachedPlayer ?? fallback.playerById(normalized);
    }
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
    final response = await client
        .post(
          uri,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({
            'tournament_id': tournament.id,
            'player_id': playerId,
            'requested_by': username,
            'provider': provider,
          }),
        )
        .timeout(_requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('LLB API HTTP ${response.statusCode}: ${response.body}');
    }
    await loadVideoStreams();
  }

  @override
  Future<void> load() async {
    try {
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
      final tournamentRows = [...results[1], ...results[2], ...results[3]];
      _applyRows(
        players: results[0],
        tournaments: tournamentRows,
        videoStreams: results[4],
      );
      await _saveCache(
        players: results[0],
        tournaments: tournamentRows,
        videoStreams: results[4],
      );
    } catch (error) {
      final restored = await _restoreCache();
      if (restored) {
        throw StateError('Нет сети. Показана сохраненная копия.');
      }
      rethrow;
    }
  }

  @override
  Future<Tournament> createTournament({
    required String title,
    required String city,
    required String club,
    required String dateText,
    required String discipline,
    required String tournamentType,
    required int? capacity,
    required String createdBy,
  }) async {
    final uri = Uri.parse(
      baseUri,
    ).replace(queryParameters: {'resource': 'tournament_create'});
    final response = await client
        .post(
          uri,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({
            'title': title,
            'city': city,
            'club': club,
            'date_text': dateText,
            'discipline': discipline,
            'tournament_type': tournamentType,
            'participants_limit': capacity,
            'created_by': createdBy,
          }),
        )
        .timeout(_requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('LLB API HTTP ${response.statusCode}: ${response.body}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final tournament = _tournamentFromJson(
      (json['item'] as Map<String, dynamic>?) ?? json,
    );
    _tournaments = [tournament, ..._tournaments];
    return tournament;
  }

  @override
  Future<TournamentRegistrationResult> tournamentRegistrationAction({
    required Tournament tournament,
    required String action,
    required String username,
    required String? playerId,
    required String name,
    required String city,
  }) async {
    final normalizedAction = action == 'unregister' ? 'unregister' : 'register';
    final uri = Uri.parse(
      baseUri,
    ).replace(queryParameters: {'resource': 'tournament_registration'});
    final response = await client
        .post(
          uri,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({
            'tournament_id': tournament.id,
            'action': normalizedAction,
            'username': username,
            'player_id': int.tryParse(playerId ?? ''),
            'name': name.isEmpty ? username : name,
            'city': city,
          }),
        )
        .timeout(_requestTimeout);
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final ok =
        response.statusCode >= 200 &&
        response.statusCode < 300 &&
        _boolValue(json['ok']);
    if (!ok) {
      final error = _text(json['error'], 'registration_failed');
      throw StateError('LLB API $error');
    }
    final participants = (json['participants'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_participantFromJson)
        .toList();
    return TournamentRegistrationResult(
      ok: ok,
      state: _text(json['state'], normalizedAction),
      message: _text(json['message']),
      participants: participants,
      participantsCount:
          _intValue(json['participants_count']) ?? participants.length,
    );
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
    final response = await client.get(uri).timeout(_requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('LLB API HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  void _applyRows({
    required List<Map<String, dynamic>> players,
    required List<Map<String, dynamic>> tournaments,
    required List<Map<String, dynamic>> videoStreams,
  }) {
    _players = players.map(_playerFromJson).toList()
      ..sort((a, b) => b.rating.compareTo(a.rating));
    _tournaments = _mergeTournamentRows(
      tournaments,
    ).map(_tournamentFromJson).toList();
    _videoStreams = videoStreams.map(_videoStreamFromJson).toList();
  }

  Future<void> _saveCache({
    required List<Map<String, dynamic>> players,
    required List<Map<String, dynamic>> tournaments,
    required List<Map<String, dynamic>> videoStreams,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode({
          'saved_at': DateTime.now().toIso8601String(),
          'players': players,
          'tournaments': tournaments,
          'video_streams': videoStreams,
        }),
      );
    } catch (_) {
      // Cache is best-effort: a successful API load must not fail because
      // local storage is unavailable in tests or on a damaged device profile.
    }
  }

  Future<bool> _restoreCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) {
        return false;
      }
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final players = _cachedRows(json['players']);
      final tournaments = _cachedRows(json['tournaments']);
      final videoStreams = _cachedRows(json['video_streams']);
      if (players.isEmpty && tournaments.isEmpty && videoStreams.isEmpty) {
        return false;
      }
      _applyRows(
        players: players,
        tournaments: tournaments,
        videoStreams: videoStreams,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  List<Map<String, dynamic>> _cachedRows(dynamic raw) {
    return (raw as List<dynamic>? ?? const [])
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
      discipline: _text(json['discipline'], _disciplineFromTitle(title)),
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
      appCreated: _boolValue(json['app_created']),
      media: (json['media'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_tournamentMediaFromJson)
          .toList(),
    );
  }

  TournamentMedia _tournamentMediaFromJson(Map<String, dynamic> json) {
    return TournamentMedia(
      id: _text(json['id']),
      tournamentId: _text(json['tournament_id']),
      kind: TournamentMediaKind.fromStorage(_text(json['kind'], 'photo')),
      title: _text(json['title']),
      url: _text(json['url'] ?? json['file_url']),
      mimeType: _text(json['mime_type']),
      uploadedBy: _text(json['uploaded_by']),
      createdAt: _text(json['created_at']),
    );
  }

  ClubSummaryData _clubFromJson(Map<String, dynamic> json) {
    return ClubSummaryData(
      id: _text(json['id']),
      name: _text(json['name']),
      city: _text(json['city']),
      address: _text(json['address']),
      phone: _text(json['phone']),
      website: _text(json['website']),
      latitude: _doubleValue(json['latitude']),
      longitude: _doubleValue(json['longitude']),
      tournamentsCount: _intValue(json['tournaments_count']) ?? 0,
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
      discipline: ratings.isEmpty ? '' : _disciplineSummary(ratings, ''),
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

  double? _doubleValue(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('${value ?? ''}');
  }

  bool _boolValue(dynamic value) {
    if (value is bool) {
      return value;
    }
    final text = '$value'.trim().toLowerCase();
    return text == '1' || text == 'true' || text == 'yes';
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
  List<ClubSummaryData> clubs() => const [];

  @override
  Future<List<ClubSummaryData>> loadClubs({String city = ''}) async => clubs();

  @override
  Future<ClubSummaryData> createClub({
    required String name,
    required String city,
    String address = '',
    String phone = '',
    String website = '',
    String createdBy = '',
  }) async {
    throw UnsupportedError('Club creation is not available');
  }

  @override
  Future<Player?> playerById(String id) async => null;

  @override
  Future<Tournament> createTournament({
    required String title,
    required String city,
    required String club,
    required String dateText,
    required String discipline,
    required String tournamentType,
    required int? capacity,
    required String createdBy,
  }) async {
    throw UnsupportedError('Tournament creation is not available');
  }

  @override
  Future<TournamentRegistrationResult> tournamentRegistrationAction({
    required Tournament tournament,
    required String action,
    required String username,
    required String? playerId,
    required String name,
    required String city,
  }) async {
    throw UnsupportedError('Tournament registration is not available');
  }

  @override
  Future<List<TournamentMedia>> tournamentMedia(Tournament tournament) async {
    return tournament.media;
  }

  @override
  Future<TournamentMedia> uploadTournamentMedia({
    required Tournament tournament,
    required TournamentMediaKind kind,
    required String filename,
    required List<int> bytes,
    required String uploadedBy,
    String title = '',
  }) async {
    throw UnsupportedError('Media upload is not available');
  }

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
  Future<Tournament> createTournament({
    required String title,
    required String city,
    required String club,
    required String dateText,
    required String discipline,
    required String tournamentType,
    required int? capacity,
    required String createdBy,
  }) async {
    return Tournament(
      id: 'mock-created',
      title: title,
      city: city,
      club: club,
      discipline: discipline,
      level: 'Предстоящий',
      dateLabel: dateText,
      playersCount: 0,
      capacity: capacity,
      matchesCount: 0,
      status: TournamentStatus.upcoming,
      bracketUrl: 'https://challonge.com/mock_created',
      players: const [],
      matches: const [],
      appCreated: true,
    );
  }

  @override
  Future<TournamentRegistrationResult> tournamentRegistrationAction({
    required Tournament tournament,
    required String action,
    required String username,
    required String? playerId,
    required String name,
    required String city,
  }) async {
    final registered = action != 'unregister';
    final participant = Player(
      id: playerId?.isNotEmpty == true ? playerId! : 'mock-$username',
      name: name.isEmpty ? username : name,
      city: city,
      club: '',
      discipline: tournament.discipline,
      rating: 0,
    );
    return TournamentRegistrationResult(
      ok: true,
      state: registered ? 'registered' : 'not_registered',
      message: registered ? 'Вы записаны на турнир.' : 'Запись отменена.',
      participants: registered ? [participant] : const [],
      participantsCount: registered ? 1 : 0,
    );
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
  Future<List<TournamentMedia>> tournamentMedia(Tournament tournament) async {
    return tournament.media;
  }

  @override
  Future<TournamentMedia> uploadTournamentMedia({
    required Tournament tournament,
    required TournamentMediaKind kind,
    required String filename,
    required List<int> bytes,
    required String uploadedBy,
    String title = '',
  }) async {
    return TournamentMedia(
      id: 'mock-media-${DateTime.now().microsecondsSinceEpoch}',
      tournamentId: tournament.id,
      kind: kind,
      title: title,
      url: '',
      createdAt: DateTime.now().toIso8601String(),
      uploadedBy: uploadedBy,
    );
  }

  @override
  List<VideoStream> videoStreams() => const [];

  @override
  List<ClubSummaryData> clubs() => const [
    ClubSummaryData(
      name: 'ЦБС Ольгино',
      city: 'Санкт-Петербург',
      tournamentsCount: 2,
    ),
    ClubSummaryData(name: 'БАЗА', city: 'Санкт-Петербург', tournamentsCount: 1),
  ];

  @override
  Future<List<ClubSummaryData>> loadClubs({String city = ''}) async => clubs();

  @override
  Future<ClubSummaryData> createClub({
    required String name,
    required String city,
    String address = '',
    String phone = '',
    String website = '',
    String createdBy = '',
  }) async {
    return ClubSummaryData(
      name: name,
      city: city,
      address: address,
      phone: phone,
      website: website,
    );
  }

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
        media: const [
          TournamentMedia(
            id: 'media-1',
            tournamentId: 'done-1',
            kind: TournamentMediaKind.photo,
            title: 'Финальный стол',
            url: 'https://example.test/final-table.jpg',
            createdAt: '2026-07-09 20:10:00',
          ),
        ],
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
