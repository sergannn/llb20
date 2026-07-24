part of '../app.dart';

class _TournamentsPage extends StatefulWidget {
  const _TournamentsPage({
    required this.repository,
    required this.searchController,
    required this.search,
    required this.searchHint,
    required this.selectedCity,
    required this.selectedDiscipline,
    required this.citySuggestionsFor,
    required this.clubSuggestions,
    required this.onSearchChanged,
    required this.onCityTap,
    required this.onDisciplineTap,
    required this.onClubSelected,
    required this.onRefresh,
  });

  final LeagueRepository repository;
  final TextEditingController searchController;
  final String search;
  final String searchHint;
  final String selectedCity;
  final DisciplineFilter selectedDiscipline;
  final List<String> Function(String query) citySuggestionsFor;
  final List<String> clubSuggestions;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onCityTap;
  final VoidCallback onDisciplineTap;
  final ValueChanged<String> onClubSelected;
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              children: [
                _AnimaSearchField(
                  controller: widget.searchController,
                  label: 'Поиск турниров',
                  hintText: widget.searchHint,
                  value: widget.search,
                  onChanged: widget.onSearchChanged,
                ),
                const SizedBox(height: 12),
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
                    for (final club in widget.clubSuggestions)
                      _FilterChipData(
                        icon: Icons.store_outlined,
                        label: club,
                        onPressed: () => widget.onClubSelected(club),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _TournamentTabBar(
                        tabs: _tabs,
                        tournaments: visibleTournaments,
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      tooltip: 'Создать турнир',
                      onPressed: showCreateTournamentSheet,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ],
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

  Future<void> showCreateTournamentSheet() async {
    final tournament = await showModalBottomSheet<Tournament>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _CreateTournamentSheet(
        repository: widget.repository,
        initialCity: widget.selectedCity,
        initialDiscipline: widget.selectedDiscipline.label,
        citySuggestionsFor: widget.citySuggestionsFor,
      ),
    );
    if (tournament == null || !mounted) {
      return;
    }
    await widget.onRefresh();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Турнир создан: ${tournament.title}')),
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TournamentDetailsPage(
          repository: widget.repository,
          tournament: tournament,
        ),
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

class _CreateTournamentSheet extends StatefulWidget {
  const _CreateTournamentSheet({
    required this.repository,
    required this.initialCity,
    required this.initialDiscipline,
    required this.citySuggestionsFor,
  });

  final LeagueRepository repository;
  final String initialCity;
  final String initialDiscipline;
  final List<String> Function(String query) citySuggestionsFor;

  @override
  State<_CreateTournamentSheet> createState() => _CreateTournamentSheetState();
}

class _CreateTournamentSheetState extends State<_CreateTournamentSheet> {
  late final TextEditingController titleController = TextEditingController(
    text: '${widget.initialCity} 2026. Тестовый турнир',
  );
  late final TextEditingController cityController = TextEditingController(
    text: widget.initialCity,
  );
  final TextEditingController clubController = TextEditingController();
  final TextEditingController dateController = TextEditingController();
  late final TextEditingController disciplineController = TextEditingController(
    text: widget.initialDiscipline,
  );
  String tournamentType = 'single elimination';
  final TextEditingController capacityController = TextEditingController(
    text: '32',
  );
  bool loading = false;
  String? error;

  @override
  void dispose() {
    titleController.dispose();
    cityController.dispose();
    clubController.dispose();
    dateController.dispose();
    disciplineController.dispose();
    capacityController.dispose();
    super.dispose();
  }

  Future<void> createTournament() async {
    final title = titleController.text.trim();
    final city = cityController.text.trim();
    final club = clubController.text.trim();
    final dateText = dateController.text.trim();
    final discipline = disciplineController.text.trim();
    final capacity = int.tryParse(capacityController.text.trim());
    if (title.isEmpty || city.isEmpty || club.isEmpty || dateText.isEmpty) {
      setState(() => error = 'Заполните название, город, клуб и дату.');
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });
    try {
      final tournament = await widget.repository.createTournament(
        title: title,
        city: city,
        club: club,
        dateText: dateText,
        discipline: discipline.isEmpty ? 'Пирамида' : discipline,
        tournamentType: tournamentType,
        capacity: capacity,
        createdBy: 'llb-mobile',
      );
      if (mounted) {
        Navigator.of(context).pop(tournament);
      }
    } catch (exception) {
      if (mounted) {
        setState(() => error = 'Не удалось создать турнир: $exception');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> pickCity() async {
    final city = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _CityPickerSheet(
        initialCity: cityController.text,
        suggestionsFor: widget.citySuggestionsFor,
      ),
    );
    if (city == null || !mounted) {
      return;
    }
    setState(() {
      cityController.text = city;
      if (!clubSuggestions(city: city).contains(clubController.text.trim())) {
        clubController.clear();
      }
    });
  }

  Future<void> pickDiscipline() async {
    final selected = DisciplineFilter.values.firstWhere(
      (item) => item.label == disciplineController.text.trim(),
      orElse: () => DisciplineFilter.russianBilliards,
    );
    final discipline = await showModalBottomSheet<DisciplineFilter>(
      context: context,
      useSafeArea: true,
      builder: (context) =>
          _DisciplinePickerSheet(selectedDiscipline: selected),
    );
    if (discipline == null || !mounted) {
      return;
    }
    setState(() => disciplineController.text = discipline.label);
  }

  Future<void> pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2, 12, 31),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 19, minute: 0),
    );
    if (time == null || !mounted) {
      return;
    }
    setState(() {
      dateController.text =
          '${_two(date.day)}.${_two(date.month)}.${_two(date.year % 100)} '
          '${_two(time.hour)}:${_two(time.minute)}';
    });
  }

