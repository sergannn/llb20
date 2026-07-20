enum TournamentStatus { live, upcoming, finished }

enum PlayerSort { surname, russianBilliards, pool, tournaments }

enum DisciplineFilter {
  all('all', 'Все дисциплины'),
  russianBilliards('russian_billiards', 'Русский бильярд'),
  pool('pool', 'Пул'),
  snooker('snooker', 'Снукер');

  const DisciplineFilter(this.storageKey, this.label);

  final String storageKey;
  final String label;

  static DisciplineFilter fromStorage(String? value) {
    return DisciplineFilter.values.firstWhere(
      (filter) => filter.storageKey == value,
      orElse: () => DisciplineFilter.russianBilliards,
    );
  }

  bool matches(String text) {
    final value = text.toLowerCase();
    return switch (this) {
      DisciplineFilter.all => true,
      DisciplineFilter.russianBilliards =>
        value.contains('пирамид') ||
            value.contains('pyramid') ||
            value.contains('русск'),
      DisciplineFilter.pool => value.contains('пул') || value.contains('pool'),
      DisciplineFilter.snooker =>
        value.contains('снукер') || value.contains('snooker'),
    };
  }
}

class PlayerRating {
  const PlayerRating({
    required this.key,
    required this.discipline,
    required this.elo,
    this.label = 'ЭЛО',
    this.compsYear,
    this.compsTotal,
  });

  final String key;
  final String discipline;
  final int elo;
  final String label;
  final int? compsYear;
  final int? compsTotal;
}

class PlayerStats {
  const PlayerStats({this.total, this.pyramid, this.pool, this.snooker});

  final int? total;
  final int? pyramid;
  final int? pool;
  final int? snooker;

  bool get isEmpty =>
      total == null && pyramid == null && pool == null && snooker == null;
}

class PlayerTournamentEntry {
  const PlayerTournamentEntry({
    required this.tournamentId,
    required this.title,
    required this.dateLabel,
    required this.points,
    required this.place,
  });

  final String tournamentId;
  final String title;
  final String dateLabel;
  final String points;
  final String place;
}

class Player {
  const Player({
    required this.id,
    required this.name,
    required this.city,
    required this.club,
    required this.discipline,
    required this.rating,
    this.avatarUrl = '',
    this.ratings = const [],
    this.stats = const PlayerStats(),
    this.tournamentEntries = const [],
    this.participantPoints = '',
    this.participantPlace = '',
    this.membershipNodeId = '',
    this.contactsRaw = '',
    this.phone = '',
    this.email = '',
    this.telegram = '',
    this.whatsapp = '',
  });

  final String id;
  final String name;
  final String city;
  final String club;
  final String discipline;
  final int rating;
  final String avatarUrl;
  final List<PlayerRating> ratings;
  final PlayerStats stats;
  final List<PlayerTournamentEntry> tournamentEntries;
  final String participantPoints;
  final String participantPlace;
  final String membershipNodeId;
  final String contactsRaw;
  final String phone;
  final String email;
  final String telegram;
  final String whatsapp;

  bool get hasRealLlbId => !id.startsWith('participant-');

  bool get hasContacts =>
      contactsRaw.isNotEmpty ||
      phone.isNotEmpty ||
      email.isNotEmpty ||
      telegram.isNotEmpty ||
      whatsapp.isNotEmpty;

  String get participantSummary {
    final parts = [
      if (participantPlace.isNotEmpty) 'место: $participantPlace',
      if (participantPoints.isNotEmpty) 'очки: $participantPoints',
    ];
    return parts.join(' · ');
  }

  String get initials {
    final parts = name.split(' ').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) {
      return '?';
    }
    return parts.take(2).map((part) => part.substring(0, 1)).join();
  }

  String get surnameKey {
    final parts = name
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    return parts.isEmpty ? name.toLowerCase() : parts.first;
  }

  String get bestEloLabel => rating > 0 ? '$rating' : 'нет';

  int get tournamentsCount {
    if (stats.total != null) {
      return stats.total!;
    }
    final disciplineTotal = [
      stats.pyramid,
      stats.pool,
      stats.snooker,
    ].whereType<int>().fold<int>(0, (sum, value) => sum + value);
    if (disciplineTotal > 0) {
      return disciplineTotal;
    }
    return tournamentEntries.length;
  }

  int? get poolElo => _bestEloWhere((rating) {
    final value = _ratingSearchText(rating);
    return value.contains('пул') || value.contains('pool');
  });

  int? get russianBilliardsElo => _bestEloWhere((rating) {
    final value = _ratingSearchText(rating);
    return value.contains('пирамид') ||
        value.contains('pyramid') ||
        value.contains('русск');
  });

  int? _bestEloWhere(bool Function(PlayerRating rating) test) {
    final values = ratings.where(test).map((rating) => rating.elo).toList();
    if (values.isEmpty) {
      return null;
    }
    values.sort();
    return values.last;
  }

  String _ratingSearchText(PlayerRating rating) {
    return '${rating.key} ${rating.discipline} ${rating.label}'.toLowerCase();
  }

  bool matchesQuery(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    return name.toLowerCase().contains(normalized);
  }

  bool matchesNameQuery(String query) => matchesQuery(query);

  bool matchesDiscipline(DisciplineFilter filter) {
    return filter.matches(
      [
        discipline,
        for (final rating in ratings)
          '${rating.key} ${rating.discipline} ${rating.label}',
      ].join(' '),
    );
  }
}

