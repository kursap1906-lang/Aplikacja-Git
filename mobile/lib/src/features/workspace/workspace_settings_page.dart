import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import 'workspace_data.dart';
import 'workspace_shell.dart';

class WorkspaceSettingsPage extends StatefulWidget {
  const WorkspaceSettingsPage({
    required this.api,
    required this.accounts,
    required this.onCalendar,
    super.key,
  });
  final ApiClient api;
  final List<WorkspaceAccount> accounts;
  final VoidCallback onCalendar;

  @override
  State<WorkspaceSettingsPage> createState() => _WorkspaceSettingsPageState();
}

class _WorkspaceSettingsPageState extends State<WorkspaceSettingsPage> {
  Map<String, dynamic>? _data;
  String? _error, _selected, _notice, _testing;
  String _tab = 'Integracje', _category = 'Wszystkie', _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.api.request('/workspace/settings');
      if (data['integrations'] is! List ||
          data['security'] is! Map ||
          data['automation'] is! Map) {
        throw const ApiException(
          'INVALID_WORKSPACE_RESPONSE',
          'Nieprawidłowy raport ustawień.',
        );
      }
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _test(Map<String, dynamic> integration) async {
    final id = integration['id'] as String;
    String? accountId;
    if (id == 'github' || id == 'actions' || id == 'agents') {
      accountId = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Wybierz konto do sprawdzenia'),
          children: [
            for (final account in widget.accounts.where(
              (account) => account.active,
            ))
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, account.id),
                child: Text('@${account.login}'),
              ),
            if (!widget.accounts.any((account) => account.active))
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Najpierw połącz konto GitHub.'),
              ),
          ],
        ),
      );
      if (accountId == null || !mounted) return;
    }
    setState(() {
      _testing = id;
      _notice = null;
      _error = null;
    });
    try {
      final response = await widget.api.request(
        '/workspace/settings/integrations/$id/test',
        method: 'POST',
        data: {'accountId': ?accountId},
      );
      if (response['message'] is! String) {
        throw const ApiException(
          'INVALID_WORKSPACE_RESPONSE',
          'Brak wyniku sprawdzenia.',
        );
      }
      if (mounted) setState(() => _notice = response['message'] as String);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _testing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final integrations = data == null
        ? <Map<String, dynamic>>[]
        : (data['integrations'] as List).cast<Map<String, dynamic>>();
    final selected = integrations
        .where((entry) => entry['id'] == _selected)
        .firstOrNull;
    final categories = {
      'Wszystkie',
      for (final entry in integrations) entry['category'] as String,
    };
    return WorkspacePanel(
      title: 'Ustawienia i integracje',
      trailing: IconButton(
        tooltip: 'Odśwież ustawienia',
        onPressed: _load,
        icon: const Icon(Icons.refresh),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Osobne kontrolki dla każdej usługi, konta, narzędzia i polityki. Statusy pochodzą z backendu.',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tab in [
                'Integracje',
                'Konta GitHub',
                'Serwer i MCP',
                'Automatyzacje',
                'Bezpieczeństwo',
              ])
                ChoiceChip(
                  label: Text(tab),
                  selected: _tab == tab,
                  onSelected: (_) => setState(() => _tab = tab),
                ),
            ],
          ),
          const Divider(height: 32),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_notice != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_notice!)),
          if (data == null && _error == null) const LinearProgressIndicator(),
          if (_tab == 'Konta GitHub') ...[
            for (final account in widget.accounts)
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text('@${account.login}'),
                subtitle: Text(
                  account.active
                      ? 'Aktywne · ${account.scopes.join(', ')}'
                      : 'Wymaga ponownej autoryzacji',
                ),
              ),
            FilledButton.icon(
              onPressed: () => context.go('/connect'),
              icon: const Icon(Icons.link),
              label: const Text('Zarządzaj kontami GitHub'),
            ),
          ] else if (_tab == 'Automatyzacje') ...[
            const ListTile(
              leading: Icon(Icons.schedule),
              title: Text('Harmonogramy instancji'),
              subtitle: Text(
                'Dni, godziny i strefa czasowa są zapisywane. Automatyczny start/stop SDK nie jest jeszcze dostępny.',
              ),
            ),
            OutlinedButton(
              onPressed: widget.onCalendar,
              child: const Text('Otwórz kalendarz'),
            ),
            const ListTile(
              leading: Icon(Icons.merge),
              title: Text('Automatyczne scalanie: wyłączone'),
              subtitle: Text(
                'Utworzenie PR nie scala zmian. Wymagane jest ręczne review.',
              ),
            ),
          ] else if (_tab == 'Bezpieczeństwo') ...[
            for (final item in [
              (
                'Izolacja właścicieli',
                'Zapytania API sprawdzają właściciela danych.',
              ),
              ('Ochrona CSRF', 'Mutacje wymagają sesji i tokenu CSRF.'),
              (
                'Szyfrowanie sekretów',
                'Tokeny i pliki pozostają na backendzie. Nie są zwracane w raporcie ustawień.',
              ),
              (
                'Dowody review',
                'Istniejące bramki etapów wymagają zielonego CI i testu manualnego przypiętych do SHA.',
              ),
            ])
              ListTile(
                leading: const Icon(
                  Icons.verified_user_outlined,
                  color: Colors.green,
                ),
                title: Text(item.$1),
                subtitle: Text(item.$2),
              ),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Dostęp narzędzi do botów'),
              subtitle: Text(
                'Nie jest jeszcze udostępniany. Narzędzia MCP i preview nie są aktywowane przełącznikiem UI.',
              ),
            ),
          ] else ...[
            Wrap(
              spacing: 12,
              children: [
                Chip(label: Text('Integracje: ${integrations.length}')),
                Chip(
                  label: Text(
                    'Skonfigurowane: ${integrations.where((entry) => entry['status'] == 'CONFIGURED' || entry['status'] == 'AVAILABLE').length}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Wyszukaj integrację',
                hintText: 'GitHub, MCP, Blender, OpenAI…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final category in categories)
                  ChoiceChip(
                    label: Text(category),
                    selected: _category == category,
                    onSelected: (_) => setState(() => _category = category),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 550
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    for (final entry in integrations.where(
                      (entry) =>
                          (_category == 'Wszystkie' ||
                              entry['category'] == _category) &&
                          ('${entry['name']} ${entry['description']}'
                              .toLowerCase()
                              .contains(_search.toLowerCase())) &&
                          (_tab != 'Serwer i MCP' ||
                              [
                                'Serwer i CLI',
                                'MCP i Skills',
                                'CAD i grafika',
                              ].contains(entry['category'])),
                    ))
                      SizedBox(
                        width: width,
                        child: Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: _selected == entry['id']
                                  ? Colors.indigo
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => setState(() {
                              _selected = entry['id'] as String;
                              _notice = null;
                            }),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        _icon(entry['category'] as String),
                                        color: Colors.blue,
                                      ),
                                      const Spacer(),
                                      const Icon(Icons.expand_more),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    entry['name'] as String,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    entry['description'] as String,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  const SizedBox(height: 10),
                                  Chip(
                                    label: Text(
                                      _status(entry['status'] as String),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            if (selected != null) ...[
              const Divider(height: 32),
              Text(
                selected['name'] as String,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              SelectableText(selected['configuration'] as String),
              const SizedBox(height: 12),
              if (selected['supported'] == true)
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _testing == null
                          ? () => _test(selected)
                          : null,
                      icon: const Icon(Icons.science_outlined),
                      label: Text(
                        _testing == selected['id']
                            ? 'Sprawdzanie…'
                            : 'Sprawdź konfigurację',
                      ),
                    ),
                    if (selected['id'] == 'github' ||
                        selected['id'] == 'actions')
                      FilledButton(
                        onPressed: () => context.go('/connect'),
                        child: const Text('Konfiguruj konta GitHub'),
                      ),
                  ],
                )
              else
                const Text(
                  'Niedostępne — wymaga implementacji adaptera i kontroli uprawnień. Nie zapisujemy pozornych połączeń.',
                ),
            ],
          ],
        ],
      ),
    );
  }
}

String _status(String value) => switch (value) {
  'AVAILABLE' => 'Dostępne',
  'CONFIGURED' => 'Skonfigurowano',
  'METADATA_ONLY' => 'Tylko metadane',
  'NOT_CONFIGURED' => 'Nieskonfigurowane',
  _ => 'Adapter niedostępny',
};
IconData _icon(String category) => switch (category) {
  'AI i GitHub' => Icons.account_tree_outlined,
  'Bazy i storage' => Icons.storage_outlined,
  'Serwer i CLI' => Icons.terminal,
  'CAD i grafika' => Icons.view_in_ar_outlined,
  'MCP i Skills' => Icons.extension_outlined,
  'DevOps' => Icons.cloud_outlined,
  _ => Icons.notifications_outlined,
};
