import 'package:flutter/material.dart';

import '../workspace/workspace_data.dart';

class DemoSchedulePage extends StatelessWidget {
  const DemoSchedulePage({required this.agents, super.key});

  final List<({String id, String name})> agents;

  @override
  Widget build(BuildContext context) => BotSchedulePage(agents: agents);
}

class BotSchedulePage extends StatefulWidget {
  const BotSchedulePage({
    required this.agents,
    this.schedules = const {},
    this.onSave,
    super.key,
  });

  final List<({String id, String name})> agents;
  final Map<String, WorkspaceSchedule> schedules;
  final Future<void> Function(String, WorkspaceSchedule)? onSave;

  @override
  State<BotSchedulePage> createState() => _BotSchedulePageState();
}

class _BotSchedule {
  _BotSchedule({
    required this.days,
    required this.start,
    required this.end,
    this.enabled = true,
    this.timezone = 'Europe/Warsaw',
  });

  final Set<int> days;
  final TimeOfDay start;
  final TimeOfDay end;
  bool enabled;
  final String timezone;
}

class _BotSchedulePageState extends State<BotSchedulePage> {
  static const _dayNames = [
    'Poniedziałek',
    'Wtorek',
    'Środa',
    'Czwartek',
    'Piątek',
    'Sobota',
    'Niedziela',
  ];
  final _schedules = <String, _BotSchedule>{};
  late String? _agentId = widget.agents.firstOrNull?.id;
  final _timezone = TextEditingController(text: 'Europe/Warsaw');
  Set<int> _days = {0, 1, 2, 3, 4};
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 17, minute: 0);
  bool _enabled = true;
  String? _error;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _sync();
    _read(_agentId);
  }

  @override
  void dispose() {
    _timezone.dispose();
    super.dispose();
  }

  void _sync() {
    if (widget.onSave == null) return;
    _schedules
      ..clear()
      ..addAll({
        for (final entry in widget.schedules.entries)
          entry.key: _BotSchedule(
            days: entry.value.days.map((day) => day - 1).toSet(),
            start: _parseTime(entry.value.startTime),
            end: _parseTime(entry.value.endTime),
            enabled: entry.value.enabled,
            timezone: entry.value.timezone,
          ),
      });
  }

  TimeOfDay _parseTime(String value) => TimeOfDay(
    hour: int.parse(value.split(':')[0]),
    minute: int.parse(value.split(':')[1]),
  );

  @override
  void didUpdateWidget(covariant BotSchedulePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
    if (_agentId != null &&
        !widget.agents.any((agent) => agent.id == _agentId)) {
      _agentId = null;
      _error = 'Wybrany bot nie należy już do zespołu. Wybierz inną instancję.';
    } else if (!_dirty && !_saving) {
      _read(_agentId);
    }
  }

  String _time(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  void _read(String? id) {
    final schedule = _schedules[id];
    _agentId = id;
    _days = {
      ...(schedule?.days ?? {0, 1, 2, 3, 4}),
    };
    _start = schedule?.start ?? const TimeOfDay(hour: 9, minute: 0);
    _end = schedule?.end ?? const TimeOfDay(hour: 17, minute: 0);
    _enabled = schedule?.enabled ?? (widget.onSave == null);
    _timezone.text = schedule?.timezone ?? 'Europe/Warsaw';
    _dirty = false;
  }

  void _load(String id) {
    setState(() {
      _read(id);
      _error = null;
    });
  }

  Future<void> _pickTime(bool start) async {
    final time = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;
    setState(() {
      _dirty = true;
      if (start) {
        _start = time;
      } else {
        _end = time;
      }
    });
  }

  Future<void> _save() async {
    final agentId = _agentId;
    final startMinutes = _start.hour * 60 + _start.minute;
    final endMinutes = _end.hour * 60 + _end.minute;
    setState(() {
      _error = agentId == null
          ? 'Wybierz instancję bota.'
          : _days.isEmpty
          ? 'Wybierz co najmniej jeden dzień pracy.'
          : endMinutes <= startMinutes
          ? 'Koniec musi być późniejszy niż początek w tym samym dniu.'
          : widget.onSave != null && _timezone.text.trim().isEmpty
          ? 'Podaj strefę czasową IANA, np. Europe/Warsaw.'
          : null;
    });
    if (_error != null || agentId == null) return;
    final days = _days.toList()..sort();
    final schedule = _BotSchedule(
      days: {..._days},
      start: _start,
      end: _end,
      enabled: _enabled,
      timezone: _timezone.text.trim(),
    );
    setState(() => _saving = true);
    try {
      await widget.onSave?.call(agentId, (
        days: days.map((day) => day + 1).toList(),
        startTime: _time(schedule.start),
        endTime: _time(schedule.end),
        enabled: schedule.enabled,
        timezone: schedule.timezone,
      ));
      if (!mounted) return;
      setState(() {
        _schedules[agentId] = schedule;
        _dirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.onSave == null ? 'Harmonogram zapisany lokalnie (demo).' : 'Harmonogram zapisany na serwerze. Nie uruchamia automatycznie bota.',
          ),
        ),
      );
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.agents.isEmpty) {
      return const Text('Brak instancji botów. Najpierw utwórz zespół.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.onSave != null
              ? 'Harmonogram każdej instancji jest zapisywany na serwerze. Godziny dotyczą podanej strefy IANA. Automatyczny start/stop SDK nie jest jeszcze podłączony.'
              : 'Harmonogram pracy botów · czas lokalny przeglądarki. '
                    'DEMO: nie uruchamia ani nie zatrzymuje botów. '
                    'Dane znikają po odświeżeniu strony.',
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Godziny pracy',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey(_agentId),
                  initialValue: _agentId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Bot'),
                  items: [
                    for (final agent in widget.agents)
                      DropdownMenuItem(
                        value: agent.id,
                        child: Text(agent.name),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (id) {
                          if (id != null) _load(id);
                        },
                ),
                const SizedBox(height: 12),
                if (widget.onSave != null) ...[
                  TextField(
                    controller: _timezone,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Strefa czasowa IANA',
                      helperText: 'Np. Europe/Warsaw lub UTC. Czas nie jest przeliczany na strefę przeglądarki.',
                    ),
                    onChanged: (_) => setState(() => _dirty = true),
                  ),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var day = 0; day < _dayNames.length; day++)
                      FilterChip(
                        label: Text(_dayNames[day]),
                        selected: _days.contains(day),
                        onSelected: _saving
                            ? null
                            : (selected) => setState(() {
                                _dirty = true;
                                if (selected) {
                                  _days.add(day);
                                } else {
                                  _days.remove(day);
                                }
                              }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _saving ? null : () => _pickTime(true),
                      icon: const Icon(Icons.schedule),
                      label: Text('Początek: ${_time(_start)}'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : () => _pickTime(false),
                      icon: const Icon(Icons.schedule),
                      label: Text('Koniec: ${_time(_end)}'),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    widget.onSave == null
                        ? 'Harmonogram włączony (demo)'
                        : 'Harmonogram włączony',
                  ),
                  value: _enabled,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _enabled = value;
                          _dirty = true;
                        }),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save),
                  label: const Text('Zapisz harmonogram'),
                ),
                if (_saving) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('Tydzień pracy', style: Theme.of(context).textTheme.titleMedium),
        for (var day = 0; day < _dayNames.length; day++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _dayNames[day],
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  if (!_schedules.values.any(
                    (s) => s.enabled && s.days.contains(day),
                  ))
                    const Text('Brak zaplanowanej pracy.'),
                  for (final agent in widget.agents)
                    if (_schedules[agent.id] case final schedule?
                        when schedule.enabled && schedule.days.contains(day))
                      Text(
                        '${agent.name} · ${_time(schedule.start)}–${_time(schedule.end)}'
                        '${widget.onSave == null ? '' : ' · ${schedule.timezone}'}',
                      ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
