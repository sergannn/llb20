part of '../app.dart';

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