  List<String> clubSuggestions({String? city}) {
    final selectedCity = (city ?? cityController.text).trim().toLowerCase();
    final clubs = <String>{};
    for (final tournament in widget.repository.tournaments()) {
      final club = tournament.club.trim();
      if (club.isEmpty) {
        continue;
      }
      if (selectedCity.isNotEmpty &&
          tournament.city.trim().toLowerCase() != selectedCity) {
        continue;
      }
      clubs.add(club);
    }
    final sorted = clubs.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted.take(12).toList();
  }

  List<String> disciplineSuggestions() {
    return DisciplineFilter.values
        .where((discipline) => discipline != DisciplineFilter.all)
        .map((discipline) => discipline.label)
        .toList();
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Новый турнир',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: 'Закрыть',
                onPressed: loading ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: titleController,
            enabled: !loading,
            decoration: const InputDecoration(
              labelText: 'Название',
              prefixIcon: Icon(Icons.emoji_events_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: cityController,
            enabled: !loading,
            readOnly: true,
            onTap: loading ? null : pickCity,
            decoration: const InputDecoration(
              labelText: 'Город',
              prefixIcon: Icon(Icons.place_outlined),
              suffixIcon: Icon(Icons.expand_more),
            ),
          ),
          _SuggestionChips(
            options: widget.citySuggestionsFor(cityController.text),
            selected: cityController.text,
            maxVisible: 6,
            onSelected: loading
                ? null
                : (value) => setState(() {
                    cityController.text = value;
                    if (!clubSuggestions(
                      city: value,
                    ).contains(clubController.text.trim())) {
                      clubController.clear();
                    }
                  }),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: clubController,
            enabled: !loading,
            decoration: const InputDecoration(
              labelText: 'Клуб',
              prefixIcon: Icon(Icons.store_outlined),
            ),
          ),
          _SuggestionChips(
            options: clubSuggestions(),
            selected: clubController.text,
            maxVisible: 8,
            onSelected: loading
                ? null
                : (value) => setState(() => clubController.text = value),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: dateController,
            enabled: !loading,
            readOnly: true,
            onTap: loading ? null : pickDateTime,
            decoration: const InputDecoration(
              labelText: 'Дата и время',
              hintText: '25.07.26 19:00',
              prefixIcon: Icon(Icons.event_outlined),
              suffixIcon: Icon(Icons.expand_more),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: disciplineController,
            enabled: !loading,
            readOnly: true,
            onTap: loading ? null : pickDiscipline,
            decoration: const InputDecoration(
              labelText: 'Дисциплина',
              prefixIcon: Icon(Icons.pool_outlined),
              suffixIcon: Icon(Icons.expand_more),
            ),
          ),
          _SuggestionChips(
            options: disciplineSuggestions(),
            selected: disciplineController.text,
            maxVisible: 4,
            onSelected: loading
                ? null
                : (value) => setState(() => disciplineController.text = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: tournamentType,
            items: const [
              DropdownMenuItem(
                value: 'single elimination',
                child: Text('Одиночное выбывание'),
              ),
              DropdownMenuItem(
                value: 'double elimination',
                child: Text('Двойное выбывание'),
              ),
              DropdownMenuItem(value: 'round robin', child: Text('Круговая')),
              DropdownMenuItem(value: 'swiss', child: Text('Swiss')),
            ],
            onChanged: loading
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => tournamentType = value);
                    }
                  },
            decoration: const InputDecoration(
              labelText: 'Формат сетки',
              prefixIcon: Icon(Icons.account_tree_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: capacityController,
            enabled: !loading,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Лимит участников',
              prefixIcon: Icon(Icons.groups_outlined),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: loading ? null : createTournament,
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Создать'),
          ),
        ],
      ),
    );
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

class _SuggestionChips extends StatelessWidget {
  const _SuggestionChips({
    required this.options,
    required this.selected,
    required this.maxVisible,
    required this.onSelected,
  });

  final List<String> options;
  final String selected;
  final int maxVisible;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final normalized = selected.trim().toLowerCase();
    final visible = options
        .where((option) => option.trim().isNotEmpty)
        .where((option) => option.trim().toLowerCase() != normalized)
        .take(maxVisible)
        .toList();
    if (visible.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in visible)
              ActionChip(
                label: Text(option),
                visualDensity: VisualDensity.compact,
                onPressed: onSelected == null
                    ? null
                    : () => onSelected!(option),
              ),
          ],
        ),
      ),
    );
  }
}

class _FilterChipData {
  const _FilterChipData({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}

class _AnimaSearchField extends StatelessWidget {
  const _AnimaSearchField({
    required this.controller,
    required this.label,
    required this.hintText,
    required this.value,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: const Icon(Icons.search, size: 28),
            suffixIcon: value.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Очистить',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
            filled: true,
            fillColor: scheme.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 11,
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
      ],
    );
  }
}

class _FilterChipsRow extends StatelessWidget {
  const _FilterChipsRow({required this.chips});

  final List<_FilterChipData> chips;

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < chips.length; index++) ...[
            _AnimaFilterChip(chip: chips[index]),
            if (index != chips.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _AnimaFilterChip extends StatelessWidget {
  const _AnimaFilterChip({required this.chip});

  final _FilterChipData chip;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: chip.onPressed,
      icon: Icon(chip.icon, size: 18),
      label: Text(chip.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        maximumSize: const Size(240, 44),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        backgroundColor: Theme.of(context).colorScheme.surface,
        side: const BorderSide(color: LlbAppTheme.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
    );
  }
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
