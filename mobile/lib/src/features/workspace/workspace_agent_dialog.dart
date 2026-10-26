import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import 'workspace_data.dart';

Future<void> showWorkspaceAgent(
  BuildContext context, {
  required ApiClient api,
  required WorkspaceTask task,
  required VoidCallback onChanged,
}) => showDialog<void>(
  context: context,
  builder: (_) => _AgentDialog(api: api, task: task, onChanged: onChanged),
);

class _AgentDialog extends StatefulWidget {
  const _AgentDialog({
    required this.api,
    required this.task,
    required this.onChanged,
  });
  final ApiClient api;
  final WorkspaceTask task;
  final VoidCallback onChanged;
  @override
  State<_AgentDialog> createState() => _AgentDialogState();
}

class _AgentDialogState extends State<_AgentDialog> {
  String? _stageId, _status, _taskState, _url, _error;
  bool _busy = true;
  Timer? _timer;
  Map<String, dynamic>? _details;
  final _reply = TextEditingController();

  @override
  void initState() {
    super.initState();
    _prepare();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_busy &&
          _stageId != null &&
          _taskState != null &&
          [
            'queued',
            'in_progress',
            'waiting_for_user',
            'idle',
          ].contains(_taskState)) {
        _request();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _reply.dispose();
    super.dispose();
  }

  void _read(Map<String, dynamic> response) {
    final stage = response['stage'];
    if (stage is! Map<String, dynamic> ||
        stage['id'] is! String ||
        stage['status'] is! String) {
      throw const ApiException(
        'INVALID_WORKSPACE_RESPONSE',
        'Brak potwierdzonego etapu GitHub.',
      );
    }
    _stageId = stage['id'] as String;
    _status = stage['status'] as String;
    final task = response['task'];
    if (task != null) {
      if (task is! Map<String, dynamic> ||
          task['state'] is! String ||
          (task['url'] != null && task['url'] is! String)) {
        throw const ApiException(
          'INVALID_WORKSPACE_RESPONSE',
          'Nieprawidłowy status agenta.',
        );
      }
      _taskState = task['state'] as String;
      final candidate = Uri.tryParse(task['url'] as String? ?? '');
      _url = candidate?.scheme == 'https' && candidate?.host == 'github.com'
          ? candidate.toString()
          : _url;
      _details = task;
    }
  }

