import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import 'workspace_data.dart';
import 'workspace_roadmap.dart';

class WorkspaceTeamControl extends StatefulWidget {
  const WorkspaceTeamControl({
    required this.team,
    required this.api,
    required this.onChanged,
    required this.onCoordinationChanged,
    super.key,
  });
  final WorkspaceTeam team;
  final ApiClient api;
  final VoidCallback onChanged;
  final ValueChanged<bool> onCoordinationChanged;
  @override
  State<WorkspaceTeamControl> createState() => _WorkspaceTeamControlState();
}

class _WorkspaceTeamControlState extends State<WorkspaceTeamControl> {
  Timer? _timer;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _execution;
  String? _milestoneId;
  String get _path => '/workspace/teams/${widget.team.id}/execution';

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
      final execution = response['execution'];
      if (execution != null &&
          (execution is! Map<String, dynamic> ||
              execution['phase'] is! String ||
              execution['items'] is! List ||
              execution['events'] is! List)) {
        throw const ApiException(
          'INVALID_WORKSPACE_RESPONSE',
          'Nieprawidłowy stan koordynatora zespołu.',
        );
      }
      if (mounted) {
        final changed = jsonEncode(execution) != jsonEncode(_execution);
        setState(() {
          _execution = execution as Map<String, dynamic>?;
          _error = null;
        });
        final phase = _execution?['phase'];
        widget.onCoordinationChanged(
          phase != null && !['STOPPED', 'RELEASED'].contains(phase),
        );
        if (changed) widget.onChanged();
      }
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _action(
    String action,
    String confirmation, {
    Map<String, dynamic>? data,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Potwierdź działanie'),
        content: Text(confirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Potwierdzam'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.request(
        '$_path/$action',
        method: 'POST',
        data: data ?? {},
      );
      await _load();
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () =>
              _error = '$error\nSprawdź stan GitHub przed ponowieniem zapisu.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String value) async {
    final url = Uri.tryParse(value);
    if (url == null ||
        url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        !await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        setState(() => _error = 'Nie udało się otworzyć adresu HTTPS.');
      }
    }
  }