class Tournament {
  const Tournament({
    required this.id,
    required this.title,
    required this.city,
    required this.club,
    required this.discipline,
    required this.level,
    required this.dateLabel,
    required this.playersCount,
    required this.capacity,
    required this.matchesCount,
    required this.status,
    required this.bracketUrl,
    required this.players,
    required this.matches,
    this.media = const [],
  });

  final String id;
  final String title;
  final String city;
  final String club;
  final String discipline;
  final String level;
  final String dateLabel;
  final int playersCount;
  final int? capacity;
  final int matchesCount;
  final TournamentStatus status;
  final String bracketUrl;
  final List<Player> players;
  final List<MatchInfo> matches;
  final List<TournamentMedia> media;

  DateTime? get startsAt {
    final match = RegExp(r'(\d{2})\.(\d{2})\.(\d{2,4})').firstMatch(dateLabel);
    if (match == null) {
      return null;
    }
    final day = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    final rawYear = int.tryParse(match.group(3) ?? '');
    if (day == null || month == null || rawYear == null) {
      return null;
    }
    final year = rawYear < 100 ? 2000 + rawYear : rawYear;
    return DateTime(year, month, day);
  }

  Tournament copyWith({
    int? playersCount,
    int? matchesCount,
    List<Player>? players,
    List<MatchInfo>? matches,
    List<TournamentMedia>? media,
  }) {
    return Tournament(
      id: id,
      title: title,
      city: city,
      club: club,
      discipline: discipline,
      level: level,
      dateLabel: dateLabel,
      playersCount: playersCount ?? this.playersCount,
      capacity: capacity,
      matchesCount: matchesCount ?? this.matchesCount,
      status: status,
      bracketUrl: bracketUrl,
      players: players ?? this.players,
      matches: matches ?? this.matches,
      media: media ?? this.media,
    );
  }

  bool matchesQuery(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    return [
      title,
      city,
      club,
      discipline,
      level,
    ].any((value) => value.toLowerCase().contains(normalized));
  }

  bool matchesDiscipline(DisciplineFilter filter) {
    return filter.matches('$title $discipline $level');
  }
}

enum TournamentMediaKind {
  photo('photo', 'Фото'),
  video('video', 'Видео');

  const TournamentMediaKind(this.storageKey, this.label);

  final String storageKey;
  final String label;

  static TournamentMediaKind fromStorage(String value) {
    return switch (value.toLowerCase()) {
      'video' => TournamentMediaKind.video,
      _ => TournamentMediaKind.photo,
    };
  }
}

class TournamentMedia {
  const TournamentMedia({
    required this.id,
    required this.tournamentId,
    required this.kind,
    required this.url,
    required this.createdAt,
    this.title = '',
    this.mimeType = '',
    this.uploadedBy = '',
  });

  final String id;
  final String tournamentId;
  final TournamentMediaKind kind;
  final String url;
  final String createdAt;
  final String title;
  final String mimeType;
  final String uploadedBy;

  bool get isVideo => kind == TournamentMediaKind.video;
}

class VideoStream {
  const VideoStream({
    required this.id,
    required this.tournamentId,
    required this.tournamentTitle,
    required this.provider,
    required this.status,
    required this.createdAt,
    this.playerId = '',
    this.playerName = '',
    this.playbackUrl = '',
    this.obsNode = '',
  });

  final String id;
  final String tournamentId;
  final String tournamentTitle;
  final String provider;
  final String status;
  final String createdAt;
  final String playerId;
  final String playerName;
  final String playbackUrl;
  final String obsNode;

  String get providerLabel {
    return switch (provider.toLowerCase()) {
      'vk' => 'VK',
      'rutube' => 'Rutube',
      _ => 'YouTube',
    };
  }

  String get statusLabel {
    return switch (status.toLowerCase()) {
      'live' => 'в эфире',
      'starting' => 'запускается',
      'ended' => 'завершена',
      'failed' => 'ошибка',
      _ => 'заявка',
    };
  }

  bool get isLive => status.toLowerCase() == 'live';
}

class MatchInfo {
  const MatchInfo({
    required this.round,
    required this.playerA,
    required this.playerB,
    this.score,
    this.state = 'ожидает',
  });

  final String round;
  final String playerA;
  final String playerB;
  final String? score;
  final String state;
}
