part of '../app.dart';

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
      key: ValueKey('tournament-card-${tournament.id}'),
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
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      tournament.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _StatusBadge(status: tournament.status),
                ],
              ),
              const SizedBox(height: 12),
              _TournamentMetaGrid(tournament: tournament),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _TournamentFooterFact(
                      label: 'Участники',
                      value: spots,
                    ),
                  ),
                  if (tournament.status != TournamentStatus.upcoming) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TournamentFooterFact(
                        label: 'Матчи',
                        value: '${tournament.matchesCount}',
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TournamentMetaGrid extends StatelessWidget {
  const _TournamentMetaGrid({required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final items = [
      (icon: Icons.calendar_today_outlined, label: tournament.startDateText),
      if (tournament.startTimeText.isNotEmpty)
        (icon: Icons.schedule_outlined, label: tournament.startTimeText),
      (icon: Icons.place_outlined, label: tournament.city),
      (icon: Icons.pool_outlined, label: tournament.discipline),
      (icon: Icons.store_outlined, label: tournament.club),
    ].where((item) => item.label.trim().isNotEmpty).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth < 320
            ? constraints.maxWidth
            : (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: _InfoChip(icon: item.icon, label: item.label),
              ),
          ],
        );
      },
    );
  }
}

class _TournamentFooterFact extends StatelessWidget {
  const _TournamentFooterFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value.replaceAll('\n', ' '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
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
  bool detailsLoaded = false;
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
        setState(() {
          tournament = details;
          detailsLoaded = true;
        });
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
    final savedState = await secureStorage.read(
      key: '$_registrationStatePrefix${widget.tournament.id}',
    );
    if (widget.tournament.appCreated || tournament.appCreated) {
      final appUsername = await secureStorage.read(
        key: _LeagueHomePageState._appUsernameKey,
      );
      final appUserId = await secureStorage.read(
        key: _LeagueHomePageState._appUserIdKey,
      );
      final llbUsername = await secureStorage.read(
        key: _LeagueHomePageState._llbUsernameKey,
      );
      final llbPlayerId = await secureStorage.read(
        key: _LeagueHomePageState._llbPlayerIdKey,
      );
      final llbCookies = await secureStorage.read(
        key: _LeagueHomePageState._llbCookiesKey,
      );
      final fallbackUsername = llbCookies == null || llbCookies.isEmpty
          ? null
          : llbUsername;
      final username = appUsername?.isNotEmpty == true
          ? appUsername
          : fallbackUsername;
      final playerId = appUserId?.isNotEmpty == true ? appUserId : llbPlayerId;
      if (mounted) {
        setState(() {
          this.llbUsername = username;
          this.llbPlayerId = playerId;
          llbSessionValid = username != null && username.isNotEmpty;
          registrationState = savedState;
        });
      }
      return;
    }

    final username = await secureStorage.read(
      key: _LeagueHomePageState._llbUsernameKey,
    );
    var playerId = await secureStorage.read(
      key: _LeagueHomePageState._llbPlayerIdKey,
    );
    final cookies = await secureStorage.read(
      key: _LeagueHomePageState._llbCookiesKey,
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
    if (tournament.appCreated) {
      await showAppAuthDialog();
      return;
    }
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

  Future<void> showAppAuthDialog() async {
    final result = await showDialog<AppAuthResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _AppAuthDialog(),
    );
    if (result != null) {
      await secureStorage.write(
        key: _LeagueHomePageState._appUserIdKey,
        value: result.id,
      );
      await secureStorage.write(
        key: _LeagueHomePageState._appUsernameKey,
        value: result.username,
      );
      await secureStorage.write(
        key: _LeagueHomePageState._appDisplayNameKey,
        value: result.displayName,
      );
      await secureStorage.write(
        key: _LeagueHomePageState._appCityKey,
        value: result.city,
      );
      await secureStorage.write(
        key: _LeagueHomePageState._appTokenKey,
        value: result.token,
      );
      await loadRegistrationSession();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Вход выполнен: ${result.username}')),
        );
      }
    }
  }

  Future<void> submitRegistrationAction(String action) async {
    if (tournament.appCreated) {
      await submitAppTournamentRegistrationAction(action);
      return;
    }

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

  Future<void> submitAppTournamentRegistrationAction(String action) async {
    final username = llbUsername;
    if (username == null || username.isEmpty) {
      await showLoginDialog();
      return;
    }

    setState(() {
      registrationLoading = true;
      registrationMessage = null;
    });

    try {
      final displayName = await secureStorage.read(
        key: _LeagueHomePageState._appDisplayNameKey,
      );
      final city = await secureStorage.read(
        key: _LeagueHomePageState._appCityKey,
      );
      final result = await widget.repository.tournamentRegistrationAction(
        tournament: tournament,
        action: action,
        username: username,
        playerId: llbPlayerId,
        name: displayName?.trim().isNotEmpty == true ? displayName! : username,
        city: city?.trim().isNotEmpty == true ? city! : tournament.city,
      );
      final nextState = result.state == 'not_registered'
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
        registrationState = nextState;
        registrationMessage = result.message;
        tournament = tournament.copyWith(
          players: result.participants,
          playersCount: result.participantsCount,
        );
      });
      await loadDetails();
    } catch (exception) {
      if (mounted) {
        setState(() => registrationMessage = 'Ошибка API: $exception');
      }
    } finally {
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
                      label: tournament.hasExternalBracket
                          ? 'Сетка'
                          : 'Карточка',
                      value: tournament.hasExternalBracket
                          ? 'Открыть'
                          : 'Открыть в приложении',
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
              _TournamentParticipantTile(
                repository: widget.repository,
                player: player,
                tournamentCity: tournament.city,
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
            const SizedBox(height: 12),
            TournamentMediaSection(
              repository: widget.repository,
              tournament: tournament,
              username: llbUsername,
              onChanged: (media) {
                setState(() => tournament = tournament.copyWith(media: media));
              },
            ),
          ],
        ),
      ),
    );
  }

  String? _effectiveRegistrationState() {
    if (tournament.appCreated &&
        detailsLoaded &&
        registrationState == 'registered' &&
        tournament.playersCount == 0 &&
        !_currentUserListed()) {
      return 'not_registered';
    }
    if (registrationState == 'registered' ||
        registrationState == 'not_registered') {
      return registrationState;
    }
    if (_currentUserListed()) {
      return 'registered';
    }
    if (tournament.players.isNotEmpty || tournament.playersCount == 0) {
      return 'not_registered';
    }
    return null;
  }

  bool _currentUserListed() {
    final id = llbPlayerId?.trim();
    final username = llbUsername?.trim().toLowerCase();
    return tournament.players.any((player) {
      if (id != null && id.isNotEmpty && player.id == id) {
        return true;
      }
      if (username != null &&
          username.isNotEmpty &&
          player.name.trim().toLowerCase() == username) {
        return true;
      }
      return false;
    });
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

class _TournamentParticipantTile extends StatelessWidget {
  const _TournamentParticipantTile({
    required this.repository,
    required this.player,
    required this.tournamentCity,
  });

  final LeagueRepository repository;
  final Player player;
  final String tournamentCity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sameCity =
        tournamentCity.trim().isNotEmpty &&
        tournamentCity.trim().toLowerCase() == player.city.trim().toLowerCase();
    final metaParts = [
      if (player.city.isNotEmpty && !sameCity) player.city,
      if (player.club.isNotEmpty) player.club,
      if (player.participantSummary.isNotEmpty) player.participantSummary,
    ];
    final metrics = <({String label, int? value})>[
      (label: 'ЭЛО РБ', value: player.russianBilliardsElo),
      (label: 'ЭЛО Пул', value: player.poolElo),
      (
        label: 'Турниры',
        value: player.tournamentsCount > 0 ? player.tournamentsCount : null,
      ),
    ].where((item) => item.value != null && item.value! > 0).toList();

    return Card(
      key: ValueKey(
        'tournament-participant-${player.id.isNotEmpty ? player.id : (player.membershipNodeId.isNotEmpty ? player.membershipNodeId : player.name)}',
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: player.hasRealLlbId
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                              ),
                        ),
                        if (metaParts.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            metaParts.join(' · '),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: scheme.onSurface.withValues(
                                    alpha: 0.68,
                                  ),
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (metrics.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final metric in metrics)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: 0.35,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.6),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                metric.label,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${metric.value}',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
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
    final appTournament = tournament.appCreated;
    final isRegistered = state == 'registered';
    final known = state == 'registered' || state == 'not_registered';
    final stateText = username == null
        ? appTournament
              ? 'Войдите или зарегистрируйтесь в приложении, чтобы записаться.'
              : 'Войдите в LLB, чтобы записаться на турнир.'
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
                appTournament
                    ? 'Аккаунт приложения: $username${playerId == null || playerId!.isEmpty ? '' : ' · id $playerId'}'
                    : sessionValid
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
                label: Text(
                  appTournament ? 'Войти / регистрация' : 'Войти в LLB',
                ),
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