  Future<void> _reconcile(
    Map<String, dynamic> run,
    List<Map<String, dynamic>> items,
  ) async {
    final pending = items
        .where((item) => ['SUBMITTING', 'MERGING'].contains(item['state']))
        .firstOrNull;
    final key =
        pending?['key'] as String? ??
        (run['milestonePull'] != null
            ? 'milestone'
            : run['leaderTaskId'] == null
            ? 'leader'
            : 'release');
    final needsId =
        pending?['state'] != 'MERGING' &&
        !['release', 'milestone'].contains(key);
    final controller = TextEditingController();
    String? remoteId;
    if (needsId) {
      final dialog = DialogRoute<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Powiąż istniejące zadanie GitHub'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Krok: $key. Wklej ID zadania z GitHub Agents. Panel sprawdzi repozytorium i gałąź z metadanych sesji. Nie uruchomi drugiego zadania.',
              ),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'GitHub task ID'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Sprawdź ID'),
            ),
          ],
        ),
      );
      remoteId = await Navigator.of(context).push(dialog);
      await dialog.completed;
    }

    controller.dispose();
    if (!mounted || needsId && (remoteId == null || remoteId.isEmpty)) return;
    await _action(
      'reconcile',
      'Zweryfikować rzeczywiste zadanie lub wynik scalenia na GitHub i wznowić koordynację bez ponownego wysłania operacji?',
      data: {'key': key, if (needsId) 'remoteTaskId': remoteId},
    );
  }

  Future<void> _revise() async {
    final controller = TextEditingController();
    final dialog = DialogRoute<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Poprawki całego etapu'),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 8,
          maxLength: 4000,
          decoration: const InputDecoration(
            labelText: 'Co lider i zespół mają poprawić? (min. 10 znaków)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().length >= 10) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Przekaż liderowi'),
          ),
        ],
      ),
    );
    final reason = await Navigator.of(context).push(dialog);
    await dialog.completed;
    controller.dispose();
    if (reason != null && mounted) {
      await _action(
        'revise-milestone',
        'Przekazać poprawki liderowi na tej samej wspólnej gałęzi etapu?',
        data: {'reason': reason},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final run = _execution;
    final phase = run?['phase'] as String?;
    final active = phase != null && !['STOPPED', 'RELEASED'].contains(phase);
    final items = (run?['items'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final preview = run?['preview'] is Map<String, dynamic>
        ? run!['preview'] as Map<String, dynamic>
        : null;
    final events = (run?['events'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkspaceRoadmap(
          teamId: widget.team.id,
          api: widget.api,
          onSelected: (id) => setState(() => _milestoneId = id),
        ),
        Text(
          'Sterowanie zespołem',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'Wybierz etap Road Map. Lider planuje i uruchamia boty po kolei na wspólnej gałęzi; każdy czyta dokumentację i handoffy poprzedników. Ty zatwierdzasz cały etap, nie pojedyncze zadania. Statusy odświeżane automatycznie co 15 sekund.',
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          SelectableText(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _busy || active
                  ? null
                  : () => _action(
                      'start',
                      'Uruchomić cały zespół? Lider przygotuje plan i uruchomi potrzebne boty zdalnie w GitHub Agents. Sesje mogą zużywać kredyty. Zwykłe PR będą scalane na gałąź testową po review lidera i CI. Main pozostanie bez zmian.',
                      data: {
                        if (_milestoneId != null) 'milestoneId': _milestoneId,
                      },
                    ),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start zespołu'),
            ),
            OutlinedButton.icon(
              onPressed: _busy || (!active && run?['milestoneApproved'] != true)
                  ? null
                  : () => _action(
                      'preview',
                      'Zbudować aktualną aplikację z gałęzi bieżącego etapu (albo test po zatwierdzeniu) na GitHub Actions? Workflow zapisany przez programistów ma uruchomić aplikację i opublikować link do testów. Podgląd będzie publiczny. Brak konfiguracji lub hostingu zostanie pokazany jako błąd, nie jako działający podgląd.',
                    ),
              icon: const Icon(Icons.build_outlined),
              label: const Text('Kompiluj bieżącą aplikację'),
            ),
            if (preview?['success'] == true && preview?['url'] is String)
              FilledButton.tonalIcon(
                onPressed: () => _open(preview!['url'] as String),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Otwórz aplikację do testów'),
              ),
            if (preview?['buildUrl'] is String)
              TextButton(
                onPressed: () => _open(preview!['buildUrl'] as String),
                child: const Text('Logi kompilacji'),
              ),
            if (phase == 'READY' &&
                preview?['success'] == true &&
                (run?['milestoneId'] == null ||
                    run?['milestoneApproved'] == true))
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _action(
                        'release',
                        'Potwierdzasz, że przetestowałeś aplikację dla commita ${preview!['sha']} i zatwierdzasz scalenie gałęzi testowej do main? Operacja tworzy/używa PR i respektuje zabezpieczenia GitHuba.',
                        data: {'sha': preview['sha'], 'confirmed': true},
                      ),
                icon: const Icon(Icons.merge),
                label: const Text('Zatwierdź i przenieś do main'),
              ),
            if (phase == 'ERROR')
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _action(
                        'resume',
                        'Sprawdziłeś i usunąłeś przyczynę blokady na GitHub? Koordynator wznowi odczyt i pracę od zapisanego kroku. Niepotwierdzone zgłoszenia wymagają osobnego wyjaśnienia i nie będą ponawiane.',
                      ),
                child: const Text('Wznów po usunięciu blokady'),
              ),
            if (run?['milestoneId'] != null &&
                run?['milestoneApproved'] != true &&
                phase == 'READY') ...[
              FilledButton(
                onPressed: _busy || run?['milestoneSha'] == null
                    ? null
                    : () => _action(
                        'approve-milestone',
                        'Zatwierdzić cały etap i scalić jego wspólny PR na test? Main pozostanie bez zmian.',
                        data: {'sha': run!['milestoneSha'], 'confirmed': true},
                      ),
                child: const Text('Zatwierdź cały etap'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _revise,
                child: const Text('Wprowadź poprawki etapu'),
              ),
            ],
            if (active)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _action(
                        'stop',
                        'Zatrzymać koordynatora? Już wysłane zadania nie są automatycznie anulowane. Sprawdź i zakończ je w GitHub Agents przed nowym uruchomieniem.',
                      ),
                child: const Text('Zatrzymaj koordynację'),
              ),
            if (run?['uncertain'] == true)
              OutlinedButton(
                onPressed: _busy ? null : () => _reconcile(run!, items),
                child: const Text('Wyjaśnij zapis na GitHub'),
              ),
            IconButton(
              onPressed: _busy ? null : _load,
              tooltip: 'Odśwież koordynatora',
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (run != null) ...[
          SelectableText(
            'Stan: $phase\nGałąź testowa: ${run['testBranch']}\nLider: ${widget.team.members.where((member) => member.botId == run['leaderBotId']).firstOrNull?.name ?? run['leaderBotId']}',
          ),
          if (run['error'] is String)
            SelectableText(
              run['error'] as String,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (run['planSummary'] is String)
            ExpansionTile(
              title: const Text('Plan i pokrycie wymagań lidera'),
              children: [SelectableText(run['planSummary'] as String)],
            ),
          for (final member in widget.team.members)
            Builder(
              builder: (context) {
                final assigned = items
                    .where((item) => item['botId'] == member.botId)
                    .toList();
                final completed = assigned
                    .where((item) => item['state'] == 'COMPLETED')
                    .length;
                final working = assigned.any(
                  (item) => [
                    'RUNNING',
                    'REVIEWING',
                    'SUBMITTING',
                  ].contains(item['state']),
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${member.name}: $completed/${assigned.length} zadań zakończonych${working ? ' · pracuje / review' : ''}',
                      ),
                      LinearProgressIndicator(
                        value: assigned.isEmpty
                            ? 0
                            : completed / assigned.length,
                        semanticsLabel: 'Ukończone zadania bota ${member.name}',
                      ),
                    ],
                  ),
                );
              },
            ),
          for (final item in items)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${item['title']} · ${item['state']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: item['state'] == 'COMPLETED'
                          ? 1
                          : item['state'] == 'PENDING'
                          ? 0
                          : null,
                      semanticsLabel: 'Postęp zadania ${item['title']}',
                    ),
                    Text(
                      item['state'] == 'COMPLETED'
                          ? 'Ukończone — 100%'
                          : item['state'] == 'PENDING'
                          ? 'Oczekuje — 0%'
                          : 'W toku — GitHub nie udostępnia procentu wykonania',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      'Bot: ${widget.team.members.where((member) => member.botId == item['botId']).firstOrNull?.name ?? item['botId']} · Akceptacja: ${item['approval']}',
                    ),
                    if (item['taskIdExternal'] is String)
                      SelectableText('GitHub task: ${item['taskIdExternal']}'),
                    if (item['reviewReason'] is String)
                      SelectableText(item['reviewReason'] as String),
                    if (item['pullNumber'] is int)
                      TextButton(
                        onPressed: () => _open(
                          'https://github.com/${run['repository']}/pull/${item['pullNumber']}',
                        ),
                        child: Text('Otwórz PR #${item['pullNumber']}'),
                      ),
                    if (item['state'] == 'OWNER_REVIEW' &&
                        run['milestoneId'] == null)
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _action(
                                'approve-task',
                                item['headSha'] == null
                                    ? 'Zezwolić na start zadania: ${item['title']}? Zapoznaj się z jego zakresem.'
                                    : 'Zatwierdzić PR dla SHA ${item['headSha']} i scalić na test? Main pozostaje bez zmian.',
                                data: {
                                  'key': item['key'],
                                  if (item['headSha'] != null)
                                    'sha': item['headSha'],
                                },
                              ),
                        child: Text(
                          item['headSha'] == null
                              ? 'Zezwól na start zadania'
                              : 'Zatwierdź przyrost na test',
                        ),
                      ),
                    ExpansionTile(
                      title: const Text('Szczegółowy prompt'),
                      children: [SelectableText(item['description'] as String)],
                    ),
                  ],
                ),
              ),
            ),
          ExpansionTile(
            title: const Text('Dziennik decyzji i pracy'),
            children: [
              for (final event in events.reversed)
                ListTile(
                  dense: true,
                  title: Text(event['message'] as String),
                  subtitle: Text(event['at'] as String),
                ),
            ],
          ),
        ],
        const Divider(),
      ],
    );
  }
}
