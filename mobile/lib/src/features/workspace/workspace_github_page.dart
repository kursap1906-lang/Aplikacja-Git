import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import 'workspace_data.dart';
import 'workspace_repository_picker.dart';
import 'workspace_shell.dart';

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Nieprawidłowy obiekt GitHub.');
  }
  return value;
}

List<Map<String, dynamic>> _objects(Object? value) {
  if (value is! List) {
    throw const FormatException('Nieprawidłowa lista GitHub.');
  }
  return value.map(_object).toList();
}

String _text(Object? value) {
  if (value is! String) {
    throw const FormatException('Nieprawidłowy tekst GitHub.');
  }
  return value;
}

int _number(Object? value) {
  if (value is! int || value < 1) {
    throw const FormatException('Nieprawidłowy numer PR.');
  }
  return value;
}

Future<void> _open(BuildContext context, String address) async {
  final uri = Uri.tryParse(address);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'github.com' ||
      !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nie udało się otworzyć GitHub.')),
      );
    }
  }
}

class WorkspaceGitHubPage extends StatefulWidget {
  const WorkspaceGitHubPage({
    required this.api,
    required this.accounts,
    required this.projects,
    this.teams = const [],
    super.key,
  });
  final ApiClient api;
  final List<WorkspaceAccount> accounts;
  final List<WorkspaceProject> projects;
  final List<WorkspaceTeam> teams;

  @override
  State<WorkspaceGitHubPage> createState() => _WorkspaceGitHubPageState();
}

class _WorkspaceGitHubPageState extends State<WorkspaceGitHubPage> {
  WorkspaceRepositorySelection? _selection;
  List<Map<String, dynamic>> _pulls = [];
  String _filter = 'open';
  String? _error;
  int? _nextPage;
  int _generation = 0;
  bool _loading = false;

  String _query(WorkspaceRepositorySelection selection) => Uri(
    queryParameters: {
      'accountId': selection.accountId,
      'repository': selection.repository,
    },
  ).query;

  Future<void> _load({int page = 1}) async {
    final selection = _selection;
    if (selection == null) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.api.request(
        '/workspace/github/pulls?${_query(selection)}&state=$_filter&page=$page',
      );
      final pulls = _objects(response['pulls']);
      for (final pull in pulls) {
        _number(pull['number']);
        _text(pull['title']);
        _text(pull['state']);
        _text(pull['url']);
      }
      final next = response['nextPage'] == null
          ? null
          : _number(response['nextPage']);
      if (!mounted || generation != _generation) return;
      setState(() {
        _pulls = page == 1
            ? pulls
            : {
                ...{for (final pull in _pulls) pull['number']: pull},
                ...{for (final pull in pulls) pull['number']: pull},
              }.values.toList();
        _nextPage = next;
      });
    } on Exception catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _select(WorkspaceRepositorySelection? selection) {
    setState(() {
      ++_generation;
      _selection = selection;
      _pulls = [];
      _error = null;
      _nextPage = null;
      _loading = false;
    });
    if (selection != null) _load();
  }

