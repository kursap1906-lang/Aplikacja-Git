import 'package:flutter/material.dart';

import '../../core/api.dart';
import 'role_catalog.dart';
import 'workspace_data.dart';
import 'workspace_shell.dart';

class WorkspaceRolesPage extends StatefulWidget {
  const WorkspaceRolesPage({
    required this.roles,
    required this.api,
    required this.onChanged,
    super.key,
  });

  final List<WorkspaceRole> roles;
  final ApiClient api;
  final VoidCallback onChanged;

  @override
  State<WorkspaceRolesPage> createState() => _WorkspaceRolesPageState();
}

class _WorkspaceRolesPageState extends State<WorkspaceRolesPage> {
  String _category = botRoleCatalog.keys.first;
  String _search = '';
  String? _selectedId;
  final _combining = <String>{};

  Future<void> _edit({
    WorkspaceRole? role,
    String? specialization,
    List<WorkspaceRole> combine = const [],
  }) async {
    final id = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _RoleEditor(
        api: widget.api,
        definition: role,
        specialization: specialization,
        combine: combine,
      ),
    );
    if (!mounted || id == null) return;
    setState(() => _selectedId = id);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final selected =
        widget.roles.where((role) => role.id == _selectedId).firstOrNull ??
        widget.roles.firstOrNull;
    final combining = widget.roles
        .where((role) => _combining.contains(role.id))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkspacePanel(
          title: 'Twoje boty',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilledButton.icon(
                onPressed: _edit,
                icon: const Icon(Icons.add),
                label: const Text('Dodaj własnego bota'),
              ),
              const SizedBox(height: 12),
              const Text(
                'To definicje ról. Zespół otrzymuje osobne instancje, rozmowy '
                'i zadania. Konto GitHub wybierasz dla instancji w zespole.',
              ),
              if (widget.roles.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Nie masz jeszcze własnych botów. Dodaj pierwszą definicję.',
                  ),
                ),
              for (final role in widget.roles)
                ListTile(
                  leading: const Icon(Icons.smart_toy),
                  title: Text(role.name),
                  subtitle: Text(role.role),
                  selected: selected?.id == role.id,
                  trailing: IconButton(
                    tooltip: 'Edytuj ${role.name}',
                    icon: const Icon(Icons.edit),
                    onPressed: () => _edit(role: role),
                  ),
                  onTap: () => setState(() => _selectedId = role.id),
                ),
            ],
          ),
        ),
        WorkspacePanel(
          title: 'Biblioteka specjalizacji',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final category in botRoleCatalog.keys)
                    ChoiceChip(
                      label: Text(category),
                      selected: _category == category,
                      onSelected: (_) => setState(() => _category = category),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(labelText: 'Wyszukaj rolę'),
                onChanged: (value) => setState(() => _search = value),
              ),
              const SizedBox(height: 10),
              const Text(
                'Specjalizacje są szablonami, nie utworzonymi botami. Wybierz i zapisz własny prompt.',
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final role in botRoleCatalog[_category]!.where(
                    (role) =>
                        role.toLowerCase().contains(_search.toLowerCase()),
                  ))
                    ActionChip(
                      label: Text(role),
                      onPressed: () => _edit(specialization: role),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (selected != null)
          WorkspacePanel(
            title: 'Profil i obowiązki bota',
            trailing: OutlinedButton.icon(
              onPressed: () => _edit(role: selected),
              icon: const Icon(Icons.edit),
              label: const Text('Edytuj profil'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selected.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(selected.role),
                const SizedBox(height: 12),
                SelectableText(selected.description),
                const SizedBox(height: 12),
                SelectableText(selected.systemPrompt),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final skill in selected.skills)
                      Chip(label: Text(skill)),
                  ],
                ),
                const Text(
                  'Specjalizacje opisują rolę; nie aktywują narzędzi ani MCP. '
                  'Edycja nie zmienia promptu istniejących instancji.',
                ),
              ],
            ),
          ),
        if (widget.roles.length >= 2)
          WorkspacePanel(
            title: 'Łączenie wielu ról w jeden profil',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final role in widget.roles)
                  CheckboxListTile(
                    dense: true,
                    title: Text(role.name),
                    value: _combining.contains(role.id),
                    onChanged: (selected) => setState(() {
                      if (selected == true) {
                        _combining.add(role.id);
                      } else {
                        _combining.remove(role.id);
                      }
                    }),
                  ),
                const Text(
                  'Powstanie nowa definicja. Nie łączymy kont, licencji ani sald.',
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: combining.length < 2
                      ? null
                      : () => _edit(combine: combining),
                  icon: const Icon(Icons.merge),
                  label: const Text('Połącz role'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _RoleEditor extends StatefulWidget {
  const _RoleEditor({
    required this.api,
    required this.definition,
    required this.specialization,
    required this.combine,
  });

  final ApiClient api;
  final WorkspaceRole? definition;
  final String? specialization;
  final List<WorkspaceRole> combine;

  @override
  State<_RoleEditor> createState() => _RoleEditorState();
}

class _RoleEditorState extends State<_RoleEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text:
        widget.definition?.name ??
        widget.specialization ??
        widget.combine.map((role) => role.name).join(' + '),
  );
  late final _role = TextEditingController(
    text:
        widget.definition?.role ??
        widget.specialization ??
        widget.combine.map((role) => role.role).join(' + '),
  );
  late final _description = TextEditingController(
    text:
        widget.definition?.description ??
        widget.combine.map((role) => role.description).join('\n\n'),
  );
  late final _prompt = TextEditingController(
    text:
        widget.definition?.systemPrompt ??
        widget.combine
            .map((role) => '${role.name}:\n${role.systemPrompt}')
            .join('\n\n'),
  );
  late final _skills = TextEditingController(
    text:
        (widget.definition?.skills ??
                widget.combine.expand((role) => role.skills).toSet().toList())
            .join('\n'),
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_name, _role, _description, _prompt, _skills]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final definition = widget.definition;
      final response = await widget.api.request(
        definition == null
            ? '/bot-definitions'
            : '/bot-definitions/${Uri.encodeComponent(definition.id)}',
        method: definition == null ? 'POST' : 'PATCH',
        data: {
          'name': _name.text.trim(),
          'role': _role.text.trim(),
          'description': _description.text.trim(),
          'systemPrompt': _prompt.text.trim(),
          'skills': _skills.text
              .split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList(),
        },
      );
      final String id;
      if (definition == null) {
        id = requireCreatedId(response, 'definition');
      } else {
        if (response['ok'] != true) {
          throw const ApiException(
            'INVALID_WORKSPACE_RESPONSE',
            'Serwer nie potwierdził zapisu definicji.',
          );
        }
        id = definition.id;
      }
      if (mounted) Navigator.pop(context, id);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label,
    int max, {
    int lines = 1,
    bool required = false,
  }) => WorkspaceTextField(
    controller: controller,
    label: label,
    maxLength: max,
    lines: lines,
    isRequired: required,
    enabled: !_saving,
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(
        widget.definition == null
            ? 'Dodaj własnego bota'
            : 'Edytuj definicję bota',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field(_name, 'Nazwa bota', 100, required: true),
                _field(_role, 'Rola i specjalizacja', 200, required: true),
                _field(_description, 'Opis obowiązków', 5000, lines: 3),
                _field(
                  _prompt,
                  'Prompt systemowy',
                  20000,
                  lines: 4,
                  required: true,
                ),
                TextFormField(
                  controller: _skills,
                  enabled: !_saving,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Specjalizacje — po jednej w wierszu',
                  ),
                  validator: (value) {
                    final skills = (value ?? '')
                        .split('\n')
                        .map((s) => s.trim())
                        .where((s) => s.isNotEmpty)
                        .toList();
                    return skills.length > 30 ||
                            skills.any((s) => s.length > 100)
                        ? 'Maksymalnie 30 specjalizacji, do 100 znaków każda.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'Zapis tworzy definicję w bazie. Nie uruchamia bota ani nie przypisuje konta GitHub.',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
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
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: const Text('Zapisz definicję'),
        ),
      ],
    ),
  );
}
