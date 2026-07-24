part of '../app.dart';

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
    return SizedBox(
      height: 46,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xffeef1ea),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Icon(
                icon,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
