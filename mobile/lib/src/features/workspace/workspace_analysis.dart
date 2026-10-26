import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import 'workspace_data.dart';

Future<void> showWorkspaceAnalysis(
  BuildContext context, {
  required ApiClient api,
  required String teamId,
  required VoidCallback onChanged,
}) => showDialog<void>(
  context: context,
  builder: (context) =>
      _AnalysisDialog(api: api, teamId: teamId, onChanged: onChanged),
);

bool _active(WorkspaceAnalysis job) =>
    job.status == 'QUEUED' || job.status == 'RUNNING';

String _requestKey() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class _AnalysisDialog extends StatefulWidget {
  const _AnalysisDialog({
    required this.api,
    required this.teamId,
    required this.onChanged,
  });
  final ApiClient api;
  final String teamId;
  final VoidCallback onChanged;

  @override
  State<_AnalysisDialog> createState() => _AnalysisDialogState();
}

class _AnalysisDialogState extends State<_AnalysisDialog> {
  WorkspaceAnalysisInfo? _info;
  final _notified = <String>{};
  Timer? _poll;
  String? _pendingKey;
  String? _error;
  bool _loading = true;
  bool _submitting = false;

  String get _path =>
      '/workspace/teams/${Uri.encodeComponent(widget.teamId)}/analyses';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _schedule() {
    _poll?.cancel();
    if (_info?.analyses.any(_active) == true) {
      _poll = Timer(const Duration(seconds: 3), _refresh);
    }
  }

  void _notify(Iterable<WorkspaceAnalysis> jobs) {
    var changed = false;
    for (final job in jobs) {
      if (job.status == 'COMPLETED' && _notified.add(job.id)) {
        changed = true;
      }
    }
    if (changed) widget.onChanged();
  }

  Future<void> _refresh() async {
    _poll?.cancel();
    try {
      final result = parseWorkspaceAnalysisInfo(
        await widget.api.request(_path),
        teamId: widget.teamId,
      );
      if (!mounted) return;
      setState(() {
        _info = result;
        _error = null;
        _loading = false;
        if (_pendingKey != null &&
            result.analyses.any((job) => job.requestKey == _pendingKey)) {
          _pendingKey = null;
        }
      });
      _notify(result.analyses);
      _schedule();
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _start() async {
    final info = _info;
    if (info == null || !info.enabled || info.analyses.any(_active)) return;
    _poll?.cancel();
    setState(() {
      _submitting = true;
      _error = null;
      _pendingKey ??= _requestKey();
    });
    try {
      final response = await widget.api.request(
        _path,
        method: 'POST',
        data: {'requestKey': _pendingKey},
      );
      final job = parseWorkspaceAnalysis(
        response['analysis'],
        teamId: widget.teamId,
      );
      if (job.requestKey != _pendingKey) {
        throw const ApiException(
          'INVALID_WORKSPACE_RESPONSE',
          'Serwer nie potwierdził tej analizy.',
        );
      }
      if (!mounted) return;
      setState(() {
        _pendingKey = null;
        _info = (
          enabled: info.enabled,
          model: info.model,
          maximumCostMicros: info.maximumCostMicros,
          monthlyBudgetMicros: info.monthlyBudgetMicros,
          analyses: [
            job,
            ...info.analyses.where((item) => item.id != job.id),
          ].take(10).toList(),
        );
      });
      _notify([job]);
      _schedule();
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return AlertDialog(
      title: const Text('Analiza materiałów zespołu'),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Wyślemy do OpenAI opis projektu, brief, kontekst, wszystkie '
                'materiały (w tym aktualne wersje PDF), role botów i istniejące taski. '
                'Nie dodawaj sekretów do materiałów. Analiza dopisze brakujące zadania '
                'z przypisaniem i priorytetem, bez usuwania istniejących i bez startu botów.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Limit: 1 USD na analizę i 10 USD miesięcznie łącznie dla tej aplikacji '
                '(UTC, miesiąc rozpoczęcia wywołania). Wywołania poza aplikacją nie są '
                'objęte tym limitem. Nie ponawiamy płatnych wywołań automatycznie.',
              ),
              if (info != null) ...[
                const SizedBox(height: 8),
                Text('Model: ${info.model}'),
                if (!info.enabled)
                  const Text(
                    'Analiza OpenAI nie jest teraz dostępna. Nie rozpoczęto płatnego wywołania.',
                  ),
              ],
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_pendingKey != null && !_submitting)
                const Text(
                  'Nie potwierdzono zapisu. Odśwież historię albo ponów potwierdzenie '
                  'z tym samym identyfikatorem — nie utworzymy drugiego płatnego żądania.',
                ),
              for (final job in info?.analyses ?? <WorkspaceAnalysis>[])
                _AnalysisResult(job: job),
              if (info != null && info.analyses.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Brak wcześniejszych analiz tego zespołu.'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : _refresh,
          child: const Text('Odśwież historię'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Zamknij'),
        ),
        FilledButton(
          onPressed:
              _loading ||
                  _submitting ||
                  info == null ||
                  !info.enabled ||
                  info.analyses.any(_active)
              ? null
              : _start,
          child: Text(
            _submitting
                ? 'Zapisujemy…'
                : _pendingKey != null
                ? 'Ponów potwierdzenie'
                : 'Analizuj i dodaj taski',
          ),
        ),
      ],
    );
  }
}

class _AnalysisResult extends StatelessWidget {
  const _AnalysisResult({required this.job});
  final WorkspaceAnalysis job;

  @override
  Widget build(BuildContext context) {
    const labels = {
      'QUEUED': 'Oczekuje w kolejce',
      'RUNNING': 'Trwa analiza',
      'COMPLETED': 'Analiza zakończona',
      'FAILED': 'Analiza nie została zastosowana',
      'UNKNOWN': 'Nie potwierdzono rozliczenia',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              labels[job.status]!,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (_active(job)) const LinearProgressIndicator(),
            if (job.summary != null) Text(job.summary!),
            if (job.addedTaskCount != null)
              Text('Dodano tasków: ${job.addedTaskCount}'),
            if (job.errorMessage != null) Text(job.errorMessage!),
            if (job.estimatedCostMicros != null)
              Text(
                'Szacowany koszt modelu: ${(job.estimatedCostMicros! / 1000000).toStringAsFixed(6)} USD',
              ),
            if (job.reservationHeldMicros > 0)
              Text(
                'Zarezerwowany limit: ${(job.reservationHeldMicros / 1000000).toStringAsFixed(2)} USD',
              ),
            if (job.status == 'UNKNOWN')
              const Text(
                'Rezerwacja pozostaje zajęta do wyjaśnienia rozliczenia. Nie ponowiono wywołania.',
              ),
          ],
        ),
      ),
    );
  }
}
