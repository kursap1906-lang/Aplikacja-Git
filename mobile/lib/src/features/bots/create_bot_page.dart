import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/providers.dart';
import '../../theme.dart';

class CreateBotPage extends ConsumerStatefulWidget {
  const CreateBotPage({super.key});

  @override
  ConsumerState<CreateBotPage> createState() => _CreateBotPageState();
}

class _CreateBotPageState extends ConsumerState<CreateBotPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _prompt = TextEditingController();
  final _stages = <_StageDraft>[_StageDraft(number: 1)];
  String? _accountId;
  String? _repositoryId;
  List<Map<String, dynamic>> _repositories = const [];
  bool _loadingRepositories = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    for (final stage in _stages) {
      stage.dispose();
    }
    super.dispose();
  }

  Future<void> _selectAccount(String? accountId) async {
    setState(() {
      _accountId = accountId;
      _repositoryId = null;
      _repositories = const [];
      _error = null;
      _loadingRepositories = accountId != null;
    });
    if (accountId == null) return;
    try {
      final response = await ref.read(apiClientProvider).request('/github/accounts/$accountId/repositories');
      final repositories = response['repositories'];
      if (!mounted) {
        return;
      }
      setState(() {
        _repositories = repositories is List
            ? repositories.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
            : const [];
        _loadingRepositories = false;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _loadingRepositories = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_accountId == null || _repositoryId == null) {
      setState(() => _error = 'Wybierz konto GitHub i repozytorium z dostępem do zapisu.');
      return;
    }
    final repository = _repositories.firstWhere((item) => item['id'] == _repositoryId);
    final stages = _stages.map((stage) => {
      'number': stage.number,
      'title': stage.title.text.trim(),
      'description': stage.description.text.trim(),
      'acceptanceCriteria': stage.criteria.text
          .split('\n')
          .map((criterion) => criterion.trim())
          .where((criterion) => criterion.isNotEmpty)
          .toList(),
    }).toList();

    if (stages.any((stage) => (stage['acceptanceCriteria'] as List).isEmpty)) {
      setState(() => _error = 'Każdy etap musi mieć co najmniej jedno kryterium akceptacji.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await ref.read(apiClientProvider).request('/bots', method: 'POST', data: {
        'name': _name.text.trim(),
        'githubAccountId': _accountId,
        'repositoryId': repository['id'],
        'repository': repository['fullName'],
        'systemPrompt': _prompt.text.trim(),
        'stages': stages,
      });
      final bot = created['bot'];
      ref.invalidate(botsProvider);
      if (!mounted) {
        return;
      }
      final id = bot is Map ? bot['id']?.toString() : null;
      if (id != null) {
        context.go('/bots/$id');
      } else {
        context.go('/dashboard');
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionDataProvider);

    return CustomScrollView(slivers: [
      const SliverPadding(
        padding: EdgeInsets.fromLTRB(26, 30, 26, 5),
        sliver: SliverToBoxAdapter(child: Text('NOWY BOT', style: TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.w700))),
      ),
      const SliverPadding(
        padding: EdgeInsets.fromLTRB(26, 0, 26, 20),
        sliver: SliverToBoxAdapter(child: Text('Konfiguracja projektu', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700))),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(26, 0, 26, 36),
        sliver: SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Form(
                key: _formKey,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _Section(title: 'Tożsamość bota', description: 'Nazwa widoczna w Twoim panelu.'),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Nazwa bota', hintText: 'np. Agent dokumentacji'),
                    validator: (value) => value == null || value.trim().isEmpty ? 'Podaj nazwę bota.' : null,
                  ),
                  const SizedBox(height: 28),
                  _Section(title: 'Konto i repozytorium', description: 'Wybierz konto z dostępem do odczytu i zapisu repozytorium.'),
                  const SizedBox(height: 12),
                  session.when(
                    data: (data) {
                      final user = data['user'];
                      final accounts = user is Map ? user['githubAccounts'] : null;
                      final values = accounts is List
                          ? accounts.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
                          : <Map<String, dynamic>>[];
                      if (values.isEmpty) {
                        return _NoAccounts(onOpen: () => context.go('/accounts'));
                      }
                      return DropdownButtonFormField<String>(
                        initialValue: _accountId,
                        decoration: const InputDecoration(labelText: 'Konto GitHub'),
                        items: [
                          for (final account in values)
                            DropdownMenuItem(
                              value: account['id'].toString(),
                              enabled: account['status'] == 'ACTIVE',
                              child: Text('@${account['login']} · ${_accountStatus(account['status'])}'),
                            ),
                        ],
                        onChanged: (accountId) => _selectAccount(accountId),
                      );
                    },
                    loading: () => const LinearProgressIndicator(),
                    error: (error, stack) => Text(error.toString(), style: const TextStyle(color: AppColors.coral)),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(_accountId),
                    initialValue: _repositoryId,
                    decoration: InputDecoration(
                      labelText: 'Repozytorium',
                      suffixIcon: _loadingRepositories
                          ? const Padding(
                              padding: EdgeInsets.all(13),
                              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : null,
                    ),
                    hint: Text(_accountId == null ? 'Najpierw połącz konto GitHub' : 'Wybierz repozytorium'),
                    items: [
                      for (final repository in _repositories.where((item) => item['canPush'] == true))
                        DropdownMenuItem(
                          value: repository['id'].toString(),
                          child: Text('${repository['fullName']} · ${repository['isPrivate'] == true ? 'prywatne' : 'publiczne'}'),
                        ),
                    ],
                    onChanged: _loadingRepositories || _repositories.isEmpty
                        ? null
                        : (value) => setState(() => _repositoryId = value),
                  ),
                  const SizedBox(height: 28),
                  _Section(title: 'Główny prompt', description: 'Wspólne wytyczne dla wszystkich etapów projektu.'),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _prompt,
                    minLines: 4,
                    maxLines: 8,
                    maxLength: 20000,
                    decoration: const InputDecoration(
                      labelText: 'Instrukcje dla agenta',
                      hintText: 'Opisz kontekst projektu, konwencje repozytorium i oczekiwane rezultaty.',
                      alignLabelWithHint: true,
                    ),
                    validator: (value) => value == null || value.trim().isEmpty ? 'Dodaj główny prompt.' : null,
                  ),
                  const SizedBox(height: 26),
                  Row(children: [
                    const Expanded(child: _Section(title: 'Etapy projektu', description: 'Każdy kolejny etap ruszy dopiero po Twojej akceptacji.')),
                    IconButton(
                      tooltip: 'Dodaj etap',
                      onPressed: _stages.length >= 30 ? null : () => setState(() => _stages.add(_StageDraft(number: _stages.length + 1))),
                      icon: const Icon(Icons.add_circle_outline_rounded),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  for (final stage in _stages)
                    _StageEditor(
                      stage: stage,
                      canRemove: _stages.length > 1,
                      onRemove: () => setState(() {
                        _stages.remove(stage);
                        for (var index = 0; index < _stages.length; index++) {
                          _stages[index].number = index + 1;
                        }
                        stage.dispose();
                      }),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.coral)),
                  ],
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _submit,
                      icon: _saving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check_rounded),
                      label: Text(_saving ? 'Zapisywanie…' : 'Utwórz bota'),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }

  String _accountStatus(Object? status) => switch (status) {
        'ACTIVE' => 'aktywne',
        'REAUTH_REQUIRED' => 'wymaga autoryzacji',
        _ => 'odłączone',
      };
}

class _StageDraft {
  _StageDraft({required this.number});
  int number;
  final title = TextEditingController();
  final description = TextEditingController();
  final criteria = TextEditingController();

  void dispose() {
    title.dispose();
    description.dispose();
    criteria.dispose();
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.description});
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(description, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      ]);
}

class _StageEditor extends StatelessWidget {
  const _StageEditor({required this.stage, required this.canRemove, required this.onRemove});

  final _StageDraft stage;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 11),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('ETAP ${stage.number}', style: const TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.w700))),
              IconButton(
                tooltip: 'Usuń etap',
                onPressed: canRemove ? onRemove : null,
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
              ),
            ]),
            TextFormField(
              controller: stage.title,
              decoration: const InputDecoration(labelText: 'Tytuł etapu'),
              validator: (value) => value == null || value.trim().isEmpty ? 'Podaj tytuł.' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: stage.description,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Opis etapu'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: stage.criteria,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Kryteria akceptacji',
                hintText: 'Jedno kryterium w wierszu',
                alignLabelWithHint: true,
              ),
            ),
          ]),
        ),
      );
}

class _NoAccounts extends StatelessWidget {
  const _NoAccounts({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.amber.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.amber.withValues(alpha: .35)),
        ),
        child: Row(children: [
          const Expanded(child: Text('Połącz konto GitHub, aby wybrać repozytorium.', style: TextStyle(color: AppColors.amber))),
          TextButton(onPressed: onOpen, child: const Text('Otwórz konta')),
        ]),
      );
}