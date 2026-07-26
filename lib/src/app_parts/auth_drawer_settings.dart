part of '../app.dart';

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

class _AppAuthDialog extends StatefulWidget {
  const _AppAuthDialog();

  @override
  State<_AppAuthDialog> createState() => _AppAuthDialogState();
}

class _AppAuthDialogState extends State<_AppAuthDialog> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController displayNameController = TextEditingController();
  final TextEditingController cityController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool register = false;
  bool loading = false;
  bool obscurePassword = true;
  String? error;

  @override
  void dispose() {
    usernameController.dispose();
    displayNameController.dispose();
    cityController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final username = usernameController.text.trim();
    final password = passwordController.text;
    final displayName = displayNameController.text.trim();
    final city = cityController.text.trim();
    if (username.isEmpty || password.isEmpty) {
      setState(() => error = 'Введите логин и пароль.');
      return;
    }
    if (register && password.length < 6) {
      setState(() => error = 'Пароль должен быть не короче 6 символов.');
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    final client = AppAuthClient();
    try {
      final result = await client.authenticate(
        register: register,
        username: username,
        password: password,
        displayName: displayName.isEmpty ? username : displayName,
        city: city,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(result);
    } catch (exception) {
      if (mounted) {
        setState(() => error = 'Не удалось войти: $exception');
      }
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
      title: const Text('Аккаунт приложения'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Вход')),
                ButtonSegment(value: true, label: Text('Регистрация')),
              ],
              selected: {register},
              onSelectionChanged: loading
                  ? null
                  : (value) => setState(() => register = value.single),
            ),
            const SizedBox(height: 12),
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
            if (register) ...[
              const SizedBox(height: 12),
              TextField(
                controller: displayNameController,
                enabled: !loading,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Имя в турнирах',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: cityController,
                enabled: !loading,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Город',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              enabled: !loading,
              obscureText: obscurePassword,
              onSubmitted: (_) => loading ? null : submit(),
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
          onPressed: loading ? null : submit,
          icon: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(register ? Icons.person_add_alt_1 : Icons.login),
          label: Text(register ? 'Создать' : 'Войти'),
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
    required this.selectedClubMapProvider,
    required this.clubs,
    required this.llbUsername,
    required this.llbPlayerId,
    required this.llbSessionValid,
    required this.citySuggestions,
    required this.onCitySelected,
    required this.onDisciplineSelected,
    required this.onClubMapProviderSelected,
    required this.onLlbLogin,
    required this.onLlbLogout,
  });

  final LeagueRepository repository;
  final String selectedCity;
  final DisciplineFilter selectedDiscipline;
  final ClubMapProvider selectedClubMapProvider;
  final List<ClubSummary> clubs;
  final String? llbUsername;
  final String? llbPlayerId;
  final bool llbSessionValid;
  final List<String> Function(String query) citySuggestions;
  final ValueChanged<String> onCitySelected;
  final ValueChanged<DisciplineFilter> onDisciplineSelected;
  final ValueChanged<ClubMapProvider> onClubMapProviderSelected;
  final VoidCallback onLlbLogin;
  final VoidCallback onLlbLogout;

  @override
  Widget build(BuildContext context) {
    const drawerTextColor = Colors.white;
    return Drawer(
      backgroundColor: LlbAppTheme.baize,
      child: SafeArea(
        child: ListTileTheme(
          iconColor: drawerTextColor,
          textColor: drawerTextColor,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    Text(
                      'Меню',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: drawerTextColor,
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
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
                      ListTileTheme(
                        iconColor: Theme.of(context).colorScheme.onSurface,
                        textColor: Theme.of(context).colorScheme.onSurface,
                        child: _DrawerProfileSection(
                          repository: repository,
                          username: llbUsername!,
                          playerId: llbPlayerId,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.store_mall_directory_outlined),
                      title: const Text('Клубы'),
                      subtitle: Text(
                        '${clubs.length} клубов',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ClubsPage(
                              clubs: clubs,
                              initialCity: selectedCity,
                              mapProvider: selectedClubMapProvider,
                            ),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.perm_media_outlined),
                      title: const Text('Медиа'),
                      subtitle: const Text(
                        'Фото и видео турниров',
                        style: TextStyle(color: Colors.white70),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                MediaLibraryPage(repository: repository),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.article_outlined),
                      title: const Text('Новости'),
                      subtitle: const Text(
                        'Раздел в разработке',
                        style: TextStyle(color: Colors.white70),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const NewsPage()),
                        );
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.sports_cricket_outlined),
                      title: const Text('Кии'),
                      subtitle: const Text(
                        'Раздел в разработке',
                        style: TextStyle(color: Colors.white70),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const CuesPage()),
                        );
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.settings_outlined),
                      title: const Text('Настройки'),
                      subtitle: Text(
                        '$selectedCity · ${selectedDiscipline.label} · ${selectedClubMapProvider.label}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _DefaultSettingsPage(
                              selectedCity: selectedCity,
                              selectedDiscipline: selectedDiscipline,
                              selectedClubMapProvider: selectedClubMapProvider,
                              citySuggestions: citySuggestions,
                              onCitySelected: onCitySelected,
                              onDisciplineSelected: onDisciplineSelected,
                              onClubMapProviderSelected:
                                  onClubMapProviderSelected,
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
                      style: OutlinedButton.styleFrom(
                        foregroundColor: drawerTextColor,
                        side: const BorderSide(color: Colors.white70),
                      ),
                      icon: const Icon(Icons.logout),
                      label: const Text('Выйти'),
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
    required this.selectedClubMapProvider,
    required this.citySuggestions,
    required this.onCitySelected,
    required this.onDisciplineSelected,
    required this.onClubMapProviderSelected,
  });

  final String selectedCity;
  final DisciplineFilter selectedDiscipline;
  final ClubMapProvider selectedClubMapProvider;
  final List<String> Function(String query) citySuggestions;
  final ValueChanged<String> onCitySelected;
  final ValueChanged<DisciplineFilter> onDisciplineSelected;
  final ValueChanged<ClubMapProvider> onClubMapProviderSelected;

  @override
  State<_DefaultSettingsPage> createState() => _DefaultSettingsPageState();
}

class _DefaultSettingsPageState extends State<_DefaultSettingsPage> {
  late String selectedCity = widget.selectedCity;
  late DisciplineFilter selectedDiscipline = widget.selectedDiscipline;
  late ClubMapProvider selectedClubMapProvider = widget.selectedClubMapProvider;

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

  void pickClubMapProvider(ClubMapProvider provider) {
    widget.onClubMapProviderSelected(provider);
    setState(() => selectedClubMapProvider = provider);
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
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.map_outlined),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              'Карта клубов',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<ClubMapProvider>(
                        segments: const [
                          ButtonSegment(
                            value: ClubMapProvider.osm,
                            icon: Icon(Icons.public),
                            label: Text('OSM'),
                          ),
                          ButtonSegment(
                            value: ClubMapProvider.mapbox,
                            icon: Icon(Icons.map),
                            label: Text('Mapbox'),
                          ),
                        ],
                        selected: {selectedClubMapProvider},
                        onSelectionChanged: (value) =>
                            pickClubMapProvider(value.single),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
