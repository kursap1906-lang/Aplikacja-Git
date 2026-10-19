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
  int _currentStep = 0;
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
      final response = await ref
          .read(apiClientProvider)
          .request('/github/accounts/$accountId/repositories');
      final repositories = response['repositories'];
      if (!mounted) {
        return;
      }
      setState(() {
        _repositories = repositories is List
            ? repositories
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
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
      setState(
        () => _error =
            'Wybierz konto GitHub i repozytorium z dostępem do zapisu.',
      );
      return;
    }
    final repository = _repositories.firstWhere(
      (item) => item['id'] == _repositoryId,
    );
    final stages = _stages
        .map(
          (stage) => {
            'number': stage.number,
            'title': stage.title.text.trim(),
            'description': stage.description.text.trim(),
            'acceptanceCriteria': stage.criteria.text
                .split('\n')
                .map((criterion) => criterion.trim())
                .where((criterion) => criterion.isNotEmpty)
                .toList(),
          },
        )
        .toList();

    if (stages.any((stage) => (stage['acceptanceCriteria'] as List).isEmpty)) {
      setState(
        () => _error =
            'Każdy etap musi mieć co najmniej jedno kryterium akceptacji.',
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await ref
          .read(apiClientProvider)
          .request(
            '/bots',
            method: 'POST',
            data: {
              'name': _name.text.trim(),
              'githubAccountId': _accountId,
              'repositoryId': repository['id'],
              'repository': repository['fullName'],
              'systemPrompt': _prompt.text.trim(),
              'stages': stages,
            },
          );
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
    final accounts = session.when(
      data: (data) {
        final user = data['user'];
        final values = user is Map ? user['githubAccounts'] : null;
        return values is List
            ? values
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
            : <Map<String, dynamic>>[];
      },
      loading: () => <Map<String, dynamic>>[],
      error: (error, stack) => <Map<String, dynamic>>[],
    );
    final writableRepositories = _repositories
        .where((item) => item['canPush'] == true)
        .toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 600 ? 18.0 : 28.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            28,
            horizontalPadding,
            36,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'NOWY BOT',
                    style: TextStyle(
                      color: AppColors.blue,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'Stwórz swojego agenta',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Odpowiedz na kilka pytań, wybierz repozytorium i opisz, co bot ma zrobić.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 26),
                  _WizardProgress(currentStep: _currentStep),
                  const SizedBox(height: 22),
                  Form(
                    key: _formKey,
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(
                          constraints.maxWidth < 600 ? 16 : 24,
                        ),
                        child: _buildStep(
                          context,
                          session: session,
                          accounts: accounts,
                          writableRepositories: writableRepositories,
                        ),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.coral.withValues(alpha: .08),
                        border: Border.all(
                          color: AppColors.coral.withValues(alpha: .45),
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: AppColors.coral,
                            size: 19,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(color: AppColors.coral),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      if (_currentStep > 0)
                        OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => setState(() {
                                  _currentStep--;
                                  _error = null;
                                }),
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: const Text('Wstecz'),
                        )
                      else
                        TextButton.icon(
                          onPressed: _saving
                              ? null
                              : () => context.go('/dashboard'),
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('Anuluj'),
                        ),
                      const Spacer(),
                      if (_currentStep < 2)
                        FilledButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _continueStep(accounts),
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: const Text('Dalej'),
                        )
                      else
                        FilledButton.icon(
                          onPressed: _saving ? null : _submit,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check_rounded),
                          label: Text(
                            _saving ? 'Tworzenie bota…' : 'Utwórz bota',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStep(
    BuildContext context, {
    required AsyncValue<Map<String, dynamic>> session,
    required List<Map<String, dynamic>> accounts,
    required List<Map<String, dynamic>> writableRepositories,
  }) {
    return switch (_currentStep) {
      0 => _buildIdentityStep(context, session, accounts, writableRepositories),
      1 => _buildPromptStep(),
      _ => _buildStagesStep(),
    };
  }

  Widget _buildIdentityStep(
    BuildContext context,
    AsyncValue<Map<String, dynamic>> session,
    List<Map<String, dynamic>> accounts,
    List<Map<String, dynamic>> writableRepositories,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _QuestionHeading(
          number: '01',
          title: 'Podstawowe informacje',
          description: 'Najpierw nazwij bota i wskaż konto oraz repozytorium, nad którym będzie pracował.',
        ),
        const SizedBox(height: 22),
        const _FieldLabel(number: '1', title: 'Jak ma nazywać się bot?'),
        const SizedBox(height: 9),
        TextFormField(
          controller: _name,
          decoration: const InputDecoration(
            hintText: 'np. Agent dokumentacji',
            prefixIcon: Icon(Icons.smart_toy_outlined),
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Wpisz nazwę bota, aby przejść dalej.'
              : null,
        ),
        const SizedBox(height: 22),
        const _FieldLabel(
          number: '2',
          title: 'Z którego konta GitHub ma korzystać?',
        ),
        const SizedBox(height: 9),
        session.when(
          data: (_) => accounts.isEmpty
              ? _NoAccounts(onOpen: () => context.go('/accounts'))
              : DropdownButtonFormField<String>(
                  key: ValueKey('account-$_accountId'),
                  initialValue: _accountId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    hintText: 'Wybierz połączone konto',
                    prefixIcon: Icon(Icons.account_circle_outlined),
                  ),
                  items: [
                    for (final account in accounts)
                      DropdownMenuItem(
                        value: account['id'].toString(),
                        enabled: account['status'] == 'ACTIVE',
                        child: Text(
                          '@${account['login']} · ${_accountStatus(account['status'])}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _selectAccount,
                ),
          loading: () => const LinearProgressIndicator(),
          error: (error, stack) => Text(
            'Nie udało się wczytać kont: $error',
            style: const TextStyle(color: AppColors.coral),
          ),
        ),
        const SizedBox(height: 22),
        const _FieldLabel(
          number: '3',
          title: 'Które repozytorium ma obsługiwać bot?',
        ),
        const SizedBox(height: 9),
        DropdownButtonFormField<String>(
          key: ValueKey('repository-$_accountId-$_repositoryId'),
          initialValue: _repositoryId,
          isExpanded: true,
          decoration: InputDecoration(
            hintText: _accountId == null
                ? 'Najpierw wybierz konto GitHub'
                : 'Wybierz repozytorium',
            prefixIcon: const Icon(Icons.folder_open_outlined),
            suffixIcon: _loadingRepositories
                ? const Padding(
                    padding: EdgeInsets.all(13),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
          items: [
            for (final repository in writableRepositories)
              DropdownMenuItem(
                value: repository['id'].toString(),
                child: Text(
                  '${repository['fullName']} · ${repository['isPrivate'] == true ? 'prywatne' : 'publiczne'}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _loadingRepositories || writableRepositories.isEmpty
              ? null
              : (value) => setState(() {
                  _repositoryId = value;
                  _error = null;
                }),
        ),
        if (_accountId != null &&
            !_loadingRepositories &&
            writableRepositories.isEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            'Nie znaleziono repozytoriów z dostępem do zapisu dla tego konta.',
            style: TextStyle(color: AppColors.amber, fontSize: 12),
          ),
        ],
        if (_accountId == null && accounts.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            'Bot może pracować tylko w repozytorium, do którego konto ma dostęp zapisu.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _buildPromptStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _QuestionHeading(
          number: '02',
          title: 'Opisz zadanie i zasady',
          description:
              'Te wytyczne będą dołączane do każdego etapu pracy agenta.',
        ),
        const SizedBox(height: 22),
        const _FieldLabel(
          number: '4',
          title: 'Co bot powinien wiedzieć o projekcie i jak ma pracować?',
        ),
        const SizedBox(height: 9),
        TextFormField(
          controller: _prompt,
          minLines: 5,
          maxLines: 9,
          maxLength: 20000,
          decoration: const InputDecoration(
            hintText: 'Np. opisz cel projektu, używany język i framework, konwencje kodu, ważne ograniczenia oraz czego bot ma unikać.',
            alignLabelWithHint: true,
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Opisz instrukcje dla agenta.'
              : null,
        ),
        const SizedBox(height: 10),
        const _TipCard(
          icon: Icons.lightbulb_outline_rounded,
          text: 'Dobre instrukcje są konkretne: opisz oczekiwany rezultat, ograniczenia i sposób weryfikacji zmian.',
        ),
      ],
    );
  }

  Widget _buildStagesStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: _QuestionHeading(
                number: '03',
                title: 'Podziel pracę na etapy',
                description: 'Zdefiniuj, co agent ma zrobić i po czym poznasz, że etap jest gotowy.',
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Dodaj etap',
              onPressed: _stages.length >= 30
                  ? null
                  : () => setState(
                      () =>
                          _stages.add(_StageDraft(number: _stages.length + 1)),
                    ),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        const SizedBox(height: 18),
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
        const SizedBox(height: 8),
        _SummaryCard(
          name: _name.text.trim().isEmpty ? '—' : _name.text.trim(),
          repository: _selectedRepositoryName(),
          stageCount: _stages.length,
        ),
      ],
    );
  }

  String _selectedRepositoryName() {
    for (final repository in _repositories) {
      if (repository['id'].toString() == _repositoryId) {
        return repository['fullName']?.toString() ?? '—';
      }
    }
    return '—';
  }

  void _continueStep(List<Map<String, dynamic>> accounts) {
    if (!_formKey.currentState!.validate()) return;
    if (_currentStep == 0) {
      final activeAccount = accounts.any(
        (account) =>
            account['id'].toString() == _accountId &&
            account['status'] == 'ACTIVE',
      );
      if (!activeAccount || _repositoryId == null) {
        setState(
          () => _error = 'Wybierz aktywne konto GitHub i repozytorium z dostępem do zapisu.',
        );
        return;
      }
    }
    setState(() {
      _currentStep++;
      _error = null;
    });
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

class _WizardProgress extends StatelessWidget {
  const _WizardProgress({required this.currentStep});

  final int currentStep;

  static const _labels = ['Bot i repozytorium', 'Zadanie', 'Etapy'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < _labels.length; index++) ...[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: index <= currentStep
                            ? AppColors.blue
                            : AppColors.panelRaised,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: index <= currentStep
                              ? AppColors.blue
                              : AppColors.stroke,
                        ),
                      ),
                      child: index < currentStep
                          ? const Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: AppColors.canvas,
                            )
                          : Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: index == currentStep
                                    ? AppColors.canvas
                                    : AppColors.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                    if (index < _labels.length - 1)
                      Expanded(
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          color: index < currentStep
                              ? AppColors.blue
                              : AppColors.stroke,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  _labels[index],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: index == currentStep
                        ? AppColors.foreground
                        : AppColors.muted,
                    fontSize: 11,
                    fontWeight: index == currentStep
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _QuestionHeading extends StatelessWidget {
  const _QuestionHeading({
    required this.number,
    required this.title,
    required this.description,
  });

  final String number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.blue.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          number,
          style: const TextStyle(
            color: AppColors.blue,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(width: 13),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              description,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.number, required this.title});

  final String number;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.panelRaised,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          number,
          style: const TextStyle(
            color: AppColors.blue,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}

class _TipCard extends StatelessWidget {
  const _TipCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: AppColors.blue.withValues(alpha: .07),
      border: Border.all(color: AppColors.blue.withValues(alpha: .2)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.blue),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.name,
    required this.repository,
    required this.stageCount,
  });

  final String name;
  final String repository;
  final int stageCount;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: AppColors.panelRaised.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.stroke),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PODSUMOWANIE',
          style: TextStyle(
            color: AppColors.blue,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
        _SummaryLine(icon: Icons.smart_toy_outlined, label: name),
        const SizedBox(height: 7),
        _SummaryLine(icon: Icons.folder_outlined, label: repository),
        const SizedBox(height: 7),
        _SummaryLine(
          icon: Icons.account_tree_outlined,
          label: '$stageCount ${stageCount == 1 ? 'etap' : 'etapy'}',
        ),
      ],
    ),
  );
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: AppColors.muted),
      const SizedBox(width: 8),
      Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
    ],
  );
}

class _StageEditor extends StatelessWidget {
  const _StageEditor({
    required this.stage,
    required this.canRemove,
    required this.onRemove,
  });

  final _StageDraft stage;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 11),
    child: Padding(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'ETAP ${stage.number}',
                  style: const TextStyle(
                    color: AppColors.blue,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Usuń etap',
                onPressed: canRemove ? onRemove : null,
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
              ),
            ],
          ),
          TextFormField(
            controller: stage.title,
            decoration: const InputDecoration(labelText: 'Tytuł etapu'),
            validator: (value) =>
                value == null || value.trim().isEmpty ? 'Podaj tytuł.' : null,
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
        ],
      ),
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
    child: Row(
      children: [
        const Expanded(
          child: Text(
            'Połącz konto GitHub, aby wybrać repozytorium.',
            style: TextStyle(color: AppColors.amber),
          ),
        ),
        TextButton(onPressed: onOpen, child: const Text('Otwórz konta')),
      ],
    ),
  );
}
