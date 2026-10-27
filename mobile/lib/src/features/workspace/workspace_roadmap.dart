import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';

class WorkspaceRoadmap extends StatefulWidget {
  const WorkspaceRoadmap({
    required this.teamId,
    required this.api,
    required this.onSelected,
    super.key,
  });
  final String teamId;
  final ApiClient api;
  final ValueChanged<String?> onSelected;
  @override
  State<WorkspaceRoadmap> createState() => _WorkspaceRoadmapState();
}

class _WorkspaceRoadmapState extends State<WorkspaceRoadmap> {
  List<Map<String, dynamic>> _steps = [];
  List<Map<String, dynamic>> _runs = [];
  String? _version, _selected, _error;
  bool _busy = false;
  Timer? _timer;
  String get _path => '/workspace/teams/${widget.teamId}/roadmap';
  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_busy) _load();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final response = await widget.api.request(_path);
      if (response['roadmap'] is! List ||
          response['version'] is! String ||
          response['executions'] is! List) {
        throw const ApiException(
          'INVALID_WORKSPACE_RESPONSE',
          'Nieprawidłowa Road Map.',
        );
      }
      if (!mounted) return;
      setState(() {
        _steps = (response['roadmap'] as List)
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList();
        _runs = (response['executions'] as List)
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList();
        _version = response['version'] as String;
        _error = null;
      });
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _save(List<Map<String, dynamic>> steps) async {
    setState(() => _busy = true);
    try {
      await widget.api.request(
        _path,
        method: 'PUT',
        data: {'version': _version, 'roadmap': steps},
      );
      await _load();
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () =>
              _error = '$error\nNie nadpisano planu. Wczytaj aktualną wersję.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? step]) async {
    final title = TextEditingController(text: step?['title'] as String? ?? '');
    final description = TextEditingController(
      text: step?['description'] as String? ?? '',
    );
    final date = TextEditingController(text: step?['dueDate'] as String? ?? '');
    final fields = TextEditingController(
      text: jsonEncode(step?['fields'] ?? {}),
    );
    String? error;
    final dialog = DialogRoute<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(step == null ? 'Dodaj etap Road Map' : 'Edytuj etap'),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Nazwa etapu, np. Ekran logowania',
                    ),
                  ),
                  TextField(
                    controller: description,
                    minLines: 3,
                    maxLines: 8,
                    maxLength: 10000,
                    decoration: const InputDecoration(
                      labelText: 'Zakres i kryteria akceptacji dla lidera',
                    ),
                  ),
                  TextField(
                    controller: date,
                    decoration: const InputDecoration(
                      labelText: 'Termin ukończenia YYYY-MM-DD (opcjonalny)',
                    ),
                  ),
                  TextField(
                    controller: fields,
                    minLines: 2,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Własne pola JSON, np. {"Priorytet":"Wysoki","Odbiorca":"Ekipa"}',
                    ),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  final custom = jsonDecode(fields.text);
                  final parsedDate = date.text.trim().isEmpty
                      ? null
                      : DateTime.tryParse(date.text.trim());
                  if (title.text.trim().isEmpty ||
                      custom is! Map<String, dynamic> ||
                      custom.length > 20 ||
                      custom.entries.any(
                        (entry) =>
                            entry.key.isEmpty ||
                            entry.key.length > 80 ||
                            entry.value is! String ||
                            (entry.value as String).length > 2000,
                      ) ||
                      date.text.trim().isNotEmpty &&
                          (parsedDate == null ||
                              parsedDate.toIso8601String().substring(0, 10) !=
                                  date.text.trim())) {
                    update(
                      () => error = 'Podaj nazwę, prawidłowy termin i maks. 20 pól tekstowych w JSON.',
                    );
                    return;
                  }
                  Navigator.pop(context, <String, dynamic>{
                    'id':
                        step?['id'] ??
                        'step-${DateTime.now().microsecondsSinceEpoch}',
                    'title': title.text.trim(),
                    'description': description.text,
                    'dueDate': date.text.trim().isEmpty
                        ? null
                        : date.text.trim(),
                    'fields': custom,
                    'status': step?['status'] ?? 'PLANNED',
                  });
                } on FormatException {
                  update(
                    () => error = 'Własne pola muszą być poprawnym obiektem JSON z wartościami tekstowymi.',
                  );
                }
              },
              child: const Text('Zapisz etap'),
            ),
          ],
        ),
      ),
    );
    final result = await Navigator.of(context).push(dialog);
    await dialog.completed;
    title.dispose();
    description.dispose();
    date.dispose();
    fields.dispose();
    if (result == null || !mounted) return;
    await _save([
      for (final current in _steps)
        if (current['id'] == result['id']) result else current,
      if (step == null) result,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _steps
        .where((step) => step['id'] == _selected)
        .firstOrNull;
    final run = _runs
        .where((run) => run['milestoneId'] == _selected)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Road Map',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton(
              onPressed: _busy ? null : _load,
              tooltip: 'Wczytaj Road Map',
              icon: const Icon(Icons.refresh),
            ),
            FilledButton.tonalIcon(
              onPressed: _busy || _version == null ? null : () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Dodaj etap'),
            ),
          ],
        ),
        const Text(
          '1. Zaplanuj etapy → 2. Kliknij punkt i uruchom lidera → 3. Boty realizują zadania na wspólnej gałęzi → 4. Przetestuj i zatwierdź cały etap. Terminy i własne pola są edytowalne przed startem.',
        ),
        if (_error != null)
          SelectableText(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_steps.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Zacznij od dodania pierwszego etapu, np. Ekran logowania. Nie uruchomiono żadnych botów.',
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (index, step) in _steps.indexed) ...[
                if (index > 0)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.arrow_forward),
                  ),
                SizedBox(
                  width: 230,
                  child: Card(
                    color: step['id'] == _selected
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    child: InkWell(
                      onTap: () {
                        setState(() => _selected = step['id'] as String);
                        widget.onSelected(_selected);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            Icon(
                              step['status'] == 'APPROVED'
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                            ),
                            Text(
                              '${index + 1}. ${step['title']}',
                              textAlign: TextAlign.center,
                            ),
                            Text(
                              'Termin: ${step['dueDate'] ?? 'nie ustalono'}',
                            ),
                            Text(
                              step['status'] == 'APPROVED'
                                  ? 'Zatwierdzony'
                                  : 'Do realizacji',
                            ),
                            if (step['status'] != 'APPROVED')
                              Wrap(
                                children: [
                                  IconButton(
                                    onPressed: _busy ? null : () => _edit(step),
                                    tooltip: 'Edytuj etap',
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    onPressed:
                                        _busy ||
                                            index == 0 ||
                                            _steps[index - 1]['status'] ==
                                                'APPROVED'
                                        ? null
                                        : () {
                                            final reordered = [..._steps];
                                            final previous =
                                                reordered[index - 1];
                                            reordered[index - 1] =
                                                reordered[index];
                                            reordered[index] = previous;
                                            _save(reordered);
                                          },
                                    tooltip: 'Przenieś wcześniej',
                                    icon: const Icon(Icons.arrow_back),
                                  ),
                                  IconButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _save(
                                            _steps
                                                .where(
                                                  (current) =>
                                                      current['id'] !=
                                                      step['id'],
                                                )
                                                .toList(),
                                          ),
                                    tooltip: 'Usuń planowany etap',
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (selected != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Etap: ${selected['title']}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  SelectableText(selected['description'] as String),
                  for (final entry in (selected['fields'] as Map).entries)
                    Text('${entry.key}: ${entry.value}'),
                  if (run != null) ...[
                    SelectableText('Wspólna gałąź: ${run['leaderBranch']}'),
                    for (final (index, item) in (run['items'] as List).indexed)
                      ListTile(
                        leading: CircleAvatar(child: Text('${index + 1}')),
                        title: Text(item['title'] as String),
                        subtitle: Text(
                          'Bot: ${item['botId']} · ${item['state']}',
                        ),
                      ),
                  ] else
                    const Text(
                      'Zadania i kolejność przygotuje lider po uruchomieniu etapu.',
                    ),
                ],
              ),
            ),
          ),
        const Divider(),
      ],
    );
  }
}
