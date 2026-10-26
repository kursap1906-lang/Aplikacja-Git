import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import 'workspace_data.dart';
import 'workspace_shell.dart';
import 'workspace_dashboard.dart';

class WorkspaceCostsPage extends StatefulWidget {
  const WorkspaceCostsPage({required this.api, super.key});
  final ApiClient api;

  @override
  State<WorkspaceCostsPage> createState() => _WorkspaceCostsPageState();
}

class _WorkspaceCostsPageState extends State<WorkspaceCostsPage> {
  final _limit = TextEditingController(text: '0.00');
  WorkspaceCosts? _data;
  String? _version;
  String? _error;
  String? _notice;
  Timer? _poll;
  bool _dirty = false;
  bool _loading = true;
  bool _saving = false;
  String? _refreshing;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _limit.dispose();
    super.dispose();
  }

  void _setPolicy(WorkspaceSdkPolicy? policy) {
    _version = policy?.updatedAt;
    _limit.text = ((policy?.monthlyExtraLimitMinor ?? 0) / 100).toStringAsFixed(
      2,
    );
    _dirty = false;
  }

  void _schedule() {
    _poll?.cancel();
    if (_data?.accounts.any(
          (account) =>
              account.refreshStatus == 'QUEUED' ||
              account.refreshStatus == 'RUNNING',
        ) ==
        true) {
      _poll = Timer(const Duration(seconds: 3), _load);
    }
  }

  Future<void> _load({bool reloadPolicy = false}) async {
    _poll?.cancel();
    final generation = ++_loadGeneration;
    final draft = _limit.text;
    try {
      final data = parseWorkspaceCosts(
        await widget.api.request('/workspace/costs'),
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
        if (!_saving && (!_dirty || (reloadPolicy && _limit.text == draft))) {
          _setPolicy(data.sdkPolicy);
        }
      });
      _schedule();
    } on Exception catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _savedPolicy() async {
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Wczytać zapisany limit?'),
          content: const Text(
            'Niezapisana kwota z formularza zostanie odrzucona.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Wczytaj'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    await _load(reloadPolicy: true);
  }

  Future<void> _save() async {
    final text = _limit.text.trim().replaceAll(',', '.');
    if (!RegExp(r'^(?:0|[1-9]\d{0,4})(?:\.\d{1,2})?$').hasMatch(text)) {
      setState(
        () => _error =
            'Podaj kwotę USD z maksymalnie dwoma miejscami po przecinku.',
      );
      return;
    }
    final parts = text.split('.');
    final amount =
        int.parse(parts[0]) * 100 +
        (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
    if (amount > 1000000) {
      setState(
        () => _error = 'Limit musi mieścić się w zakresie 0–10 000 USD.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    _loadGeneration++;
    _poll?.cancel();
    try {
      final response = await widget.api.request(
        '/workspace/costs/sdk-policy',
        method: 'POST',
        data: {'monthlyExtraLimitMinor': amount, 'updatedAt': _version},
      );
      final policy = parseWorkspaceSdkPolicy(response['policy']);
      if (policy.monthlyExtraLimitMinor != amount) {
        throw const ApiException(
          'INVALID_WORKSPACE_RESPONSE',
          'Serwer nie potwierdził podanej kwoty.',
        );
      }
      if (!mounted) return;
      setState(() {
        _setPolicy(policy);
        _notice = 'Zapisano limit dodatkowych wydatków GitHub Copilot.';
      });
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        _schedule();
      }
    }
  }

  Future<void> _refresh(WorkspaceCreditAccount account) async {
    setState(() {
      _refreshing = account.id;
      _error = null;
    });
    try {
      final response = await widget.api.request(
        '/workspace/github-accounts/${Uri.encodeComponent(account.id)}/sdk-metadata',
        method: 'POST',
      );
      if (!{'QUEUED', 'RUNNING'}.contains(response['status'])) {
        throw const ApiException(
          'INVALID_WORKSPACE_RESPONSE',
          'Serwer nie potwierdził odczytu kredytów.',
        );
      }
      if (mounted) await _load();
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _refreshing = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkspacePanel(
          title: 'Koszty i kredyty',
          trailing: IconButton(
            tooltip: 'Odśwież koszty',
            onPressed: _saving ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'GitHub Copilot korzysta z subskrypcji konta przypisanego do bota. '
                'Zadania wykonuje GitHub Agents; odczyt pakietów SDK jest osobną funkcją. OpenAI do analiz ma osobne rozliczenie.',
              ),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_notice != null) Text(_notice!),
            ],
          ),
        ),
        if (data != null) ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 650
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: width,
                    child: WorkspaceMetricCard(
                      title: 'Twoje konta GitHub',
                      value: '${data.accounts.length}',
                      subtitle:
                          '${data.accounts.where((account) => account.quotaKnown).length} z odczytanym raportem pakietów',
                      icon: Icons.account_tree_outlined,
                      color: Colors.indigo,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: WorkspaceMetricCard(
                      title: 'OpenAI · rozliczone analizy',
                      value:
                          '${(data.aiSpentMicros / 1000000).toStringAsFixed(4)} USD',
                      subtitle:
                          '${(data.aiReservedMicros / 1000000).toStringAsFixed(2)} USD zajętych rezerwacji · ${data.aiMonth}',
                      icon: Icons.auto_awesome_outlined,
                      color: Colors.teal,
                    ),
                  ),
                ],
              );
            },
          ),
          WorkspacePanel(
            title: 'Limit dodatkowych wydatków GitHub Copilot',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (data.sdkPolicy == null && _version == null)
                  const Text(
                    'Nie zapisano jeszcze polityki kosztów SDK. Kwota 0 w formularzu to propozycja, nie odczytane saldo.',
                  ),
                TextField(
                  controller: _limit,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Miesięczny limit dopłat (USD)',
                    helperText:
                        '0 = brak zgody na dopłaty poza pakietem subskrypcji.',
                  ),
                  onChanged: (_) => setState(() {
                    _dirty = true;
                    _notice = null;
                  }),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Limit aplikacji nie zmienia ustawień rozliczeń GitHuba. '
                  'Zabezpiecz również limit wydatków na koncie GitHub. '
                  'Nie przeliczamy nieznanego salda AI Credits na wymyśloną kwotę USD.',
                ),
                if (!data.sdkExecutionAvailable)
                  const Text(
                    'Lokalny wykonawca SDK jest wyłączony. Boty uruchamiasz ręcznie na GitHub. Ten zapis jest polityką panelu i nie zmienia limitów rozliczeń u dostawcy.',
                  ),
                Wrap(
                  spacing: 12,
                  children: [
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: const Text('Zapisz limit SDK'),
                    ),
                    TextButton(
                      onPressed: _saving ? null : _savedPolicy,
                      child: const Text('Wczytaj zapisany limit'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          WorkspacePanel(
            title: 'Pakiety i kredyty kont GitHub',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'To odczyt raportu GitHub dla całego konta, również użycia poza tą aplikacją. '
                  'Brak danych nie oznacza salda zero. Odczyt nie uruchamia rozmowy z botem.',
                ),
                if (!data.metadataEnabled)
                  const Text(
                    'Usługa odczytu kredytów nie jest jeszcze włączona.',
                  ),
                if (data.accounts.isEmpty)
                  const Text('Nie masz podłączonych kont GitHub.'),
                for (final account in data.accounts)
                  _account(account, data.metadataEnabled),
              ],
            ),
          ),
          WorkspacePanel(
            title: 'Analizy OpenAI — ${data.aiMonth} (UTC)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Model: ${data.aiModel}'),
                const Text(
                  'Limit: 1 USD na analizę i 10 USD miesięcznie łącznie dla całej aplikacji.',
                ),
                Text(
                  'Twoje rozliczone analizy: ${(data.aiSpentMicros / 1000000).toStringAsFixed(6)} USD',
                ),
                Text(
                  'Twoje zajęte rezerwacje: ${(data.aiReservedMicros / 1000000).toStringAsFixed(6)} USD',
                ),
                const Text(
                  'Kwoty są estymacją cen tokenów, nie fakturą ani saldem konta OpenAI.',
                ),
                if (data.aiUnknownCount > 0)
                  Text(
                    'Niepotwierdzone rozliczenia: ${data.aiUnknownCount}. Ich rezerwacje pozostają zajęte; brak automatycznego ponowienia.',
                  ),
                if (data.aiRecent.isEmpty)
                  const Text('Brak zapisanych analiz.'),
                for (final job in data.aiRecent)
                  ListTile(
                    dense: true,
                    title: Text('${_kind(job.kind)} · ${job.status}'),
                    subtitle: Text(
                      job.costMicros == null
                          ? 'Koszt niepotwierdzony'
                          : '${(job.costMicros! / 1000000).toStringAsFixed(6)} USD',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _account(WorkspaceCreditAccount account, bool enabled) {
    final pending = {'QUEUED', 'RUNNING'}.contains(account.refreshStatus);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.indigo.withValues(alpha: .1),
                  child: Text(
                    account.login.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '@${account.login}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: Text(
                    account.active ? 'Aktywne konto' : 'Połącz ponownie',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!account.active)
              const Text('Konto wymaga ponownego połączenia.'),
            if (account.fetchedAt != null)
              Text('Ostatni odczyt: ${account.fetchedAt}'),
            if (pending) ...[
              const LinearProgressIndicator(),
              const Text('Trwa odczyt metadanych GitHub…'),
            ],
            if (account.errorMessage != null)
              Text('Odczyt nie powiódł się: ${account.errorMessage}'),
            if (!account.quotaKnown)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.help_outline, color: Colors.blueGrey),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Nie pobrano jeszcze danych pakietu.'),
                    ),
                  ],
                ),
              ),
            if (account.quotaKnown && account.quotas.isEmpty)
              const Text('GitHub nie udostępnił danych o limitach pakietu.'),
            if (account.autoAvailable == false)
              const Text('GitHub nie udostępnia trybu Auto na tym koncie.'),
            for (final quota in account.quotas) ...[
              const Divider(),
              Text('Pakiet: ${quota.name}'),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 76,
                    height: 76,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox.expand(
                          child: CircularProgressIndicator(
                            key: ValueKey(
                              'quota-ring-${account.id}-${quota.name}',
                            ),
                            value: quota.unlimited
                                ? 1
                                : (quota.remainingPercentage / 100)
                                      .clamp(0, 1)
                                      .toDouble(),
                            strokeWidth: 7,
                            backgroundColor: Colors.indigo.withValues(
                              alpha: .1,
                            ),
                            color:
                                quota.remainingPercentage <= 10 &&
                                    !quota.unlimited
                                ? Colors.orange
                                : Colors.indigo,
                          ),
                        ),
                        Text(
                          quota.unlimited
                              ? '∞'
                              : '${quota.remainingPercentage.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          quota.unlimited
                              ? 'Bez limitu'
                              : 'Pozostało w pakiecie',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          key: ValueKey(
                            'quota-bar-${account.id}-${quota.name}',
                          ),
                          value: quota.unlimited
                              ? 1
                              : (quota.remainingPercentage / 100)
                                    .clamp(0, 1)
                                    .toDouble(),
                          minHeight: 10,
                          borderRadius: BorderRadius.circular(8),
                          color:
                              quota.remainingPercentage <= 10 &&
                                  !quota.unlimited
                              ? Colors.orange
                              : Colors.indigo,
                          backgroundColor: Colors.indigo.withValues(alpha: .1),
                          semanticsLabel:
                              '${account.login} · ${quota.name} · pozostało',
                          semanticsValue: quota.unlimited
                              ? 'bez limitu'
                              : '${quota.remainingPercentage}%',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                quota.unlimited
                    ? 'Uprawnienie dla tego pakietu: bez limitu'
                    : 'W pakiecie: ${quota.entitlement} · wykorzystano: ${quota.used}',
              ),
              Text(
                'Pozostało: ${quota.remainingPercentage.toStringAsFixed(1)}% · użycie poza pakietem: ${quota.overage}',
              ),
              if (quota.resetDate != null)
                Text('Odnowienie: ${quota.resetDate}'),
              Text(
                quota.overageAllowed
                    ? 'Uwaga: GitHub dopuszcza dopłaty po wyczerpaniu tego pakietu.'
                    : 'GitHub nie dopuszcza dopłat po wyczerpaniu tego pakietu.',
              ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed:
                    !enabled ||
                        !account.active ||
                        pending ||
                        _refreshing != null ||
                        _saving
                    ? null
                    : () => _refresh(account),
                icon: const Icon(Icons.refresh),
                label: const Text('Pobierz pakiet z GitHub'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _kind(String kind) => switch (kind) {
  'DIAGNOSTIC' => 'Test syntetyczny',
  'TEAM_TASKS' => 'Plan tasków',
  'REPOSITORY_CONTEXT' => 'Kontekst repozytorium',
  _ => kind,
};