  Future<void> _prepare() async {
    try {
      final result = await widget.api.request(
        '/workspace/tasks/${widget.task.id}/agent-stage',
      );
      if (!mounted) return;
      if (result['stage'] == null && result['execution'] == 'GITHUB_HOSTED') {
        setState(() => _status = 'PENDING');
      } else {
        setState(() => _read(result));
        if (_status != 'PENDING') await _request();
      }
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _request({bool start = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (start && _stageId == null) {
        final prepared = await widget.api.request(
          '/workspace/tasks/${widget.task.id}/agent-stage',
          method: 'POST',
        );
        if (!mounted) return;
        setState(() => _read(prepared));
      }
      final result = await widget.api.request(
        '/stages/$_stageId/${start ? 'start' : 'task'}',
        method: start ? 'POST' : 'GET',
        data: start ? <String, dynamic>{} : null,
      );
      if (!mounted) return;
      setState(() => _read(result));
      widget.onChanged();
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _error =
              '$error${start ? '\nPrzed ponowieniem sprawdź zakładkę Agents w repozytorium GitHub.' : ''}',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() async {
    final uri = Uri.tryParse(_url ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.userInfo.isNotEmpty ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        setState(() => _error = 'Nie udało się otworzyć zadania na GitHub.');
      }
    }
  }

  Future<void> _sendReply() async {
    final details = _details;
    final pulls = details?['pullRequests'];
    if (details == null ||
        pulls is! List ||
        pulls.isEmpty ||
        _reply.text.trim().isEmpty) {
      return;
    }
    final first = pulls.first;
    if (first is! Map ||
        first['number'] is! int ||
        details['accountId'] is! String ||
        details['repository'] is! String) {
      setState(() => _error = 'Brak zweryfikowanego PR do kontynuacji.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final query = Uri(
        queryParameters: {
          'accountId': details['accountId'] as String,
          'repository': details['repository'] as String,
        },
      ).query;
      await widget.api.request(
        '/workspace/github/pulls/${first['number']}/comments?$query',
        method: 'POST',
        data: {
          'body':
              '@copilot ${_reply.text.trim()}\n\nKontynuuj w tej samej gałęzi i PR. Zrealizuj kryteria etapu, uruchom testy i pozostaw wynik do review. Nie scalaj, nie wdrażaj i nie twórz dodatkowych gałęzi.',
        },
      );
      if (!mounted) return;
      _reply.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Wysłano komentarz @copilot na GitHub. To nie jest potwierdzenie rozpoczęcia kolejnej sesji; odśwież status.',
          ),
        ),
      );
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _error =
              '$error\nPrzed ponowieniem sprawdź komentarze PR — zapis mógł dotrzeć do GitHuba.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Agent GitHub — praca zdalna'),
    content: SizedBox(
      width: 1000,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.task.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            const Text(
              'Kod jest zmieniany przez GitHub Copilot w repozytorium, tak jak w zakładce Agents. Panel nie uruchamia lokalnego wykonawcy. API startu wymaga Copilot Business lub Enterprise i uprawnień Agent tasks (zapis). Start może zużywać pakiet przypisanego konta. Po zgłoszeniu treść i przypisanie zadania zostają zachowane jako historia.',
            ),
            const SizedBox(height: 12),
            Text('Etap: ${_status ?? 'przygotowywanie'}'),
            if (_taskState != null) Text('GitHub: $_taskState'),
            if (_details?['branch'] != null)
              SelectableText('Gałąź: ${_details!['branch']}'),
            ExpansionTile(
              title: const Text('Szczegółowy prompt zadania'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(widget.task.description),
                ),
              ],
            ),
            for (final session
                in (_details?['sessions'] as List? ?? const [])
                    .whereType<Map>())
              Card(
                child: ListTile(
                  title: Text('Sesja ${session['id']} · ${session['state']}'),
                  subtitle: SelectableText(
                    [
                      if (session['model'] != null)
                        'Model: ${session['model']}',
                      if (session['head_ref'] != null)
                        'Gałąź: ${session['head_ref']}',
                      if (session['prompt'] != null)
                        'Prompt: ${session['prompt']}',
                      if (session['usage'] is Map)
                        'Zużycie: ${(session['usage'] as Map)['amount']} ${(session['usage'] as Map)['type']}',
                      if (session['error'] is Map)
                        'Błąd: ${(session['error'] as Map)['message']}',
                    ].join('\n'),
                  ),
                ),
              ),
            if (_details != null)
              const Text(
                'API GitHub udostępnia status i metadane sesji, ale nie pełny zapis wewnętrznej rozmowy ani automatyczne odpowiedzi na pytania. Nie pokazujemy fikcyjnych logów. Agent sam rozwiązuje zwykłe decyzje zgodnie z promptem; pytania wymagające właściciela pozostają do odpowiedzi.',
              ),
            if ((_details?['pullRequests'] as List? ?? const [])
                .isNotEmpty) ...[
              const Divider(),
              for (final pull
                  in (_details!['pullRequests'] as List).whereType<Map>())
                TextButton(
                  onPressed: () {
                    final router = GoRouter.of(context);
                    Navigator.pop(context);
                    router.go(
                      '/bots/${widget.task.botId}/pull-requests/${pull['id']}',
                    );
                  },
                  child: Text(
                    'PR #${pull['number']} · ${pull['title']} — diff, CI i review',
                  ),
                ),
              TextField(
                controller: _reply,
                enabled: !_busy,
                minLines: 3,
                maxLines: 8,
                maxLength: 18000,
                decoration: const InputDecoration(
                  labelText: 'Odpowiedź / instrukcja kontynuacji dla @copilot',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _sendReply,
                icon: const Icon(Icons.send),
                label: const Text('Wyślij do agenta w tym samym PR'),
              ),
            ],
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_status == 'WAITING_APPROVAL')
              const Text(
                'Agent zakończył pracę, ale zadanie nie jest automatycznie zatwierdzone. Sprawdź PR, CI i test manualny dla tego samego SHA.',
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Zamknij'),
      ),
      if (_url != null)
        OutlinedButton(onPressed: _open, child: const Text('Otwórz na GitHub')),
      if (_stageId != null)
        TextButton(
          onPressed: _busy ? null : () => _request(),
          child: const Text('Odśwież status'),
        ),
      if (_status == 'WAITING_APPROVAL')
        TextButton(
          onPressed: () {
            final router = GoRouter.of(context);
            Navigator.pop(context);
            router.go('/bots/${widget.task.botId}');
          },
          child: const Text('Przejdź do review etapu'),
        ),
      if (['PENDING', 'FAILED', 'CHANGES_REQUESTED'].contains(_status))
        FilledButton.icon(
          onPressed: _busy ? null : () => _request(start: true),
          icon: const Icon(Icons.cloud_outlined),
          label: const Text('Uruchom na GitHub'),
        ),
    ],
  );
}
