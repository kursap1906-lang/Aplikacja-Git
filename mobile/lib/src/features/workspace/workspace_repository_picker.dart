import 'package:flutter/material.dart';

import '../../core/api.dart';
import 'workspace_data.dart';

typedef WorkspaceRepositorySelection = ({String accountId, String repository});

class WorkspaceRepositoryPicker extends StatefulWidget {
  const WorkspaceRepositoryPicker({
    required this.api,
    required this.accounts,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final ApiClient api;
  final List<WorkspaceAccount> accounts;
  final ValueChanged<WorkspaceRepositorySelection?> onChanged;
  final bool enabled;

  @override
  State<WorkspaceRepositoryPicker> createState() =>
      _WorkspaceRepositoryPickerState();
}

class _WorkspaceRepositoryPickerState extends State<WorkspaceRepositoryPicker> {
  String? _accountId;
  String? _repositoryId;
  List<WorkspaceRepository> _repositories = [];
  int? _nextPage;
  int _generation = 0;
  int _failedPage = 1;
  bool _loading = false;
  String? _error;

  Future<void> _load(int page) async {
    final accountId = _accountId;
    if (accountId == null) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _failedPage = page;
    });
    try {
      final result = await loadWorkspaceRepositoryPage(
        widget.api,
        accountId,
        page: page,
      );
      if (!mounted || generation != _generation) return;
      final repositories = <String, WorkspaceRepository>{
        if (page > 1)
          for (final repository in _repositories) repository.id: repository,
        for (final repository in result.repositories) repository.id: repository,
      };
      setState(() {
        _repositories = repositories.values.toList();
        _nextPage = result.nextPage;
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

  void _accountChanged(String? id) {
    setState(() {
      _accountId = id;
      _repositoryId = null;
      _repositories = [];
      _nextPage = null;
      _error = null;
      ++_generation;
    });
    widget.onChanged(null);
    if (id != null) _load(1);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = widget.accounts
        .where((account) => account.active)
        .toList();
    if (accounts.isEmpty) {
      return const Text(
        'Najpierw połącz aktywne konto GitHub. Repozytoria nie są pobierane z kont demonstracyjnych.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _accountId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Główne konto GitHub projektu',
          ),
          items: [
            for (final account in accounts)
              DropdownMenuItem(
                value: account.id,
                child: Text('@${account.login}'),
              ),
          ],
          onChanged: widget.enabled ? _accountChanged : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('repository-$_accountId-$_repositoryId'),
          initialValue: _repositoryId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Wspólne repozytorium'),
          items: [
            for (final repository in _repositories)
              DropdownMenuItem(
                value: repository.id,
                enabled: repository.canPush,
                child: Text(
                  '${repository.fullName}${repository.canPush ? '' : ' · tylko odczyt'}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: !widget.enabled || _loading
              ? null
              : (id) {
                  if (id == null) return;
                  final repository = _repositories.firstWhere(
                    (repository) => repository.id == id,
                  );
                  setState(() => _repositoryId = id);
                  widget.onChanged((
                    accountId: _accountId!,
                    repository: repository.fullName,
                  ));
                },
        ),
        if (_loading) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          TextButton.icon(
            onPressed: !widget.enabled || _loading
                ? null
                : () => _load(_failedPage),
            icon: const Icon(Icons.refresh),
            label: const Text('Ponów pobieranie repozytoriów'),
          ),
        ],
        if (_accountId != null &&
            !_loading &&
            _error == null &&
            _repositories.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('GitHub nie zwrócił repozytoriów dla tego konta.'),
          ),
        if (_nextPage case final next?)
          TextButton.icon(
            onPressed: !widget.enabled || _loading ? null : () => _load(next),
            icon: const Icon(Icons.expand_more),
            label: const Text('Wczytaj więcej repozytoriów'),
          ),
      ],
    );
  }
}
