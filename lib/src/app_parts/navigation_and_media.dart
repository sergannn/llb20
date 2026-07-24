part of '../app.dart';

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 24),
        style: IconButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surface,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          disabledForegroundColor: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: LlbAppTheme.border),
          ),
        ),
      ),
    );
  }
}

class _AnimaBottomNavigation extends StatelessWidget {
  const _AnimaBottomNavigation({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _items = [
    (
      icon: Icons.emoji_events_outlined,
      activeIcon: Icons.emoji_events,
      label: 'Турниры',
    ),
    (icon: Icons.groups_outlined, activeIcon: Icons.groups, label: 'Игроки'),
    (
      icon: Icons.perm_media_outlined,
      activeIcon: Icons.perm_media,
      label: 'Медиа',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: const Border(top: BorderSide(color: LlbAppTheme.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
          child: Row(
            children: [
              for (var index = 0; index < _items.length; index++) ...[
                Expanded(
                  child: _AnimaBottomNavigationItem(
                    icon: _items[index].icon,
                    activeIcon: _items[index].activeIcon,
                    label: _items[index].label,
                    selected: selectedIndex == index,
                    onTap: () => onSelected(index),
                  ),
                ),
                if (index != _items.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimaBottomNavigationItem extends StatelessWidget {
  const _AnimaBottomNavigationItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 52,
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          border: Border.all(
            color: selected ? scheme.primaryContainer : Colors.transparent,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? activeIcon : icon,
              size: 23,
              color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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
  int selectedMediaTab = 0;

  @override
  Widget build(BuildContext context) {
    final query = widget.search.trim().toLowerCase();
    final mediaItems = <({Tournament tournament, TournamentMedia media})>[
      for (final tournament in widget.repository.tournaments())
        for (final media in tournament.media)
          if (query.isEmpty ||
              tournament.title.toLowerCase().contains(query) ||
              media.title.toLowerCase().contains(query))
            (tournament: tournament, media: media),
    ];
    final photos = mediaItems
        .where((item) => item.media.kind == TournamentMediaKind.photo)
        .toList();
    final videos = mediaItems
        .where((item) => item.media.kind == TournamentMediaKind.video)
        .toList();
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
            'Медиа',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          _SegmentedSelector(
            selectedIndex: selectedMediaTab,
            options: [
              _SegmentOption(
                icon: Icons.photo_library_outlined,
                label: 'Фото ${photos.length}',
              ),
              _SegmentOption(
                icon: Icons.video_library_outlined,
                label: 'Видео ${videos.length}',
              ),
              _SegmentOption(
                icon: Icons.sensors_outlined,
                label: 'Эфиры ${streams.length}',
              ),
            ],
            onSelected: (index) => setState(() => selectedMediaTab = index),
          ),
          const SizedBox(height: 14),
          if (selectedMediaTab == 0)
            _MediaItemsList(
              items: photos,
              emptyIcon: Icons.photo_library_outlined,
              emptyTitle: 'Фото пока нет',
            )
          else if (selectedMediaTab == 1)
            _MediaItemsList(
              items: videos,
              emptyIcon: Icons.video_library_outlined,
              emptyTitle: 'Видео пока нет',
            )
          else if (streams.isEmpty)
            const _EmptyState(
              icon: Icons.sensors_outlined,
              title: 'Пока нет трансляций',
              text: '',
            )
          else
            for (final stream in streams) ...[
              _VideoStreamCard(stream: stream),
              const SizedBox(height: 9),
            ],
        ],
      ),
    );
  }
}

class _MediaItemsList extends StatelessWidget {
  const _MediaItemsList({
    required this.items,
    required this.emptyIcon,
    required this.emptyTitle,
  });

  final List<({Tournament tournament, TournamentMedia media})> items;
  final IconData emptyIcon;
  final String emptyTitle;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _EmptyState(icon: emptyIcon, title: emptyTitle, text: '');
    }
    return Column(
      children: [
        for (final item in items) ...[
          Card(
            child: ListTile(
              leading: Icon(
                item.media.isVideo
                    ? Icons.play_circle_outline
                    : Icons.photo_outlined,
              ),
              title: Text(
                item.media.title.isEmpty
                    ? item.tournament.title
                    : item.media.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                item.tournament.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.open_in_new),
              onTap: item.media.url.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => _BracketWebViewPage(
                          title: item.media.isVideo ? 'Видео' : 'Фото',
                          url: item.media.url,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 9),
        ],
      ],
    );
  }
}

class _SegmentOption {
  const _SegmentOption({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _SegmentedSelector extends StatelessWidget {
  const _SegmentedSelector({
    required this.selectedIndex,
    required this.options,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<_SegmentOption> options;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Row(
        children: [
          for (var index = 0; index < options.length; index++) ...[
            Expanded(
              child: InkWell(
                onTap: () => onSelected(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                  color: index == selectedIndex
                      ? colorScheme.primaryContainer
                      : Colors.transparent,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(options[index].icon, size: 20),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          options[index].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (index != options.length - 1) const VerticalDivider(width: 1),
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