  Future<void> _create() async {
    final selection = _selection;
    if (selection == null) return;
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _CreatePullDialog(api: widget.api, query: _query(selection)),
    );
    if (created == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      WorkspacePanel(
        title: 'GitHub i Pull Requests',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Rzeczywiste PR z wybranego konta i repozytorium. Komentarze oraz tworzenie PR wymagają jawnego zapisu. Nie wykonujemy automatycznego scalania.',
            ),
            const SizedBox(height: 16),
            if (widget.projects.any(
              (project) =>
                  project.mainGithubAccountId != null &&
                  project.repository != null,
            ))
              Wrap(
                spacing: 8,
                children: [
                  for (final project in widget.projects.where(
                    (project) =>
                        project.mainGithubAccountId != null &&
                        project.repository != null,
                  ))
                    ActionChip(
                      label: Text(project.name),
                      onPressed: () => _select((
                        accountId: project.mainGithubAccountId!,
                        repository: project.repository!,
                      )),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            WorkspaceRepositoryPicker(
              api: widget.api,
              accounts: widget.accounts,
              onChanged: _select,
              requirePush: false,
            ),
            if (_selection != null) ...[
              const SizedBox(height: 12),
              Text('Wybrano: ${_selection!.repository}'),
              Wrap(
                spacing: 8,
                children: [
                  for (final state in [
                    ('open', 'Otwarte'),
                    ('closed', 'Zamknięte'),
                    ('all', 'Wszystkie'),
                  ])
                    ChoiceChip(
                      label: Text(state.$2),
                      selected: _filter == state.$1,
                      onSelected: (_) {
                        setState(() {
                          _filter = state.$1;
                          _pulls = [];
                        });
                        _load();
                      },
                    ),
                  IconButton(
                    tooltip: 'Odśwież PR',
                    onPressed: _loading ? null : () => _load(),
                    icon: const Icon(Icons.refresh),
                  ),
                  FilledButton.icon(
                    onPressed: _create,
                    icon: const Icon(Icons.add),
                    label: const Text('Nowy PR'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null)
        WorkspacePanel(
          title: 'Nie udało się wczytać PR',
          child: Column(
            children: [
              Text(_error!),
              TextButton(
                onPressed: () => _load(),
                child: const Text('Ponów odczyt'),
              ),
            ],
          ),
        ),
      if (!_loading && _error == null && _selection != null && _pulls.isEmpty)
        const WorkspacePanel(
          title: 'Pull Requests',
          child: Text('Brak PR dla wybranego filtra.'),
        ),
      for (final pull in _pulls)
        Card(
          child: ListTile(
            leading: Icon(
              pull['state'] == 'merged' ? Icons.merge : Icons.call_merge,
              color: pull['state'] == 'merged'
                  ? Colors.deepPurple
                  : Colors.green,
            ),
            title: Text('#${pull['number']} · ${pull['title']}'),
            subtitle: Text(
              '${pull['state']} · ${pull['head']} → ${pull['base']} · @${pull['author']}',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => _PullDetail(
                api: widget.api,
                query: _query(_selection!),
                number: _number(pull['number']),
                stages: {
                  for (final team in widget.teams.where(
                    (team) => widget.projects.any(
                      (project) =>
                          project.id == team.projectId &&
                          project.repository == _selection!.repository,
                    ),
                  ))
                    for (final member in team.members.where(
                      (member) =>
                          member.githubAccountId == _selection!.accountId,
                    ))
                      for (final stage in member.stages.where(
                        (stage) =>
                            stage.status != 'APPROVED' &&
                            stage.status != 'CANCELLED',
                      ))
                        stage.id: '${member.name} · ${stage.title}',
                },
              ),
            ),
          ),
        ),
      if (_nextPage != null)
        OutlinedButton(
          onPressed: _loading ? null : () => _load(page: _nextPage!),
          child: const Text('Więcej PR'),
        ),
    ],
  );
}

class _CreatePullDialog extends StatefulWidget {
  const _CreatePullDialog({required this.api, required this.query});
  final ApiClient api;
  final String query;
  @override
  State<_CreatePullDialog> createState() => _CreatePullDialogState();
}

class _CreatePullDialogState extends State<_CreatePullDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(),
      _head = TextEditingController(),
      _base = TextEditingController(text: 'main'),
      _body = TextEditingController();
  bool _draft = true, _saving = false;
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    _head.dispose();
    _base.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.api.request(
        '/workspace/github/pulls?${widget.query}',
        method: 'POST',
        data: {
          'title': _title.text.trim(),
          'head': _head.text.trim(),
          'base': _base.text.trim(),
          'body': _body.text,
          'draft': _draft,
        },
      );
      _number(_object(result['pull'])['number']);
      if (mounted) Navigator.pop(context, true);
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _error =
              '$error\nPrzed ponowieniem sprawdź listę PR — odpowiedź mogła zostać utracona.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Utwórz Pull Request'),
    content: SizedBox(
      width: 550,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Gałąź źródłowa musi już istnieć na GitHub. Ta operacja nie wykonuje pusha ani merge.',
              ),
              WorkspaceTextField(
                controller: _title,
                label: 'Tytuł PR',
                maxLength: 200,
                isRequired: true,
                enabled: !_saving,
              ),
              WorkspaceTextField(
                controller: _head,
                label: 'Gałąź źródłowa',
                maxLength: 250,
                isRequired: true,
                enabled: !_saving,
              ),
              WorkspaceTextField(
                controller: _base,
                label: 'Gałąź docelowa',
                maxLength: 250,
                isRequired: true,
                enabled: !_saving,
              ),
              WorkspaceTextField(
                controller: _body,
                label: 'Opis PR',
                maxLength: 20000,
                lines: 3,
                enabled: !_saving,
              ),
              SwitchListTile(
                title: const Text('Wersja robocza (draft)'),
                value: _draft,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _draft = value),
              ),
              if (_error != null) Text(_error!),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Anuluj'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Zapisywanie…' : 'Utwórz PR na GitHub'),
      ),
    ],
  );
}

class _PullDetail extends StatefulWidget {
  const _PullDetail({
    required this.api,
    required this.query,
    required this.number,
    required this.stages,
  });
  final ApiClient api;
  final String query;
  final int number;
  final Map<String, String> stages;
  @override
  State<_PullDetail> createState() => _PullDetailState();
}

class _PullDetailState extends State<_PullDetail> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _sending = false;
  String? _stageId;
  final _comment = TextEditingController();

  Future<void> _linkStage() async {
    final stageId = _stageId;
    if (stageId == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await widget.api.request(
        '/workspace/github/pulls/${widget.number}/link-stage?${widget.query}',
        method: 'POST',
        data: {'stageId': stageId},
      );
      final botId = _text(result['botId']);
      final prId = _text(result['pullRequestId']);
      if (!mounted) return;
      final router = GoRouter.of(context);
      Navigator.pop(context);
      router.go('/bots/$botId/pull-requests/$prId');
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await widget.api.request(
        '/workspace/github/pulls/${widget.number}?${widget.query}',
      );
      _object(data['pull']);
      _objects(data['files']);
      _objects(data['comments']);
      _objects(data['checks']);
      _objects(data['statuses']);
      _text(data['ciSha']);
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

  Future<void> _send() async {
    if (_comment.text.trim().isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final response = await widget.api.request(
        '/workspace/github/pulls/${widget.number}/comments?${widget.query}',
        method: 'POST',
        data: {'body': _comment.text.trim()},
      );
      _object(response['comment']);
      _comment.clear();
      await _load();
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _error =
              '$error\nPrzed ponowieniem odśwież komentarze; nie ponawiamy zapisu automatycznie.',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return AlertDialog(
      title: Text('PR #${widget.number}'),
      content: SizedBox(
        width: 900,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (data == null && _error == null)
                const LinearProgressIndicator(),
              if (data != null) ...[
                Text(
                  _text(_object(data['pull'])['title']),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  '${_object(data['pull'])['head']} → ${_object(data['pull'])['base']} · ${_object(data['pull'])['state']}',
                ),
                if (widget.stages.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _stageId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Etap bota do review',
                    ),
                    items: [
                      for (final stage in widget.stages.entries)
                        DropdownMenuItem(
                          value: stage.key,
                          child: Text(
                            stage.value,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _sending
                        ? null
                        : (value) => setState(() => _stageId = value),
                  ),
                  OutlinedButton.icon(
                    onPressed: _sending || _stageId == null ? null : _linkStage,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text(
                      'Powiąż PR i otwórz test manualny / review',
                    ),
                  ),
                ],
                SelectableText(_object(data['pull'])['body'] as String? ?? ''),
                OutlinedButton.icon(
                  onPressed: () =>
                      _open(context, _text(_object(data['pull'])['url'])),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Otwórz na GitHub'),
                ),
                const Divider(),
                const Text(
                  'CI i statusy',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SelectableText('Sprawdzone SHA: ${data['ciSha']}'),
                if (_objects(data['checks']).isEmpty &&
                    _objects(data['statuses']).isEmpty)
                  const Text(
                    'Brak wyników CI. Nie oznacza to zaliczonych testów.',
                  ),
                for (final check in _objects(data['checks']))
                  ListTile(
                    leading: Icon(
                      check['conclusion'] == 'success'
                          ? Icons.check_circle_outline
                          : Icons.pending_outlined,
                      color: check['conclusion'] == 'success'
                          ? Colors.green
                          : Colors.orange,
                    ),
                    title: Text(_text(check['name'])),
                    subtitle: Text(
                      '${check['status']} · ${check['conclusion'] ?? 'w toku'}',
                    ),
                  ),
                for (final status in _objects(data['statuses']))
                  ListTile(
                    title: Text(_text(status['context'])),
                    subtitle: Text(_text(status['state'])),
                  ),
                if (data['truncated'] == true)
                  const Text(
                    'Raport jest częściowy (paginacja GitHub). Pełny wynik sprawdź na GitHub; nie traktuj go jako kompletnego dowodu zatwierdzenia.',
                  ),
                const Divider(),
                Text(
                  'Zmienione pliki (${_objects(data['files']).length})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final file in _objects(data['files']))
                  ExpansionTile(
                    title: Text(_text(file['filename'])),
                    subtitle: Text(
                      '${file['status']} · +${file['additions']} / -${file['deletions']}',
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          file['patch'] as String? ?? 'Brak tekstowego diffu (np. plik binarny lub ograniczenie GitHub).',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                const Divider(),
                const Text(
                  'Komentarze',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                for (final comment in _objects(data['comments']))
                  ListTile(
                    title: Text(
                      (_object(
                            comment['user'] ?? {'login': '[deleted]'},
                          ))['login']
                          as String,
                    ),
                    subtitle: SelectableText(_text(comment['body'])),
                  ),
                TextField(
                  controller: _comment,
                  enabled: !_sending,
                  maxLength: 20000,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Komentarz do PR',
                  ),
                ),
                FilledButton.icon(
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send),
                  label: const Text('Wyślij komentarz na GitHub'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : _load,
          child: const Text('Odśwież'),
        ),
        TextButton(
          onPressed: _sending ? null : () => Navigator.pop(context),
          child: const Text('Zamknij'),
        ),
      ],
    );
  }
}
